# 构建、签名与发布（Android）

应用名 **YCode**，包名 `local.ycode.mobile`。正式版仅发布 arm64 APK。升级必须保持同一包名和正式签名，并使用更高的 Android 构建号，才能覆盖安装、保留配对和聊天记录。

## 本地环境

安装 Flutter、JDK 21、Android SDK/NDK、Rust 和 adb。设置 `ANDROID_HOME`（或 `ANDROID_SDK_ROOT`），将 Flutter 和 SDK 的 `platform-tools` 加入 `PATH`。JDK 不在标准位置时设置 `JAVA_HOME`；macOS 打包脚本也会尝试已安装的 Homebrew `openjdk@21`。

`android/local.properties` 仅保存本机路径，不提交，例如：

```properties
sdk.dir=/path/to/Android/sdk
flutter.sdk=/path/to/flutter
```

Windows 可以使用 `tool/prepare_android.ps1 -FlutterSdk <路径> -AndroidSdk <路径>`。首次构建前运行 `flutter pub get`。

## GitHub Actions 个人预览版

`.github/workflows/android.yml` 只在 main 的相关文件推送或手动运行时执行：先以锁文件恢复依赖，再运行 `flutter analyze --no-pub` 和 `flutter test --no-pub`，随后构建、签名并发布可与正式版并存的 arm64 预览 APK。它创建或更新数字版本标签 `v<版本名>` 对应的 **pre-release**，标题为 `YCode <版本名> Preview`，不会标记为 latest，也不会写入上游仓库。

- 设置仓库变量 `FLUTTER_VERSION` 为确认过的精确 `3.47.x` 版本；手动运行可以用 `flutter_version` 输入临时覆盖。Flutter 自带的 Dart 必须满足 `^3.13.4`。
- 构建固定使用 JDK 21、Rust 1.97.1 和所选 Flutter，传入 `YCODE_TEST_INSTALL=true`，因此 Android 工程启用 `-PtestInstall=true`，Dart 获得 `YCODE_PREVIEW=true`；同时将 `${{ github.repository }}` 作为 `YCODE_REPOSITORY`，让该 fork 的预览版只检查自己的 Release。
- 配置 Secrets：`YCODE_RELEASE_JKS_BASE64`、`YCODE_RELEASE_STORE_PASSWORD`、`YCODE_RELEASE_KEY_ALIAS`、`YCODE_RELEASE_KEY_PASSWORD`。工作流不回退到随机或 debug 签名；签名配置只写入 runner 临时目录并在退出时清理。
- 构建 artifact 名为 `ycode-android-preview-<run_id>-<run_attempt>`，包含 `ycode-<版本名>-<构建号>.apk` 与 `latest.json`；同一提交重跑会覆盖 Release 中的同名附件。发布 job 在附件齐全前保持 draft，最后才公开为 pre-release。
- 已存在的标签只有在仍指向当前 `GITHUB_SHA` 时才能重跑；若同名标签指向其他提交，工作流会失败并要求递增版本，不会强制移动标签。

### 首次初始化个人预览签名

`.github/workflows/init-signing.yml` 只支持手动运行，且发现 `YCODE_RELEASE_JKS_BASE64` 已存在时会拒绝生成或覆盖。初始化前，从本仓库 `actions/secrets/public-key` 接口取得公钥和 key id，分别存为公开仓库变量 `YCODE_SECRETS_PUBLIC_KEY`、`YCODE_SECRETS_KEY_ID`。

工作流用 JDK 21 的 `keytool` 一次生成 alias 为 `ycode-preview`、DN 仅为 `CN=YCode Preview` 的 JKS，并生成随机强口令；口令经环境变量传给 `keytool`。`tool/seal_signing.py` 使用云端固定安装的 PyNaCl 1.5.0 和 GitHub 公钥，以 libsodium SealedBox 加密四个 Secret。它只输出如下 JSON，不输出或上传明文 JKS、口令：

