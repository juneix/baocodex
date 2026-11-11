package local.baocode.mobile

import androidx.core.content.FileProvider

/**
 * 更新安装包专用的 FileProvider。Android 按类名区分 provider，剪贴板图片已经用了
 * FileProvider 本身；两个都写同一个类名时只有一个生效，系统安装器读更新包会落到
 * 剪贴板那个，读不到文件，就报「安装包已损坏」。
 */
class UpdateFileProvider : FileProvider()
