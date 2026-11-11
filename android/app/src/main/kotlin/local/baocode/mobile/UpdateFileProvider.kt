package local.baocode.mobile

import androidx.core.content.FileProvider

/**
 * 更新安装包与剪贴板图片使用独立的 FileProvider 子类。Android 按类名区分 provider；
 * 两个都写同一个类名时只有一个生效，系统安装器读更新包会落到
 * 剪贴板那个，读不到文件，就报「安装包已损坏」。
 */
class UpdateFileProvider : FileProvider()

class ClipboardFileProvider : FileProvider()
