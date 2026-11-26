package local.baocode.mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.CancellationSignal
import android.os.Handler
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** 只读取用户在系统选择器确认的单个 URI；不解析手机文件系统路径。 */
class UploadDocumentPicker(
    private val context: Context,
    private val main: Handler,
    private val activity: () -> FlutterActivity?,
) : AutoCloseable {
    private class Pending(val result: MethodChannel.Result) {
        val cancellation = CancellationSignal()
    }
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: Pending? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "pickUploadFile") return false
        if (pending != null) {
            result.error("upload_pick_busy", "A document selection is already pending", null)
            return true
        }
        val host = activity()
        if (host == null) {
            result.error("no_activity", "Document selection needs a visible activity", null)
            return true
        }
        pending = Pending(result)
        try {
            host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            }, OPEN_DOCUMENT)
        } catch (_: Exception) {
            pending = null
            result.error("upload_pick_failed", "Could not open the document picker", null)
        }
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != OPEN_DOCUMENT) return false
        val request = pending ?: return true
        if (resultCode != Activity.RESULT_OK) {
            pending = null
            request.result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            pending = null
            request.result.error("upload_read_failed", "No document was selected", null)
            return true
        }
        worker.execute {
            try {
                var name = "file"
                val resolver = context.contentResolver
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null, null, null, request.cancellation)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) &&
                            cursor.getLong(sizeIndex) > MAX_BYTES) throw TooLarge()
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex >= 0) {
                            cursor.getString(nameIndex)?.takeIf { it.isNotBlank() }?.let { name = it }
                        }
                    }
                }
                // 元数据可能缺失或不可信：流读取也硬性限制在上限加一个探测字节。
                val bytes = resolver.openAssetFileDescriptor(uri, "r", request.cancellation).use { asset ->
                    checkNotNull(asset)
                    asset.createInputStream().use { input ->
                        request.cancellation.setOnCancelListener { runCatching { input.close() } }
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            request.cancellation.throwIfCanceled()
                            val count = input.read(buffer, 0, minOf(buffer.size, MAX_BYTES - output.size() + 1))
                            if (count < 0) break
                            if (output.size() + count > MAX_BYTES) throw TooLarge()
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                }
                main.post {
                    if (pending === request) {
                        pending = null
                        request.result.success(mapOf("name" to name, "bytes" to bytes))
                    }
                }
            } catch (error: Exception) {
                main.post {
                    if (pending === request) {
                        pending = null
                        request.result.error(
                            if (error is TooLarge) "upload_too_large" else "upload_read_failed",
                            if (error is TooLarge) "Document exceeds 8 MiB" else "Could not read the document",
                            null,
                        )
                    }
                }
            }
        }
        return true
    }

    fun cancel() {
        val request = pending ?: return
        pending = null
        request.cancellation.cancel()
        request.result.success(null)
    }

    override fun close() {
        cancel()
        worker.shutdownNow()
    }

    private class TooLarge : Exception()
    private companion object {
        const val OPEN_DOCUMENT = 47123
        const val MAX_BYTES = 8 * 1024 * 1024
    }
}