```json
{"YCODE_RELEASE_JKS_BASE64":{"key_id":"...","encrypted_value":"..."}}
```

实际 JSON 同时含四个 Secret 的映射。加密 artifact 名为 `ycode-encrypted-signing-<run_id>-<run_attempt>`，保留 1 天；下载后可使用已登录且有仓库管理权限的 GitHub CLI，将每项 `{key_id, encrypted_value}` PUT 到**本仓库** Actions Secrets。无需在仓库中保存额外 PAT，也不下载明文 JKS。配置完 Secrets 后删除本地下载的密文；GitHub Secrets 无法读回，不能删除这四项，否则无法继续对同一预览包名做同签名升级。

本机没有安卓环境时只改源码和工作流，不安装 SDK/Gradle，也不进行本地 APK 构建、签名或模拟器测试。

## 正式签名：Mac 与 Windows 共用同一把密钥

密钥放在 `~/.android/ycode-release.jks`，配置放在同目录的 `ycode-release.properties`。Windows 的 `~` 是当前用户主目录；Git Bash 和 macOS 都使用同样的文件名和相对路径。

配置包含 `storeFile`、`storePassword`、`keyAlias`、`keyPassword` 四项。`storeFile` 写 `ycode-release.jks`，相对配置所在目录解析，换电脑不用改。配置放在其他位置时，用 `YCODE_SIGNING` 指定完整路径。

**换电脑要安全地转移原有文件，不要重新生成密钥。** macOS 对两个文件执行 `chmod 600`。脚本不会输出口令，apksigner 通过环境变量读取口令，避免写入命令行参数。

密钥、配置和包含它们的压缩包都不能提交。请自行安全保存正式签名；丢失密钥后无法对已安装应用做同签名升级。

## 版本号与构建号

`pubspec.yaml` 的 `version` 必须是 `版本名+构建号`，如 `0.1.0+1`：

- 版本名是三段数字，设置页和 GitHub 标签按它比较版本。发布新版本时必须提升版本名。
- `+` 后的构建号从 `1` 开始，每次发布加 1，在 `pubspec.yaml` 中手动维护。发布过的构建号不能重复使用，也不能回退：构建号更小的安装包无法覆盖安装，只能卸载重装，会清空手机上的配对和数据。
- 构建号不依赖 Git 提交数，重建或精简仓库历史不影响升级。
- 打包脚本会把版本名通过 `APP_VERSION` 编译进应用；绕过脚本构建时也要传这个参数，否则设置页显示 `dev`。

## 构建与安装

```sh
tool/build_android.sh --no-install # 只构建并正式签名
tool/build_android.sh              # 另用 adb install -r 覆盖安装
```

脚本会：

1. 备份 `GeneratedPluginRegistrant.java` 当前内容，暂时移除 `integration_test` 注册。成功或失败后都恢复原样，不用 Git 覆盖已有本地修改。
2. 以 release 模式仅构建 arm64，从 `pubspec.yaml` 读取版本和构建号。
3. 用 Android build-tools 对齐、正式签名并校验，生成 `build/app/outputs/flutter-apk/ycode-<版本名>-<构建号>.apk`。
4. 仅在未指定 `--no-install` 时执行 `adb install -r`，并打印设备上的版本信息。

build-tools 从 `ANDROID_HOME` / `ANDROID_SDK_ROOT` 或系统标准目录查找，也可以通过 `BUILD_TOOLS` 指向具体版本目录。签名配置缺失或不完整会报错退出，绝不回退到 debug 签名。

默认构建会传 `--dart-define=YCODE_REPOSITORY=shuishani/ycode`；可用环境变量 `YCODE_REPOSITORY=<owner/repo>` 覆盖。仅当受控环境变量 `YCODE_TEST_INSTALL=true` 时，脚本额外传 `-PtestInstall=true` 和 `--dart-define=YCODE_PREVIEW=true`，其他本地行为不变。

