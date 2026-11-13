package local.baocode.mobile

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 极简前台服务：只为让进程在后台不被系统冻结，好让 Dart 的心跳继续、连接不断。
 *
 * 不持有引擎、不另起通知——它显示的就是 [LiveActivity] 那条（同一个 ID），
 * 用户看到的始终只有一条。有会话在跑时保持前台；完成态把通知脱离前台持有
 * （`STOP_FOREGROUND_DETACH`）后自己停下，通知留着靠自身超时收起。
 *
 * `START_NOT_STICKY`：被系统回收或用户强行停止后不自启，要重新打开 App 才回来。
 * 不申请忽略电池优化，不注册开机广播。
 */
class LiveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        @Suppress("DEPRECATION")
        val notification = intent.getParcelableExtra<Notification>(EXTRA_NOTIFICATION)
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val keep = intent.getBooleanExtra(EXTRA_KEEP, true)
        // 先满足「5 秒内进前台」的硬性要求，再决定是留是走。
        val foregrounded = try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    LiveActivity.ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
                )
            } else {
                startForeground(LiveActivity.ID, notification)
            }
            true
        } catch (error: RuntimeException) {
            // 系统拒绝进前台（权限/类型不允许）：退化为普通通知，不空跑服务。
            false
        }
        if (!foregrounded) {
            running = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (keep) {
            running = true
        } else {
            // 完成态：通知脱离前台持有，留在状态栏靠自身超时收起，服务自己停。
            stopForeground(STOP_FOREGROUND_DETACH)
            running = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_NOTIFICATION = "notification"
        private const val EXTRA_KEEP = "keep"

        /** 服务是否已在跑；避免每次状态更新都重复 start。 */
        @Volatile
        private var running = false

        /**
         * 让服务显示 [notification]。[keep] 为 true（运行中/等你处理）时保持前台保活；
         * 为 false（完成态）时只短暂进前台满足系统要求，随后脱离并停下，通知留下。
         *
         * 统一走 `startForegroundService`：已在跑的服务被再次投递是允许的，
         * 也能覆盖完成态在后台到达的情况。
         */
        fun show(context: Context, notification: Notification, keep: Boolean) {
            if (keep) {
                // 已在保活：前台通知就是同一条（ID 相同），调用方的 notify 会改写它。
                if (running) return
            } else if (!running) {
                // 没在保活就不必为完成态专门起一次服务，普通通知照常显示即可。
                return
            }
            val intent = Intent(context, LiveService::class.java)
                .putExtra(EXTRA_NOTIFICATION, notification)
                .putExtra(EXTRA_KEEP, keep)
            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: RuntimeException) {
                /* 系统不允许时静默跳过，普通通知仍显示。 */
            }
        }

        /** 彻底停止：撤服务，通知由调用方随后 cancel。 */
        fun stop(context: Context) {
            running = false
            runCatching { context.stopService(Intent(context, LiveService::class.java)) }
        }
    }
}
