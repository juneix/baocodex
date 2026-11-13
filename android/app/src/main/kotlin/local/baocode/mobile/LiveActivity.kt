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
import io.flutter.plugin.common.EventChannel

/**
 * 状态栏胶囊的一条实时活动。
 *
 * 只做「待处理、运行中、完成未读」三种状态，内容只有状态词和数量，
 * 不放对话正文。走 Android 16 的 Live Update（请求提升为 promoted ongoing），
 * 拿不到 promoted 时退化成普通通知。
 *
 * HyperOS 的超级岛（`miui.focus.param`）不接：那套模板要上架小米商店并通过场景审核
 * 才给 `canShowFocus` 授权，本应用只自用发布，不做这层适配。
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
        detail: String?,
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
            context, kind, chip, text, detail, stopLabel, stopDesktop, stopSession,
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
        detail: String?,
        stopLabel: String?,
        stopDesktop: String?,
        stopSession: String?,
    ): Notification? {
        // 通知卡片第一行：状态词，后面用「丨」接上下文用量；第二行是对话标题。
        // 岛和胶囊只读 chip，看不到 detail，所以第一行不会挤。
        val heading = listOfNotNull(chip.ifEmpty { null }, detail).joinToString("丨")
        @Suppress("DEPRECATION")
        val builder = (if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        })
            // 状态栏小图标必须单色（系统染白），用自己的 logo 剪影，不用系统图。
            .setSmallIcon(R.drawable.ic_stat_live)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.baocodex_logo))
            .setContentTitle(heading)
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
}
