# 第三方组件与许可

YCode 整体按 [GPL-3.0-only](LICENSE) 发布。下面这些部分来自第三方，保留各自的版权与许可；应用内「设置 → 关于 YCode → 开源许可」也会列出随安装包分发的许可全文。第三方 Dart 包（`pubspec.lock` 中的依赖）的许可由 Flutter 自动收集并显示在同一页面。

## 代码

| 位置 | 来源 | 许可 |
|---|---|---|
| `vendor/bao_link`，以及 [docs/upstream-sync.md](docs/upstream-sync.md) 中列出的复制、改编文件 | [BaoCode](https://github.com/baocode-dev/baocode) | GPL-3.0-only，版权归 BaoCode 作者 |
| `vendor/bao_iroh` | BaoCode | MIT，见 [vendor/bao_iroh/LICENSE](vendor/bao_iroh/LICENSE) |
| `vendor/bao_editor` | BaoCode，内含 Monaco、TextMate 语法、Oniguruma 等 | MIT 及各自的第三方许可，见该目录下的 `LICENSE` 文件 |

## 图标与图形

| 位置 | 来源 | 许可 | 许可全文 |
|---|---|---|---|
| `assets/icons/lucide-*.svg` | [Lucide](https://lucide.dev)（lucide-static 1.66.0）；部分图标衍生自 Feather | ISC；Feather 衍生部分为 MIT | [assets/licenses/lucide.txt](assets/licenses/lucide.txt) |
| `assets/icons/{checkbox-blank-circle-line,checkbox-circle-fill,progress-4-line,speak-ai-line}.svg`，`assets/model_icons/{openai,microsoft}.svg` | [Remix Icon](https://github.com/Remix-Design/RemixIcon/tree/v4.8.0) **4.8.0** | Apache-2.0 | [assets/licenses/remix-icon-4.8.0.txt](assets/licenses/remix-icon-4.8.0.txt) |
| `assets/model_icons/` 中标注 theSVG 的文件 | [theSVG](https://github.com/glincker/thesvg) | MIT | [assets/licenses/thesvg.txt](assets/licenses/thesvg.txt) |
| `assets/model_icons/` 中标注 Simple Icons 的文件 | [Simple Icons](https://github.com/simple-icons/simple-icons) | CC0-1.0 | 无需附带 |
| `assets/material_icons/` | [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) | MIT | [assets/material_icons/LICENSE](assets/material_icons/LICENSE) |
| `assets/icons/ycode.svg`、Android 应用图标 | YCode 自有 | GPL-3.0-only | — |

每个图标文件开头的注释记录了它的具体来源与许可。

**Remix Icon 只使用 4.8.0 及更早版本。** 从 4.9.0 起 Remix Icon 改用自定义许可，与本项目的 GPL 许可可能不兼容；更新这些图标时不要从新版本复制。

## CI 工具依赖

| 用途 | 来源 | 许可 |
|---|---|---|
| GitHub Actions 初始化签名时加密 Secrets（仅 CI 使用，不打入 APK，也不复制其代码） | [PyNaCl 1.5.0](https://pypi.org/project/PyNaCl/1.5.0/) | Apache-2.0 |

## 商标

`assets/model_icons/` 中的厂商标志仅用于标明对应的模型服务商，相关商标归各自所有者，不代表这些厂商认可或赞助本项目。BaoCode 名称与标识归其权利人所有；YCode 是独立的非官方客户端。