## 发布与检查更新

发布到 `https://github.com/shuishani/ycode` 的 GitHub Releases：

1. 提升版本名和构建号，在 `CHANGELOG.md`（英文）和 `CHANGELOG_CN.md`（中文）顶部写上这一版（应用内「关于 YCode → 更新日志」按界面语言显示，测试会检查两份都有这一节），运行相关测试、静态检查并打包。
2. 确认 APK 的包名、版本、构建号和签名与预期一致。
3. 为对应源码提交创建稳定版本标签，如 `v0.1.0`。
4. 上传正式签名的 `ycode-0.1.0-1.apk`（也接受 `ycode-0.1.0.apk`），不要上传 debug 或其他架构文件冒充正式包。再运行 `dart run tool/release_manifest.dart`，把生成的 `build/app/outputs/flutter-apk/latest.json` 一起上传；它按 pubspec 的版本、这个 APK 和两份更新日志生成，不要手改。发布 fork 时可运行 `dart run tool/release_manifest.dart --repository=<owner/repo>`，也可设置 `YCODE_REPOSITORY`；命令行参数优先，默认仍为 `shuishani/ycode`，且仓库名必须是严格的 `owner/repo`。Release 的说明直接用它的 `body`（`jq -r .body latest.json`）：英文在前，`<!-- zh -->` 一行之后是中文，应用按界面语言只显示一半；不另写 APK 名和 SHA，GitHub 的附件列表自带。
5. 上传完成后再公开发布 Release，避免用户看到只有说明、没有 APK 的版本。公开仓库和公开的非预发布 Release 才能供正式应用匿名查询；个人并存预览版则明确发布为 pre-release。
6. 用较低版本实际检查更新，确认下载进度、取消、安装来源授权和系统安装器；完成覆盖安装后确认版本、配对和本地数据。

应用先读最新 Release 的 `latest.json`：`releases/latest/download/latest.json` 跳转到 CDN，不占 GitHub 匿名接口每个出口 IP 每小时 60 次的额度，多人共用出口的网络里也能查。读不到或读不懂再问 `releases/latest` 接口。`latest.json` 是接口返回 JSON 的子集，两者用同一套校验。

应用在冷启动和每次回到前台时自动检查，只在最新 Release 比当前版本新、且附带可用 APK 时弹窗；更新窗口已经开着时不重复弹出。30 分钟内复用上次的检查结果；检查失败不提示，下次打开再试。用户也可以在「设置 → 当前版本」手动检查。

应用只接受本仓库、本 Release 标签下的 GitHub APK 地址，优先选择 arm64 附件。下载使用流式写入，检查大小及可用的 SHA-256；安装前再次校验本应用包名、同一签名、Release 版本名及更高构建号。没有合适 APK 时不提供下载按钮。

首次安装更新可能跳到「允许安装未知应用」设置；授权后返回并点击「继续安装」。安装仍需要用户在 Android 系统界面确认，应用不会静默安装或绕过权限。关闭下载窗口会取消当前请求，不保证后台或进程被结束后的续传。

## 注意事项

- 签名不同的安装包（比如 debug 签名）不能覆盖安装正式版。只能卸载重装，会清空数据，必须先告知用户；不要擅自卸载。
- 不要删除或提交构建导致的 `GeneratedPluginRegistrant.java` 改动。删除它可能导致插件未注册。
- 每个 `FileProvider` 必须用各自的子类（如更新用的 `UpdateFileProvider`）。多个 `<provider>` 共用 `androidx.core.content.FileProvider` 类名时只有一个生效，系统安装器读不到更新包，会报“安装包已损坏”。
- 官方 BaoCode（`dev.baocode.mobile`）与本应用无关，不要操作它。
- adb 连接异常时先检查设备、USB 调试授权和 adb 服务，不要结束不明的共享服务或清除手机数据。
