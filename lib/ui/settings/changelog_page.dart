import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_links.dart' show confirmExternalLink;
import '../../chat/markdown/markdown_view.dart';
import '../../state/app_state.dart';
import '../../state/update_check.dart';
import '../../theme/app_theme.dart';

/// 随安装包带的更新日志，按界面语言选：不联网，也不占 GitHub 接口的额度。
const changelogAssets = (zh: 'CHANGELOG_CN.md', en: 'CHANGELOG.md');

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key, required this.state, this.bundle});
  final AppState state;
  final AssetBundle? bundle;

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  late final Future<String> _text = (widget.bundle ?? rootBundle)
      .loadString(widget.state.tr(changelogAssets.zh, changelogAssets.en))
      // 页面标题已经写着「更新日志」，文件自己的一级标题不再重复。
      .then((text) => text.replaceFirst(RegExp(r'^# .*\n+'), ''));

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('更新日志', 'Changelog'))),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.fromLTRB(
            MobileSpace.lg,
            MobileSpace.sm,
            MobileSpace.lg,
            MobileSpace.xl,
          ),
          children: [
            switch (snapshot) {
              AsyncSnapshot(hasData: true, :final data?) => SelectionArea(
                child: MarkdownView(
                  data,
                  style: MobileTheme.messageStyleOf(context),
                  options: MarkdownOptions(
                    colors: colors,
                    headingSizes: MobileTheme.headingSizesOf(context),
                    gap: MobileTheme.markdownGap,
                  ),
                ),
              ),
              AsyncSnapshot(hasError: true) => Text(
                state.tr('更新日志读取失败。', 'Could not read the changelog.'),
                style: MobileTheme.hintStyleOf(context),
              ),
              _ => const SizedBox.shrink(),
            },
            const SizedBox(height: MobileSpace.lg),
            Center(
              child: TextButton(
                onPressed: () =>
                    confirmExternalLink(context, state, '$projectUrl/releases'),
                child: Text(state.tr('在 GitHub 查看全部', 'View all on GitHub')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
