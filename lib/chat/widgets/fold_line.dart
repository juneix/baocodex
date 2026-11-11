import 'package:flutter/material.dart';

import '../chat_models.dart';
import '../step_folds.dart';
import 'agent_step.dart';
import 'edit_step.dart';
import 'step_header.dart';
import 'strings.dart';
import 'tool_call_row.dart' show ToolStrings;
import '../../theme/app_theme.dart';

/// The fold lines' strings, both languages inline (see [ToolStrings]).
class FoldStrings {
  const FoldStrings._(this.zh);

  factory FoldStrings(bool zh) => zh ? zhCN : en;

  factory FoldStrings.standard() => FoldStrings(localeIsZh);

  static const zhCN = FoldStrings._(true);
  static const en = FoldStrings._(false);

  final bool zh;

  String get separator => zh ? '，' : ', ';

  // Every count is of calls, as many as the steps it opens to: a file read
  // in two parts is read twice, not two files.
  String stepsRead(int count) =>
      zh ? '读取 $count 次' : (count == 1 ? 'read once' : 'read $count times');
  String stepsSearched(int count) => zh
      ? '搜索 $count 次'
      : (count == 1 ? 'searched once' : 'searched $count times');
  String stepsListed(int count) => zh
      ? '列出目录 $count 次'
      : (count == 1 ? 'listed once' : 'listed $count times');
  String stepsFetched(int count) => zh
      ? '获取网页 $count 次'
      : (count == 1 ? 'fetched once' : 'fetched $count times');
  String stepsRan(int count) => zh
      ? '运行 $count 条命令'
      : (count == 1 ? 'ran 1 command' : 'ran $count commands');
  String stepsBrowsed(int count) => zh
      ? '操作浏览器 $count 次'
      : (count == 1
            ? 'used the browser once'
            : 'used the browser $count times');
  String stepsUsed(int count) => zh
      ? '使用工具 $count 次'
      : (count == 1 ? 'used a tool once' : 'used tools $count times');
  String stepsThought(String duration) =>
      zh ? '思考 $duration' : 'thought $duration';
  String turnWorked(String duration) =>
      zh ? '已处理 $duration' : 'Worked for $duration';
  String turnEdited(int count) =>
      zh ? '编辑 $count 次' : (count == 1 ? 'edited once' : 'edited $count times');
}

/// A run of quick steps, folded: "Read 3 files, ran 2 commands", the
/// counts standing out; then, fainter, how long it thought. Opens to the
/// steps. Mobile adaptation: the steps' pictures stay in their cards (the
/// desktop shows small copies after the line).
class StepsFoldLine extends StatelessWidget {
  const StepsFoldLine({
    super.key,
    required this.tally,
    required this.expanded,
    required this.onToggle,
    this.strings,
  });

  final StepTally tally;
  final bool expanded;
  final VoidCallback onToggle;
  final FoldStrings? strings;

  /// What the steps did, each phrase with its count in it.
  static List<(String, int)> _actions(StepTally tally, FoldStrings s) {
    final actions = [
      for (final action in StepAction.values)
        if (tally.counts[action] case final count?)
          (
            switch (action) {
              StepAction.read => s.stepsRead(count),
              StepAction.search => s.stepsSearched(count),
              StepAction.list => s.stepsListed(count),
              StepAction.fetch => s.stepsFetched(count),
              StepAction.run => s.stepsRan(count),
              StepAction.browse => s.stepsBrowsed(count),
              StepAction.use => s.stepsUsed(count),
            },
            count,
          ),
    ];
    // The line starts as a sentence does.
    if (actions.firstOrNull case (final first, final count)) {
      actions[0] = (first[0].toUpperCase() + first.substring(1), count);
    }
    return actions;
  }

  static String? _thought(StepTally tally, FoldStrings s) => tally.thought > 0
      ? s.stepsThought(
          AgentStep.formatDuration(
            Duration(seconds: tally.thought),
            strings: AgentStrings(s.zh),
          ),
        )
      : null;

