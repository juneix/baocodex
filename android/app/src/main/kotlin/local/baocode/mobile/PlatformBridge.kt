package local.baocode.mobile

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.HapticFeedbackConstants
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.FrameLayout
import android.widget.ListPopupWindow
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import kotlin.math.roundToInt
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Native, offline facilities only. Secure storage never falls back to plaintext. */
class PlatformBridge(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val methods = MethodChannel(messenger, "local.baocode.mobile/platform")
    private val events = EventChannel(messenger, "local.baocode.mobile/discovery")
    private val main = Handler(Looper.getMainLooper())
    private val storageWorker = Executors.newSingleThreadExecutor()
    private val storageResults = mutableSetOf<MethodChannel.Result>()
    private val preferences = activity.getSharedPreferences("baocode_secure", Context.MODE_PRIVATE)
    private var closed = false
    private var exportResult: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private val permissionWaiters = mutableListOf<(Boolean) -> Unit>()
    private var permissionRequestPending = false
    private var permissionMenu: ListPopupWindow? = null
    private var permissionAnchor: View? = null
    private var permissionMenuResult: MethodChannel.Result? = null

    private val localDiscovery = LocalDiscovery(activity.applicationContext, main)
    private val chatClipboard = ChatClipboard(activity.applicationContext)
    private val updates = AndroidUpdates(activity)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(localDiscovery)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("disposed", "Platform bridge is closed", null)
            return
        }
        try {
            if (updates.handle(call, result)) return
            when (call.method) {
                "secureRead" -> {
                    val key = requiredString(call, "key")
                    storage(result) { readSecret(key) }
                }
                "secureWrite" -> {
                    val key = requiredString(call, "key")
                    val value = requiredString(call, "value", allowEmpty = true)
                    storage(result) { writeSecret(key, value); null }
                }
                "secureRemove" -> {
                    val key = requiredString(call, "key")
                    storage(result) {
                        check(preferences.edit().remove(key).commit()) { "Secure removal could not be persisted" }
                        null
                    }
                }
                "permissionMenu" -> showPermissionMenu(call, result)
                "saveFile" -> saveFile(call, result)
                "writeChatClipboard" -> chatClipboard.write(call, result)
                "readChatClipboard" -> chatClipboard.read(result)
                "discoveryStart" -> localDiscovery.start(result)
                "discoveryStop" -> { localDiscovery.stop(); result.success(null) }
                "discoveryRefresh" -> { localDiscovery.refresh(); result.success(null) }
                "haptic" -> { haptic(call.argument<String>("kind")); result.success(null) }
                "notificationPermission" -> result.success(notificationAllowed())
                "requestNotificationPermission" -> requestNotificationPermission { result.success(it) }
                "notify" -> {
                    val title = requiredString(call, "title", allowEmpty = true)
                    val body = requiredString(call, "body", allowEmpty = true)
                    val rawId = call.argument<Any>("id")
                    val id = when (rawId) {
                        is Number -> rawId.toInt()
                        is String -> rawId.toIntOrNull() ?: rawId.hashCode()
                        else -> throw IllegalArgumentException("id must be an integer or string")
                    }
                    // Background events must never trigger a permission dialog.
                    // Permission is requested only from the explicit settings action.
                    if (!notificationAllowed()) {
                        result.error("notification_permission_denied", "Notifications were not allowed", null)
                    } else {
                        postNotification(id, title, body)
                        result.success(null)
                    }
                }
                "openAppSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(if (error is IllegalArgumentException) "bad_arguments" else "platform_failed",
                error.message, null)
        }
    }

    /** Flutter 坐标换成原生锚点；这里只展示选项，不申请系统权限。 */
    private fun showPermissionMenu(call: MethodCall, result: MethodChannel.Result) {
        val options = call.argument<List<*>>("options")?.map { entry ->
            val value = entry as? Map<*, *> ?: throw IllegalArgumentException("Invalid option")
            val id = value["id"] as? String ?: throw IllegalArgumentException("Missing option id")
            val label = value["label"] as? String ?: throw IllegalArgumentException("Missing option label")
            require(id.isNotEmpty() && label.isNotEmpty()) { "Empty option" }
            id to label
        } ?: throw IllegalArgumentException("Missing options")
        require(options.isNotEmpty() && options.size <= 128) { "Invalid option count" }
        fun coordinate(key: String): Int {
            val value = call.argument<Number>(key)?.toDouble()
                ?: throw IllegalArgumentException("Missing coordinate")
            require(value.isFinite()) { "Invalid coordinate" }
            return value.roundToInt()
        }
        val x = coordinate("x")
        val y = coordinate("y")
        val width = coordinate("width")
        val height = coordinate("height")
        require(width > 0 && height > 0) { "Invalid anchor size" }
        val root = requireNotNull(activity.findViewById<FrameLayout>(android.R.id.content))
        val flutter = findFlutterView(root) ?: root
        val flutterAt = IntArray(2).also { flutter.getLocationOnScreen(it) }
        val rootAt = IntArray(2).also { root.getLocationOnScreen(it) }
        val density = activity.resources.displayMetrics.density
        val dark = call.argument<Boolean>("dark") == true
        val themed = ContextThemeWrapper(activity,
            if (dark) android.R.style.Theme_Material_NoActionBar
            else android.R.style.Theme_Material_Light_NoActionBar)
        val anchor = View(activity).apply {
            alpha = 0f
            isClickable = false
            isFocusable = false
            translationX = (x + flutterAt[0] - rootAt[0]).toFloat()
            translationY = (y + flutterAt[1] - rootAt[1]).toFloat()
        }
        val popup = ListPopupWindow(themed).apply {
            setAdapter(ArrayAdapter(themed, android.R.layout.simple_list_item_1,
                options.map { it.second }))
            anchorView = anchor
            isModal = true
            inputMethodMode = ListPopupWindow.INPUT_METHOD_NOT_NEEDED
            this.width = minOf(maxOf(width, (160 * density).roundToInt()),
                (root.width - 32 * density).roundToInt().coerceAtLeast(1))
            setOnItemClickListener { _, _, index, _ ->
                if (index in options.indices) completePermissionMenu(options[index].first)
            }
            setOnDismissListener { completePermissionMenu(null) }
        }
        completePermissionMenu(null)
        permissionMenu = popup
        permissionAnchor = anchor
        permissionMenuResult = result
        root.addView(anchor, FrameLayout.LayoutParams(width, height))
        anchor.post {
            if (closed || permissionMenu !== popup) return@post
            try {
                popup.show()
                val selected = call.argument<String>("selected")
                val index = options.indexOfFirst { it.first == selected }
                if (index >= 0) popup.setSelection(index)
            } catch (_: Exception) {
                val pending = permissionMenuResult
                permissionMenuResult = null
                completePermissionMenu(null)
                pending?.error("platform_failed", "The menu could not be opened", null)
            }
        }
    }

    private fun findFlutterView(view: View): View? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun completePermissionMenu(value: String?) {
        val popup = permissionMenu
        val anchor = permissionAnchor
        val pending = permissionMenuResult
        permissionMenu = null
        permissionAnchor = null
        permissionMenuResult = null
        popup?.setOnDismissListener(null)
        popup?.dismiss()
        if (anchor != null) (anchor.parent as? ViewGroup)?.removeView(anchor)
        pending?.success(value)
    }

    private fun requiredString(call: MethodCall, key: String, allowEmpty: Boolean = false): String {
        val value = call.argument<String>(key)
            ?: throw IllegalArgumentException("Missing $key")
        require(allowEmpty || value.isNotEmpty()) { "$key must not be empty" }
        return value
    }

    private fun storage(result: MethodChannel.Result, action: () -> Any?) {
        storageResults.add(result)
        storageWorker.execute {
            try {
                val value = action()
                main.post {
                    if (storageResults.remove(result)) result.success(value)
                }
            } catch (error: Exception) {
                // Do not return ciphertext, plaintext, or private keys in error details.
                main.post {
                    if (storageResults.remove(result)) {
                        result.error("secure_storage_failed", "Secure storage operation failed", null)
                    }
                }
            }
        }
    }

    private fun secretKey(create: Boolean): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            return keyStore.getKey(KEY_ALIAS, null) as? SecretKey
                ?: throw IllegalStateException("Secure storage key is unavailable")
        }
        check(create) { "Secure storage key is missing" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build())
        }.generateKey()
    }

    private fun readSecret(key: String): String? {
        val stored = preferences.getString(key, null) ?: return null
        val parts = stored.split(':')
        check(parts.size == 3 && parts[0] == "1") { "Invalid secure storage record" }
        val iv = Base64.decode(parts[1], Base64.NO_WRAP)
        check(iv.size == 12) { "Invalid secure storage nonce" }
        val encrypted = Base64.decode(parts[2], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(create = false), GCMParameterSpec(128, iv))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    private fun writeSecret(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey(create = true))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val record = "1:${Base64.encodeToString(cipher.iv, Base64.NO_WRAP)}:" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
        check(preferences.edit().putString(key, record).commit()) {
            "Secure value could not be persisted"
        }
    }

    private fun saveFile(call: MethodCall, result: MethodChannel.Result) {
        if (exportResult != null) {
            result.error("save_busy", "已有文件正在保存", null)
            return
        }
        val name = requiredString(call, "name")
        require(name.isNotBlank() && name != "." && name != ".." &&
            name.none { it == '/' || it == '\\' || it == '\u0000' }) { "保存文件名无效" }
        val bytes = call.argument<ByteArray>("bytes")
            ?: throw IllegalArgumentException("缺少文件数据")
        require(bytes.size <= MAX_EXPORT_BYTES) { "文件超过 8 MiB 下载上限" }
        exportResult = result
        exportBytes = bytes
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, name)
            }, SAVE_DOCUMENT)
        } catch (_: Exception) {
            exportResult = null
            exportBytes = null
            result.error("save_failed", "无法打开系统文件保存器", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == SAVE_DOCUMENT) {
            val result = exportResult ?: return true
            val bytes = exportBytes
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK) {
                exportResult = null
                exportBytes = null
                result.success(false)
                return true
            }
            if (uri == null || bytes == null) {
                exportResult = null
                exportBytes = null
                result.error("save_failed", "未收到保存目标", null)
                return true
            }
            // 只有用户在系统选择器确认后才写入，不申请全盘存储权限。
            storageWorker.execute {
                try {
                    activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                        checkNotNull(output) { "无法打开保存目标" }
                        output.write(bytes)
                    }
                    main.post {
                        if (exportResult === result) {
                            exportResult = null
                            exportBytes = null
                            result.success(true)
                        }
                    }
                } catch (_: Exception) {
                    main.post {
                        if (exportResult === result) {
                            exportResult = null
                            exportBytes = null
                            result.error("save_failed", "文件保存失败，请检查所选位置", null)
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    private fun haptic(kind: String?) {
        val feedback = when (kind) {
            "selection", "light" -> HapticFeedbackConstants.CLOCK_TICK
            "heavy", "error" -> HapticFeedbackConstants.LONG_PRESS
            "success" -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM
                else HapticFeedbackConstants.VIRTUAL_KEY
            "warning" -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT
                else HapticFeedbackConstants.LONG_PRESS
            else -> HapticFeedbackConstants.VIRTUAL_KEY
        }
        activity.window.decorView.performHapticFeedback(feedback)
    }

    private fun notificationAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return Build.VERSION.SDK_INT < 24 || manager.areNotificationsEnabled()
    }

    private fun requestNotificationPermission(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            callback(notificationAllowed())
            return
        }
        permissionWaiters.add(callback)
        if (permissionRequestPending) return
        permissionRequestPending = true
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION)
        } catch (error: Exception) {
            permissionRequestPending = false
            val waiting = permissionWaiters.toList()
            permissionWaiters.clear()
            waiting.forEach { it(false) }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION || !permissionRequestPending) return false
        permissionRequestPending = false
        val allowed = notificationAllowed()
        val waiting = permissionWaiters.toList()
        permissionWaiters.clear()
        waiting.forEach { it(allowed) }
        return true
    }

    private fun postNotification(id: Int, title: String, body: String) {
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            // 已存在的通道不会因再次 create 而改名：名字和当前不同就先删了重建。
            val existing = manager.getNotificationChannel(NOTIFICATION_CHANNEL)
            if (existing != null && existing.name.toString() != NOTIFICATION_CHANNEL_NAME) {
                manager.deleteNotificationChannel(NOTIFICATION_CHANNEL)
            }
            manager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL,
                NOTIFICATION_CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT))
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(activity, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity)
        }
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
        activity.packageManager.getLaunchIntentForPackage(activity.packageName)?.let { launch ->
            launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            builder.setContentIntent(PendingIntent.getActivity(activity, id, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        manager.notify(id, builder.build())
    }

    override fun close() {
        if (closed) return
        closed = true
        completePermissionMenu(null)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        localDiscovery.close()
        chatClipboard.close()
        updates.close()
        exportResult?.error("disposed", "文件保存窗口已关闭，保存结果未确认", null)
        exportResult = null
        exportBytes = null
        val waiting = permissionWaiters.toList()
        permissionWaiters.clear()
        permissionRequestPending = false
        waiting.forEach { it(false) }
        storageResults.toList().forEach { it.error("disposed", "Secure storage host was destroyed", null) }
        storageResults.clear()
        storageWorker.shutdown()
    }

    private companion object {
        const val KEY_ALIAS = "baocode.mobile.secure.v1"
        const val NOTIFICATION_PERMISSION = 47121
        const val SAVE_DOCUMENT = 47122
        const val MAX_EXPORT_BYTES = 8 * 1024 * 1024
        const val NOTIFICATION_CHANNEL = "baocode.mobile.local"
        const val NOTIFICATION_CHANNEL_NAME = "BaoCodeX"
    }
}
