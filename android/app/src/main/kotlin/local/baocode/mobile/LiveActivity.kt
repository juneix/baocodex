package local.baocode.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.EventChannel

/**
 * 状态栏胶囊 / HyperOS 灵动岛的一条实时活动。
 *
 * 只做「待处理、运行中、完成未读」三种状态，内容只有状态词和数量，
 * 不放对话正文。走 Android 16 的 Live Update（请求提升为 promoted ongoing），
 * 小米 HyperOS 3 会把它画进超级岛；拿不到 promoted 或焦点授权时退化成普通通知。
 *
 * 有任务时由 [LiveService] 顶住进程，后台连接不断；空闲即停，不注册开机广播，不自启。
 */
object LiveActivity {
    private const val CHANNEL = "baocode.mobile.live"
    private const val CHANNEL_NAME = "运行状态"
    const val ID = 9003

    /** 通知上「停止」按钮的广播动作。 */
    const val ACTION_STOP = "local.baocode.mobile.action.LIVE_STOP"
    const val EXTRA_DESKTOP = "desktop"
    const val EXTRA_SESSION = "session"

    /** 原生把「停止」按下的结果推回 Dart；没有宿主时为 null。 */
    var eventSink: EventChannel.EventSink? = null

    /** `Notification.EXTRA_REQUEST_PROMOTED_ONGOING`（Android 16 QPR1+）。 */
    private const val EXTRA_PROMOTED = "android.requestPromotedOngoing"

    /** HyperOS 焦点通知（超级岛）模板的键。 */
    private const val XIAOMI_PARAM = "miui.focus.param"
    private const val XIAOMI_PICS = "miui.focus.pics"
    private const val XIAOMI_PIC_ICON = "miui.focus.pic_icon"
    private const val XIAOMI_PROTOCOL = "notification_focus_protocol"
    private const val XIAOMI_PROVIDER = "content://miui.statusbar.notification.public"
    private const val XIAOMI_TTL_MS = 60_000L