  /// The line as text, e.g. for copying.
  static String text(StepTally tally, {FoldStrings? strings}) {
    final s = strings ?? FoldStrings.standard();
    return [
      _actions(tally, s).map((a) => a.$1).join(s.separator),
      ?_thought(tally, s),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = strings ?? FoldStrings.standard();
    final count = TextStyle(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final faint = TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: MobileTheme.asideAlpha),
    );
    final actions = _actions(tally, s);
    return Semantics(
      button: true,
      expanded: expanded,
      onTap: onToggle,
      child: StepHeader(
        verb: text(tally, strings: s),
        expanded: expanded,
        onToggle: onToggle,
        trailingGap: 0,
        spans: [
          for (final (i, (phrase, n)) in actions.indexed) ...[
            if (i > 0) TextSpan(text: s.separator),
            ..._withCount(phrase, n, count),
          ],
          if (_thought(tally, s) case final thought?)
            TextSpan(text: ' · $thought', style: faint),
        ],
      ),
    );
  }

  /// [phrase] with its [count] in [style].
  static List<InlineSpan> _withCount(
    String phrase,
    int count,
    TextStyle style,
  ) {
    final digits = '$count';
    final at = phrase.indexOf(digits);
    if (at < 0) return [TextSpan(text: phrase)];
    return [
      TextSpan(text: phrase.substring(0, at)),
      TextSpan(text: digits, style: style),
      TextSpan(text: phrase.substring(at + digits.length)),
    ];
  }
}

/// A finished turn's work, folded before its answer: "Worked for 4m 32s",
/// with the files it edited. Opens to the work.
class WorkFoldLine extends StatelessWidget {
  const WorkFoldLine({
    super.key,
    required this.worked,
    required this.edits,
    required this.expanded,
    required this.onToggle,
    this.strings,
  });

  final Duration worked;
  final TurnEdits edits;
  final bool expanded;
  final VoidCallback onToggle;
  final FoldStrings? strings;

  /// The line as text, e.g. for copying.
  static String text(Duration worked, TurnEdits edits, {FoldStrings? strings}) {
    final s = strings ?? FoldStrings.standard();
    return [
      s.turnWorked(
        AgentStep.formatDuration(worked, strings: AgentStrings(s.zh)),
      ),
      if (edits.count > 0)
        [
          s.turnEdited(edits.count),
          if (edits.added > 0) '+${edits.added}',
          if (edits.removed > 0) '-${edits.removed}',
        ].join(' '),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = strings ?? FoldStrings.standard();
    final faint = TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: MobileTheme.asideAlpha),
    );
    final count = TextStyle(
      fontFamily: 'monospace',
      fontSize: MobileType.aside,
    );
    final header = StepHeader(
      verb: text(worked, edits, strings: s),
      expanded: expanded,
      onToggle: onToggle,
      trailingGap: 0,
      spans: [
        TextSpan(
          text: s.turnWorked(
            AgentStep.formatDuration(worked, strings: AgentStrings(s.zh)),
          ),
        ),
        if (edits.count > 0) ...[
          TextSpan(text: ' · ${s.turnEdited(edits.count)}', style: faint),
          if (edits.added > 0)
            TextSpan(
              text: ' +${edits.added}',
              style: count.copyWith(color: EditStep.addedForeground(dark)),
            ),
          if (edits.removed > 0)
            TextSpan(
              text: ' -${edits.removed}',
              style: count.copyWith(color: EditStep.removedForeground(dark)),
            ),
        ],
      ],
    );
    return Semantics(
      button: true,
      expanded: expanded,
      onTap: onToggle,
      // As wide as it reads.
      child: Align(alignment: Alignment.centerLeft, child: header),
    );
  }
}

/// How many edits a turn made, and the lines they added and removed, each
/// edit's own summed: what it opens to. The files and their net change are
/// the changes pill's and the changes page's, off the desktop's real diff.
typedef TurnEdits = ({int count, int added, int removed});

/// The edits among [items].
TurnEdits turnEdits(Iterable<ChatItem> items) {
  var count = 0;
  var added = 0;
  var removed = 0;
  for (final item in items) {
    if (item is! CodeDiffItem) continue;
    count++;
    added += item.added;
    removed += item.removed;
  }
  return (count: count, added: added, removed: removed);
}
