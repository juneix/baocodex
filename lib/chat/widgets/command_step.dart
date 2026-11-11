import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_models.dart';
import 'shell_highlight.dart';
import 'step_header.dart';
import 'strings.dart';
import 'terminal_text.dart';
import 'tool_call_row.dart' show ToolStrings;
import '../../theme/app_theme.dart';

/// A shell command as a step: "Ran  Check the Flutter version", opening to
/// the command, colored, and what it printed. Mobile adaptation of the
/// desktop step: the `…` floating menu becomes a Material popup menu, and
/// the labels come from [strings]/[toolStrings].
class CommandStep extends StatelessWidget {
  const CommandStep({
    super.key,
    required this.command,
    required this.output,
    this.description,
    this.status = CommandStatus.succeeded,
    this.background = false,
    this.expanded = false,
    this.onToggle,
    this.strings,
    this.toolStrings,
  });

  final String command;
  final String output;
  final String? description;
  final CommandStatus status;

  /// Left running on its own: the turn went on.
  final bool background;
  final bool expanded;
  final VoidCallback? onToggle;

  final CommandStrings? strings;
  final ToolStrings? toolStrings;

  bool get _running => status == CommandStatus.running && !background;

  /// Anything to open to: the command may still be on its way.
  bool get _opens => command.trim().isNotEmpty || output.trim().isNotEmpty;

  /// What the header says it is: its description, or its first line.
  static String title(String command, String? description) =>
      switch (description?.trim()) {
        final text? when text.isNotEmpty => text,
        _ => command.trim().split('\n').first,
      };

  /// What the header says it did.
  static String verb(
    CommandStatus status, {
    required bool background,
    CommandStrings? strings,
    ToolStrings? toolStrings,
  }) {
    final s = strings ?? CommandStrings.standard();
    final t = toolStrings ?? ToolStrings.standard();
    final toolStatus = status == CommandStatus.running
        ? ToolStatus.running
        : ToolStatus.succeeded;
    return background
        ? s.started
        : t.toolVerbLabel(ToolKind.command, status: toolStatus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = strings ?? CommandStrings.standard();
    // Rendered once opened: most steps stay closed.
    final printed = expanded ? terminalText(output) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: verb(
            status,
            background: background,
            strings: strings,
            toolStrings: toolStrings,
          ),
          object: title(command, description),
          detail: background ? s.background : null,
          running: _running,
          expanded: expanded,
          onToggle: _opens ? onToggle : null,
        ),
        if (expanded && _opens)
          StepBody(
            followEnd: _running,
            // Clear of the menu button.
            padding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
            overlay: _CommandMenu(
              command: command,
              output: output,
              strings: strings ?? CommandStrings.standard(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '\$ ',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: MobileTheme.asideAlpha,
                          ),
                        ),
                      ),
                      ...highlightShell(
                        command,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ],
                  ),
                  style: stepMono(context),
                ),
                if (printed != null && printed.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TerminalPrinted(output: output),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The command step's own strings, both languages inline.
class CommandStrings {
  const CommandStrings._(this.zh);

  factory CommandStrings(bool zh) =>
      zh ? const CommandStrings._(true) : const CommandStrings._(false);

  factory CommandStrings.standard() => CommandStrings(localeIsZh);

  final bool zh;

  String get started => zh ? '已启动' : 'Started';
  String get background => zh ? '在后台' : 'in the background';
  String get copyCommand => zh ? '复制命令' : 'Copy command';
  String get copyOutput => zh ? '复制输出' : 'Copy output';
  String get more => zh ? '更多' : 'More';
}

/// `…`: copy the command or its output.
class _CommandMenu extends StatelessWidget {
  const _CommandMenu({
    required this.command,
    required this.output,
    required this.strings,
  });

  final String command;
  final String output;
  final CommandStrings strings;

  static void _copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Widget build(BuildContext context) {
    final printed = terminalText(output);
    return PopupMenuButton<String>(
      tooltip: strings.more,
      onSelected: (value) => switch (value) {
        'command' => _copy(command),
        'output' => _copy(printed.text),
        _ => {},
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'command', child: Text(strings.copyCommand)),
        if (printed.text.isNotEmpty)
          PopupMenuItem(value: 'output', child: Text(strings.copyOutput)),
      ],
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
