import 'package:flutter/material.dart';

import '../chat_models.dart';
import '../markdown/markdown_view.dart';
import '../../theme/app_theme.dart';

/// A line from the runtime rather than the agent: a compaction divider, a
/// retry or error, a hint, or the output of a command run in the session.
///
/// Mobile adaptation: the desktop reads `AppColors`/`themeColors` off the
/// workbench theme; here the Material scheme stands in, the warning amber
/// fixed per brightness.
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.item, this.zh});

  final NoticeItem item;
  final bool? zh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final error = scheme.error;
    const warningLight = Color(0xFFB26A00);
    final warning = dark ? const Color(0xFFFFB74D) : warningLight;
    final muted = scheme.onSurfaceVariant;
    final text = item.text;
    switch (item.kind) {
      case NoticeKind.compaction:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          // Sized to the text, not split with the lines, so a long note is
          // not squeezed into a third of the row.
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(child: Divider(color: scheme.outlineVariant)),
                const SizedBox(width: 10),
                Icon(Icons.compress_rounded, size: 13, color: muted),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (box.maxWidth - 2 * (24 + 10) - 13 - 6).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(color: muted, fontSize: MobileType.aside),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Divider(color: scheme.outlineVariant)),
              ],
            ),
          ),
        );
      case NoticeKind.command:
        const modelPrefix = 'Set model to ';
        if (text.startsWith(modelPrefix)) {
          final chinese =
              zh ?? Localizations.localeOf(context).languageCode == 'zh';
          var model = text.substring(modelPrefix.length);
          if (model.length >= 2 &&
              model.startsWith('`') &&
              model.endsWith('`')) {
            model = model.substring(1, model.length - 1);
          }
          // 换模型是这一段和前一段的分界：居中，两侧各一条浅线，像压缩
          // 对话那样把上下文分开，不是一句靠左的命令输出。
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  Expanded(child: Divider(color: scheme.outlineVariant)),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (box.maxWidth - 2 * (24 + 10)).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: Text(
                      chinese ? '已切换模型为 $model' : text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        fontSize: MobileType.aside,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Divider(color: scheme.outlineVariant)),
                ],
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: MarkdownView(
            text,
            style: MarkdownView.baseStyle.copyWith(
              fontSize: MobileType.secondary,
            ),
          ),
        );
      case NoticeKind.retry ||
          NoticeKind.error ||
          NoticeKind.info ||
          NoticeKind.warning:
        final (icon, color) = switch (item.kind) {
          NoticeKind.error => (Icons.error_outline_rounded, error),
          NoticeKind.warning ||
          NoticeKind.retry => (Icons.warning_amber_rounded, warning),
          _ => (Icons.info_outline_rounded, muted),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: item.kind == NoticeKind.error ? error : muted,
                    fontSize: MobileType.secondary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}
