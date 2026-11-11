import 'package:flutter/material.dart';

import '../../ui/files/file_icons.dart';
import '../chat_models.dart';
import '../markdown/code_citation.dart';
import 'step_header.dart';
import 'strings.dart';
import '../../theme/app_theme.dart';

/// A file edit as a step: "Edited main.dart +12 -3", a tap opening it
/// to its diff, under the file's icon and name. Mobile adaptation: the
/// desktop shows the changes in the side panel via [FileOpenScope]; here
/// [onOpenFile] (wired to the paired desktop's file read) takes its place,
/// and the labels come from an injected [tr].
class EditStep extends StatelessWidget {
  const EditStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
    this.tr = localeTr,
    this.onOpenFile,
  });

  final CodeDiffItem item;
  final bool expanded;
  final VoidCallback? onToggle;
  final String Function(String zh, String en) tr;

  /// Shows the edited file: the phone reads it off the desktop.
  final void Function(String path)? onOpenFile;

  /// The diff's green and red, after the editor's: lighter in the dark.
  static Color addedForeground(bool dark) =>
      Color(dark ? 0xFF3FB950 : 0xFF1A7F37);
  static Color removedForeground(bool dark) =>
      Color(dark ? 0xFFF85149 : 0xFFCF222E);

  /// Its "+12 -3".
  static const countStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: MobileType.aside,
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: tr('已编辑', 'Edited'),
          object: item.fileName.split(RegExp(r'[\\/]')).last,
          expanded: expanded,
          onToggle: onToggle,
          trailing: Text.rich(
            TextSpan(
              // A count of none is left out.
              children: [
                if (item.added > 0)
                  TextSpan(
                    text: '+${item.added}',
                    style: TextStyle(color: addedForeground(dark)),
                  ),
                if (item.added > 0 && item.removed > 0)
                  const TextSpan(text: ' '),
                if (item.removed > 0)
                  TextSpan(
                    text: '-${item.removed}',
                    style: TextStyle(color: removedForeground(dark)),
                  ),
              ],
            ),
            style: countStyle,
          ),
        ),
        if (expanded)
          StepBody(
            maxHeight: CodeCitationCard.maxCodeHeight,
            padding: const EdgeInsets.symmetric(vertical: 6),
            header: _FileHeader(
              item: item,
              tr: tr,
              onOpen: onOpenFile == null ? null : () => onOpenFile!(item.path),
            ),
            child: _Diff(item, dark: dark),
          ),
      ],
    );
  }
}

/// The edited file's icon and name over its diff: a tap shows its changes
/// on the paired desktop, when they can.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.item, required this.tr, this.onOpen});

  final CodeDiffItem item;
  final String Function(String zh, String en) tr;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onOpen = this.onOpen;
    Widget row() {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        child: Row(
          children: [
            Icon(fileIcon(item.fileName), size: 15, color: scheme.onSurface),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: MobileType.secondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (onOpen == null) return SelectionContainer.disabled(child: row());
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        label: tr('打开改动', 'Open diff'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: row(),
        ),
      ),
    );
  }
}

/// The diff's lines, each as code of its own.
class _Diff extends StatelessWidget {
  const _Diff(this.item, {required this.dark});

  final CodeDiffItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faint = scheme.onSurfaceVariant.withValues(
      alpha: MobileTheme.asideAlpha,
    );
    final lines = [
      for (final line in item.lines)
        _DiffLineRow(line, dark: dark, faint: faint),
    ];
    // 每行按内容撑开（不省略、不折行），整块一起左右滑：行内各自滚动会
    // 让行号和正文错位。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines,
        ),
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow(this.line, {required this.dark, required this.faint});

  final DiffLine line;
  final bool dark;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    final (prefix, prefixColor, background) = switch (line.type) {
      DiffLineType.added => (
        '+',
        EditStep.addedForeground(dark),
        Colors.green.withValues(alpha: 0.09),
      ),
      DiffLineType.removed => (
        '-',
        EditStep.removedForeground(dark),
        Colors.red.withValues(alpha: 0.09),
      ),
      DiffLineType.context => (' ', faint, Colors.transparent),
    };
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: MobileType.mono,
      height: 1.5,
    );

    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: mono.copyWith(color: faint),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text(
              prefix,
              textAlign: TextAlign.center,
              style: mono.copyWith(color: prefixColor),
            ),
          ),
          // 不 Expanded：要让这行按最长的内容撑开，才能横向滚过去看完。
          Text(
            line.text,
            softWrap: false,
            style: mono.copyWith(
              color: line.type == DiffLineType.context
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
