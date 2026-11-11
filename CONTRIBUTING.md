# 参与贡献

欢迎提交 Issue 和 Pull Request。YCode 是个人维护的非官方客户端，回复可能不及时，请见谅。

## 报告问题

- 先搜索是否已有相同的 Issue。
- 写清手机型号和 Android 版本、YCode 版本（「设置 → 当前版本」）、电脑端 BaoCode 版本、复现步骤，以及实际和预期的结果。
- 截图和日志里先去掉配对二维码、配对链接、安全码、令牌、真实聊天内容和个人路径。
- **安全问题不要公开提交**，按 [SECURITY.md](SECURITY.md) 私下报告。
- BaoCode 电脑端本身的问题请提交给官方仓库 [baocode-dev/baocode](https://github.com/baocode-dev/baocode)。

## 提交代码

- 从 `main` 创建分支，一个 Pull Request 只做一件事。
- 开发环境见 [README](README_CN.md)，构建和签名见 [docs/release-android.md](docs/release-android.md)。
- 提交前运行 `flutter analyze --no-pub` 和 `flutter test --no-pub`。新增或修改的行为要有测试，测试名用中文。
- 界面文案中英双语：有 `AppState` 时用 `state.tr`，否则用 `AppState.phrase`；错误提示不显示异常原文。
- 不要直接修改 `vendor/` 下的协议包，协议同步规则见 [docs/upstream-sync.md](docs/upstream-sync.md)。
- 新增第三方代码或图标时，先确认许可与 GPL-3.0-only 兼容，并按 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 的要求登记。
- 不要提交构建产物、签名文件、配对数据和真实聊天记录。
- 不需要修改版本号，发布由维护者完成。

提交的代码按本项目的 [GPL-3.0-only](LICENSE) 许可发布。
