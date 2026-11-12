# BaoCodeX：Android 云构建、签名与发布

应用显示名 **BaoCodeX**，安装包名固定为 `juneix.baocodex`。当前源码版本为 `1.0.3+1`，只发布 arm64 APK。

这是独立安装，不覆盖原 YCode 或 YCode Preview，也不自动迁移它们的配对与草稿。保留旧应用，在 BaoCodeX 中重新配对；之后 BaoCodeX 的覆盖更新必须保持同一包名、同一签名和更高构建号。

## 构建与验证环境

APK 的静态分析、Flutter 测试、构建、签名与签名校验全部在 GitHub Actions 执行。本机不安装 Android SDK/NDK、Gradle、签名工具或模拟器，也不运行本地 Android 构建或测试套件。

唯一的本机 Android 调试入口是已有 adb 连接真机，检查云端生成的产物。排障先看构建或设备日志，不为验证而自动启动测试服务。

## GitHub Actions 预览版

`.github/workflows/android.yml` 在 main 的相关文件推送或手动运行时执行：恢复锁定依赖，运行 `flutter analyze --no-pub` 和 `flutter test --no-pub`，再构建、签名、发布 arm64 pre-release。

**整条工作流包含发布，不是仅检查。**它会创建版本标签和公开附件；只有确实准备发布时才触发，不把代码修改或本地提交当作推送/发布授权。

- 仓库变量 `FLUTTER_VERSION` 使用确认过的精确 `3.47.x`；手动运行可用 `flutter_version` 临时覆盖。对应 Dart 必须满足 `^3.13.4`。
- 使用 JDK 21、Rust 1.97.1 和所选 Flutter。不再使用 `YCODE_TEST_INSTALL` / `YCODE_PREVIEW` 等历史预览标记；安装包名与显示名固定，不追加后缀。
- 将 `${{ github.repository }}` 注入 `YCODE_REPOSITORY`。工具与应用的默认值为当前 fork `juneix/ycode`，不能误指上游发布源。
- 签名 Secrets 保持 `YCODE_RELEASE_JKS_BASE64`、`YCODE_RELEASE_STORE_PASSWORD`、`YCODE_RELEASE_KEY_ALIAS`、`YCODE_RELEASE_KEY_PASSWORD`。名称不随应用改名重置；工作流不回退到随机或 debug 签名。
- artifact 名为 `baocodex-android-preview-<run_id>-<run_attempt>`，包含 `BaoCodeX-<版本名>-<构建号>.apk` 与 `latest.json`。
- 版本标签为 `v<版本名>`，标题为 `BaoCodeX <版本名> Preview`，保持 pre-release、不标 latest。附件齐全前保持 draft，最后才公开。
- 同名标签只能在仍指向当前提交时重跑；标签指向其他提交时应递增版本，不能强制移动。

仓库由维护者手动改名。建议在首个长期使用的 BaoCodeX 包构建前完成，让实际仓库写入更新源；不能假设 GitHub 跳转会绕过严格 URL 校验而自动适配后续改名。

## 既有签名与初始化

继续使用现有云端签名密钥，不因 BaoCodeX 改名重新生成密钥。历史 alias、DN、`YCODE_*` Secret 名称和私有配置路径属于内部兼容数据，不是应用显示名。

`.github/workflows/init-signing.yml` 仅支持首次手动初始化，发现 `YCODE_RELEASE_JKS_BASE64` 已存在会拒绝覆盖。它使用仓库公钥变量 `YCODE_SECRETS_PUBLIC_KEY` / `YCODE_SECRETS_KEY_ID` 加密 Secrets，不输出或上传明文 JKS、口令。既有 `ycode-preview` alias 和 `CN=YCode Preview` 可以继续使用，不必为了改名重建。

签名配置只在 runner 临时目录存在，退出时清理。初始化的加密 artifact 只用于将密文写入当前仓库 Secrets；配置完成后清理下载的密文。GitHub Secrets 无法读回，不能删除这四项，否则无法继续同签名更新。

## 版本与产物命名

`pubspec.yaml` 的格式为 `版本名+构建号`，本版 `1.0.3+1`：

- 版本名按三段数字比较；新版本的版本名递增。
- 构建号独立维护，只增不减，不能重复或依赖 Git 提交数量。
- `APP_VERSION` 由云构建脚本传入；省略时设置页只能显示 `dev`。
- APK 使用 `BaoCodeX-<版本名>-<构建号>.apk`，如 `BaoCodeX-1.0.3-1.apk`。构建脚本、manifest、上传 glob、发布正则和应用更新识别必须一致。
- `README.md` / `README_CN.md`、`CHANGELOG.md` / `CHANGELOG_CN.md` 同步；新增版本日志使用 `## 0.1.12` 等数字节标题，历史记录不全局改名。

云端 `tool/build_android.sh --no-install` 保留 `GeneratedPluginRegistrant.java`，临时移除测试插件注册后无论成功/失败都恢复，不删除或提交生成代码变动。它构建 arm64，并用 runner 的 build-tools 对齐、签名和校验。

`tool/release_manifest.dart` 按 pubspec、真实 APK 和英中日志生成 `latest.json`，不要手改大小或 SHA-256。仓库参数由 CI 注入，说明英文在前，`<!-- zh -->` 分隔后是中文，应用只显示当前语言。

## 安装与真实验收

云端成功后，先检查产物包名、版本、构建号、签名和摘要，再在明确授权的真机上安装。只调试云端产物，不在本机签名、校验 APK 或运行 Android 测试套件。

- 首次安装 BaoCodeX 保留旧应用，需要重新配对。
- 后续覆盖安装确认配对与本地数据保留；包名/签名不一致不能覆盖，不能擅自卸载。
- 检查新对话、侧栏/左右入口、返回、项目选择、图片/文件/命令、发送/停止、模型/权限/模式，以及 Bot 的当前会话和原生菜单。
- 外部行为连接授权的真实电脑验证；测试用合成数据不能替代真实 API 或硬件验收。
- 失败贴真实日志，未执行或未验证明确说明；不能把旧版本的成功记录当作新版本验收。

## 更新安全策略

应用只识别 BaoCodeX 安装附件，校验当前配置仓库、同一 Release 标签下的 GitHub URL、架构、大小和可用的 SHA-256。安装时继续校验本应用包名、同一签名、Release 版本和更高构建号，不为改名放宽策略。

预览渠道仍手动下载 pre-release；自动更新只查稳定版。系统安装器与“允许安装未知应用”流程保留用户确认，不静默安装、不绕过权限。

每个 FileProvider 继续使用自己的子类，更新和剪贴板不可共用 `androidx.core.content.FileProvider` 类名；authorities 随实际 applicationId 生成。只操作本项目应用，不操作其他已安装应用。

不提交构建产物、配对数据、真实聊天、令牌或签名材料，不强行跟踪被忽略的文件。