    private var focusCheckedAt = 0L
    private var focusAllowed = false

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = manager(context)
        if (manager.getNotificationChannel(CHANNEL) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            },
        )
    }

    /**
     * 更新那一条。[kind] 是 `waiting` / `running` / `done`，其余忽略。
     * 返回是否真的发出了通知（没宿主或没权限时为 false）。
     */
    fun update(
        context: Context,
        kind: String,
        chip: String,
        text: String,
        title: String?,
        stopLabel: String?,
        stopDesktop: String?,
        stopSession: String?,
        keepAlive: Boolean,
    ): Boolean {
        val valid = when (kind) {
            "waiting", "running", "done" -> true
            else -> false
        }
        if (!valid) {
            clear(context)
            return false
        }
        ensureChannel(context)
        val notification = build(
            context, kind, chip, text, title, stopLabel, stopDesktop, stopSession,
        ) ?: return false

        // 有会话在跑就顶住进程，连接与心跳才不会停、进度才实时（keepAlive 由 Dart 判）。
        // 没有在跑的（仅待处理/完成）不耗电保活，通知留着靠自身超时收起。
        LiveService.show(context, notification, keep = keepAlive)

        return runCatching {
            manager(context).notify(ID, notification)
            true
        }.getOrDefault(false)
    }

    /** 只建通知不发出，供前台服务 [LiveService] 复用来进入前台。 */
    fun build(
        context: Context,
        kind: String,
        chip: String,
        text: String,
        title: String?,
        stopLabel: String?,
        stopDesktop: String?,
        stopSession: String?,
    ): Notification? {
        @Suppress("DEPRECATION")
        val builder = (if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        })
            // 状态栏小图标仍要单色（系统会染成纯白），应用自己的彩色图标走大图。
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.baocodex_logo))
            .setContentTitle(chip)
            .setContentText(text.ifEmpty { null })
            .setContentIntent(openIntent(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(
                if (kind == "running") Notification.CATEGORY_PROGRESS
                else Notification.CATEGORY_STATUS,
            )
            .setVisibility(Notification.VISIBILITY_PRIVATE)

        // 运行中：胶囊里的计时从开始跑起算。
        if (kind == "running") {
            builder.setWhen(System.currentTimeMillis()).setShowWhen(true)
        }
        // 完成：短暂停留后自动撤，避免一直挂着（setTimeoutAfter 需要 API 26）。
        if (kind == "done" && Build.VERSION.SDK_INT >= 26) {
            builder.setTimeoutAfter(5 * 60_000L)
        }

        // 运行中：通知上给一个「停止」按钮，不必打开 App 就能停掉这一轮。
        if (kind == "running" && stopLabel != null &&
            stopDesktop != null && stopSession != null
        ) {
            runCatching { builder.addAction(stopAction(context, stopLabel, stopDesktop, stopSession)) }
        }

        // Android 16：请求提升为 Live Update（状态栏胶囊、锁屏、岛）。
        builder.addExtras(Bundle().apply { putBoolean(EXTRA_PROMOTED, true) })
        if (Build.VERSION.SDK_INT >= 36) {
            runCatching { builder.setShortCriticalText(chip) }
        }

        // HyperOS 超级岛：拿到焦点授权才加模板，否则跳过。
        if (xiaomiFocusAllowed(context)) {
            runCatching {
                builder.addExtras(
                    Bundle().apply {
                        putString(XIAOMI_PARAM, xiaomiParam(kind, chip, text, title))
                        putBundle(
                            XIAOMI_PICS,
                            Bundle().apply {
                                putParcelable(
                                    XIAOMI_PIC_ICON,
                                    Icon.createWithResource(context, R.mipmap.app_icon),
                                )
                            },
                        )
                    },
                )
            }
        }

        return runCatching { builder.build() }.getOrNull()
    }

    fun clear(context: Context) {
        LiveService.stop(context)
        runCatching { manager(context).cancel(ID) }
    }

    private fun openIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        ID,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** 通知上的「停止」：发一条广播，由 [LiveStopReceiver] 转给还活着的引擎。 */
    private fun stopAction(
        context: Context,
        label: String,
        desktop: String,
        session: String,
    ): Notification.Action {
        val intent = Intent(context, LiveStopReceiver::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_DESKTOP, desktop)
            putExtra(EXTRA_SESSION, session)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            1,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_close_clear_cancel),
            label,
            pending,
        ).build()
    }

    /** HyperOS 焦点通知模板：小岛只放状态词，卡片放状态词和一句说明。 */
    private fun xiaomiParam(kind: String, chip: String, text: String, title: String?): String {
        fun esc(value: String): String = value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", " ")
        val word = esc(chip.take(6))
        val line = esc(text.take(40))
        val heading = esc((title ?: chip).take(20))
        val pic = "{\"type\":1,\"pic\":\"miui.focus.pic_icon\"}"
        return "{\"param_v2\":{" +
            "\"protocol\":1," +
            "\"business\":\"ycode_live_$kind\"," +
            "\"updatable\":true," +
            "\"enableFloat\":false," +
            "\"ticker\":\"$word · $heading\"," +
            "\"aodTitle\":\"$word\"," +
            "\"param_island\":{" +
            "\"islandProperty\":1," +
            "\"bigIslandArea\":{\"imageTextInfoLeft\":{\"type\":1,\"picInfo\":$pic," +
            "\"textInfo\":{\"title\":\"$word\"}}}," +
            "\"smallIslandArea\":{\"picInfo\":$pic}" +
            "}," +
            "\"baseInfo\":{\"type\":2,\"title\":\"$heading\",\"content\":\"$line\"}" +
            "}}"
    }

    /** HyperOS 3 且 SystemUI 允许本应用显示焦点通知；一分钟内复用结果。 */
    private fun xiaomiFocusAllowed(context: Context): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (now - focusCheckedAt < XIAOMI_TTL_MS) return focusAllowed
        focusCheckedAt = now
        focusAllowed = runCatching {
            val protocol = Settings.System.getInt(
                context.contentResolver,
                XIAOMI_PROTOCOL,
                0,
            )
            if (protocol < 1) return@runCatching false
            val extras = Bundle().apply { putString("package", context.packageName) }
            context.contentResolver
                .call(
                    android.net.Uri.parse(XIAOMI_PROVIDER),
                    "canShowFocus",
                    null,
                    extras,
                )
                ?.getBoolean("canShowFocus", false) == true
        }.getOrDefault(false)
        return focusAllowed
    }
}
