# YCode

- 文案统一双语：有 `AppState` 用 `state.tr`，否则用 `AppState.phrase`；错误走 `userMessage`，不显示异常原文。
- 术语统一叫「电脑」；连接状态复用 `linkStatusLabel()`。
- 组件与格式化复用现有实现，保持 UI 和行为，不为精简而拆文件。
- 只格式化自己改的源码，不动 vendor 和生成代码；新测试的名字和内容用中文。
- 不提交构建产物、配对数据、真实聊天记录、令牌和签名密钥。
- 修改后通过 `flutter analyze --no-pub` 和 `flutter test --no-pub`。
- 保留 `GeneratedPluginRegistrant.java`；构建、签名、覆盖安装前读 `docs/release-android.md`。
- 这是公开仓库：不写入个人路径、真实姓名、内部分支名和官方闭源 App 的信息；界面参考官方截图自行设计，不复制官方 App 的代码和素材。
- 发版时 `pubspec.yaml` 的版本名和构建号都要递增，构建号只增不减；发布流程见 `docs/release-android.md`。
- `README.md` / `README_CN.md`、`CHANGELOG.md` / `CHANGELOG_CN.md` 是英中两份，改一份就同步改另一份。
- 新增第三方代码或图标先核对许可，更新 `THIRD_PARTY_NOTICES.md`；Remix Icon 只用 4.8.0 及更早版本。
- 每个 `FileProvider` 用各自的子类，不能共用 `androidx.core.content.FileProvider` 类名。
- 电脑端改了 `packages/bao_link`、`packages/bao_iroh` 或 `lib/link/` 的协议时，按 `docs/upstream-sync.md` 跟进，并更新其中记录的官方提交。
