import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'activity_row.dart';
import 'agent_step.dart';
import 'assistant_text.dart';
import 'command_step.dart';
import 'edit_step.dart';
import 'notice_row.dart';
import 'plan_card.dart';
import 'step_header.dart';
import 'strings.dart';
import 'terminal_text.dart';
import 'thinking_section.dart';
import 'tool_call_row.dart';

/// Maps a [ChatItem] to its visual component. Mobile adaptation of the
/// desktop dispatcher: the user message keeps the phone's own bubble
/// (`MessageView` renders it), and the desktop's dedicated browser and
/// image steps are v1 rendered by the generic [ToolCallRow].
class ChatItemView extends StatelessWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.zh,
    this.expanded = false,
    this.onToggle,
    this.onOpen,
    this.onSetGoal,
    this.onOpenFile,
  });

  final ChatItem item;

  /// The app language, as the strings bundles take it; null, the
  /// platform locale decides.
  final bool? zh;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Opens a subagent's own conversation.
  final VoidCallback? onOpen;

  /// Sets a goal the agent proposed as the session's.
  final ValueChanged<String>? onSetGoal;

  /// Reads a file off the paired desktop.
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final view = _build();
    // Steps line up on the left: the history centers what is narrower
    // than its column.
    return isStep(item) ? SizedBox(width: double.infinity, child: view) : view;
  }

  Widget _build() {
    final zh = this.zh ?? localeIsZh;
    return switch (item) {
      AssistantTextItem(:final text) => AssistantText(text),
      ThinkingItem(:final text, :final seconds, :final startedAt) =>
        ThinkingSection(
          text: text,
          seconds: seconds,
          startedAt: startedAt,
          expanded: expanded,
          onToggle: onToggle ?? () {},
        ),
      ToolCallItem(
        :final kind,
        :final target,
        :final detail,
        :final path,
        :final results,
        :final label,
        :final tool,
        :final input,
        :final status,
        :final output,
        :final images,
        :final imageFiles,
      ) =>
        ToolCallRow(
          kind: kind,
          target: target,
          detail: detail,
          path: path,
          results: results,
          label: label,
          tool: tool,
          input: input,
          status: status,
          output: output,
          images: images,
          imageFiles: imageFiles,
          expanded: expanded,
          onToggle: onToggle,
          onSetGoal: onSetGoal,
          strings: ToolStrings(zh),
          onOpenFile: onOpenFile,
        ),
      final AgentItem agent => AgentStep(
        item: agent,
        onOpen: onOpen,
        strings: AgentStrings(zh),
      ),
      final NoticeItem notice => NoticeRow(item: notice),
      final PlanItem plan => PlanCard(
        item: plan,
        onOpen: onOpenFile == null || plan.path.isEmpty
            ? null
            : () => onOpenFile!(plan.path),
        strings: PlanStrings(zh),
      ),
      TerminalItem(
        :final command,
        :final description,
        :final output,
        :final status,
        :final background,
      ) =>
        CommandStep(
          strings: CommandStrings(zh),
          toolStrings: ToolStrings(zh),
          command: command,
          description: description,
          output: output,
          status: status,
          background: background,
          expanded: expanded,
          onToggle: onToggle,
        ),
      final CodeDiffItem diff => EditStep(
        item: diff,
        expanded: expanded,
        onToggle: onToggle,
        tr: (zhText, enText) => zh ? zhText : enText,
        onOpenFile: onOpenFile,
      ),
      LiveStatusItem(
        :final label,
        :final whimsical,
        :final visible,
        :final cue,
      ) =>
        ActivityRow(
          strings: ActivityStrings(zh),
          label: label,
          whimsical: whimsical,
          visible: visible,
          cue: cue,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The text of [item] as the history shows it, for copying items that are
/// wholly inside a selection (built or not). Mirrors the widgets above: one
/// line per text block, blocks on the same row joined by a space, so it
/// matches what copying the rendered item yields.
String chatItemPlainText(
  ChatItem item, {
  bool expanded = false,
  bool? zh,
  ToolStrings? strings,
}) {
  final isZh = zh ?? localeIsZh;
  final toolStrings = strings ?? ToolStrings(isZh);
  final planStrings = PlanStrings(isZh);
  final thinkingStrings = ThinkingStrings(isZh);
  final activityStrings = ActivityStrings(isZh);
  String inline(String text) {
    final parts = text.split('`');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty) i.isOdd ? ' ${parts[i]} ' : parts[i],
    ].join();
  }

  return switch (item) {
    UserMessageItem(:final text) => inline(text),
    AssistantTextItem(:final text) => [
      for (final line in text.split('\n'))
        if (line.startsWith('- '))
          '• ${inline(line.substring(2))}'
        else if (line.isNotEmpty)
          inline(line),
    ].join('\n'),
    ThinkingItem(:final text, :final seconds) => switch (thoughtSummary(text)) {
      (:final title, :final body) => [
        title,
        if (expanded && body.isNotEmpty) body,
      ].join('\n'),
      null => [
        thinkingTitle(seconds: seconds, strings: thinkingStrings),
        if (expanded) text.trimRight(),
      ].join('\n'),
    },
    ToolCallItem(
      :final kind,
      :final target,
      :final detail,
      :final label,
      :final status,
      :final results,
      :final output,
      :final tool,
      :final input,
    ) =>
      [
        switch (kind == ToolKind.todo &&
                status != ToolStatus.denied &&
                status != ToolStatus.failed
            ? todoStep(
                tool,
                input,
                target,
                output: output,
                strings: toolStrings,
              )
            : null) {
          (:final verb, :final object, detail: final todoDetail)
              when label == null =>
            StepHeader.text(verb, object, todoDetail ?? detail),
          _ => StepHeader.text(
            status == ToolStatus.denied || status == ToolStatus.failed
                ? toolVerb(kind, status: status, strings: toolStrings)
                : label ?? toolVerb(kind, status: status, strings: toolStrings),
            target,
            detail,
          ),
        },
        if (expanded)
          if (results.isNotEmpty)
            results.join('\n')
          else if (output?.trimRight() case final output?
              when output.isNotEmpty)
            output,
      ].join('\n'),
    final AgentItem agent => AgentStep.plainText(
      agent,
      toolStrings: toolStrings,
    ),
    NoticeItem(:final text) => text,
    final PlanItem plan => PlanCard.plainText(plan, strings: planStrings),
    TerminalItem(
      :final command,
      :final description,
      :final output,
      :final status,
      :final background,
    ) =>
      [
        StepHeader.text(
          CommandStep.verb(
            status,
            background: background,
            toolStrings: toolStrings,
          ),
          CommandStep.title(command, description),
          background ? (isZh ? '在后台' : 'in the background') : null,
        ),
        if (expanded) ...[
          '\$ $command',
          if (terminalText(output).text case final printed
              when printed.isNotEmpty)
            printed,
        ],
      ].join('\n'),
    CodeDiffItem(:final fileName, :final lines) => [
      [
        StepHeader.text(toolStrings.toolVerbLabel(ToolKind.edit), fileName),
        if (item.added > 0) '+${item.added}',
        if (item.removed > 0) '-${item.removed}',
      ].join(' '),
      if (expanded)
        for (final line in lines)
          '${line.lineNumber} ${switch (line.type) {
            DiffLineType.added => '+',
            DiffLineType.removed => '-',
            DiffLineType.context => ' ',
          }} ${line.text}',
    ].join('\n'),
    LiveStatusItem(:final label, :final visible) =>
      visible ? activityStrings.label(label) : '',
  };
}

/// Whether [ChatItemView] renders [item] itself: everything but the user
/// message (the phone keeps its own bubble) and items it cannot know.
bool handledByChatItemView(ChatItem item) => switch (item) {
  UserMessageItem() => false,
  AssistantTextItem() ||
  ThinkingItem() ||
  ToolCallItem() ||
  AgentItem() ||
  NoticeItem() ||
  PlanItem() ||
  TerminalItem() ||
  CodeDiffItem() ||
  LiveStatusItem() => true,
};

/// Whether [item] is a step the agent took (a thought, a tool call…): one
/// line that may open.
bool isStep(ChatItem item) => switch (item) {
  ThinkingItem() ||
  ToolCallItem() ||
  AgentItem() ||
  TerminalItem() ||
  CodeDiffItem() ||
  LiveStatusItem() => true,
  _ => false,
};

/// Whether a step is open unless opened or closed by hand: a thought while
/// it streams. Tool calls stay closed (opening and closing as they start
/// and end would flicker): a picture's shows small after its line.
bool defaultExpanded(ChatItem item) => switch (item) {
  ThinkingItem(:final streaming) => streaming,
  _ => false,
};
