package local.baocode.mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 通知上「停止」按钮的落点：把要停的会话推回 Dart。
 *
 * 尽力而为——进程还活着、Dart 侧在听时才能真正停掉；进程已被系统回收时
 * 这条广播无人处理，通知本身也会随进程消失，属于可接受的降级。
 */
class LiveStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != LiveActivity.ACTION_STOP) return
        val sink = LiveActivity.eventSink ?: return
        val desktop = intent.getStringExtra(LiveActivity.EXTRA_DESKTOP)
        val session = intent.getStringExtra(LiveActivity.EXTRA_SESSION)
        if (desktop == null || session == null) return
        sink.success(mapOf("desktop" to desktop, "session" to session))
    }
}
