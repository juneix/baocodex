package local.baocode.mobile

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.util.AtomicFile
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors

internal class ChatClipboard(private val context: Context) : AutoCloseable {
    private val clipboard = context.getSystemService(ClipboardManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val record = AtomicFile(File(context.filesDir, "chat_clipboard"))
    private val tokenKey = "${context.packageName}.chatClipboard"
    private val queue = ArrayDeque<() -> Unit>()
    private val results = mutableSetOf<MethodChannel.Result>()
    private var running = false
    @Volatile private var closed = false

    fun write(call: MethodCall, result: MethodChannel.Result) = enqueue(result) {
        val text = call.argument<String>("text")
            ?: throw IllegalArgumentException("缺少剪贴板正文")
        val payload = call.argument<ByteArray>("payload")
            ?: throw IllegalArgumentException("缺少剪贴板数据")
        require(payload.isNotEmpty() && payload.size <= ChatClipboardRecord.MAX_PAYLOAD_BYTES) {
            "剪贴板数据过大或为空"
        }
        val image = call.argument<Map<String, Any>>("image")
        val imageBytes = image?.get("bytes") as? ByteArray
        val type = image?.get("type") as? String
        val extension = when (type) {
            "image/png" -> "png"
            "image/jpeg" -> "jpg"
            "image/gif" -> "gif"
            "image/webp" -> "webp"
            else -> null
        }
        if (image != null) {
            require(imageBytes != null && imageBytes.isNotEmpty() &&
                imageBytes.size <= 8 * 1024 * 1024 && extension != null) {
                "图片格式或大小无效"
            }
        }
        val token = UUID.randomUUID().toString()
        background(result, "clipboard_failed", "无法复制图文，请重试", {
            val imageFile = if (imageBytes == null) null else {
                val folder = File(context.cacheDir, "clipboard_images")
                check(folder.isDirectory || folder.mkdirs()) { "无法创建剪贴板目录" }
                File(folder, "$token.$extension").apply { writeBytes(imageBytes) }
            }
            val output = record.startWrite()
            try {
                output.write(ChatClipboardRecord.encode(token, payload))
                record.finishWrite(output)
            } catch (error: Exception) {
                record.failWrite(output)
                throw error
            }
            imageFile
        }) { imageFile ->
            val clip = if (imageFile == null) ClipData.newPlainText("YCode", text) else {
                val uri = FileProvider.getUriForFile(context,
                    "${context.packageName}.clipboard", imageFile)
                ClipData("YCode", arrayOf(type!!, ClipDescription.MIMETYPE_TEXT_PLAIN),
                    ClipData.Item(text, null, null, uri))
            }
            clip.description.extras = PersistableBundle().apply {
                putString(tokenKey, token)
            }
            clipboard.setPrimaryClip(clip)
            finish(result, null)
        }
    }

    fun read(result: MethodChannel.Result) = enqueue(result) {
        val token = currentToken()
        if (token == null) {
            finish(result, null)
        } else {
            background(result, "clipboard_unavailable", "复制的图片已不可用，请重新复制", {
                record.openRead().use { input ->
                    val size = input.channel.size()
                    if (size <= 0 || size > ChatClipboardRecord.MAX_RECORD_BYTES) {
                        throw IOException("剪贴板记录大小无效")
                    }
                    val saved = ChatClipboardRecord.decode(input.readBytes())
                    check(saved.token == token) { "剪贴板标记已变化" }
                    saved.payload
                }
            }) { payload ->
                finish(result, if (currentToken() == token) payload else null)
            }
        }
    }

    private fun currentToken(): String? =
        clipboard.primaryClip?.description?.extras?.getString(tokenKey)

    private fun enqueue(result: MethodChannel.Result, action: () -> Unit) {
        if (closed) {
            result.error("disposed", "剪贴板窗口已关闭", null)
            return
        }
        results.add(result)
        queue.add {
            try {
                action()
            } catch (_: IllegalArgumentException) {
                finish(result, code = "bad_arguments", message = "剪贴板参数无效")
            } catch (_: Exception) {
                finish(result, code = "clipboard_failed", message = "无法访问剪贴板，请重试")
            }
        }
        next()
    }

    private fun next() {
        if (closed || running || queue.isEmpty()) return
        running = true
        queue.removeFirst().invoke()
    }

    private fun <T> background(
        result: MethodChannel.Result,
        code: String,
        message: String,
        action: () -> T,
        deliver: (T) -> Unit,
    ) {
        worker.execute {
            try {
                check(!closed)
                val value = action()
                main.post {
                    if (!closed && result in results) {
                        try {
                            deliver(value)
                        } catch (_: Exception) {
                            finish(result, code = code, message = message)
                        }
                    }
                }
            } catch (_: Exception) {
                main.post { finish(result, code = code, message = message) }
            }
        }
    }

    private fun finish(
        result: MethodChannel.Result,
        value: Any? = null,
        code: String? = null,
        message: String? = null,
    ) {
        if (!results.remove(result)) return
        if (code == null) result.success(value) else result.error(code, message, null)
        running = false
        next()
    }

    override fun close() {
        if (closed) return
        closed = true
        queue.clear()
        results.toList().forEach {
            it.error("disposed", "剪贴板窗口已关闭，复制结果未确认", null)
        }
        results.clear()
        worker.shutdown()
    }
}
