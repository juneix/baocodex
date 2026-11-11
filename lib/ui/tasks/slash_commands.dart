import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum SlashKind { builtin, skill, command }

class SlashCommand {
  const SlashCommand(
    this.name,
    this.description, {
    this.hint = '',
    this.kind = SlashKind.builtin,
    this.project = false,
  });

  final String name, description;

  /// 参数提示，如 `[name]`。
  final String hint;
  final SlashKind kind;

  /// 项目自己的（项目里的技能、`.claude/commands`），不是用户级的。
  final bool project;
}

/// Claude Code 的内置命令和自带技能里，经电脑发过去也认（无界面模式报的那些）、
/// 手机上用得着的；用户和项目的技能、项目命令另外从电脑要。
List<SlashCommand> builtinSlashCommands(String Function(String, String) tr) => [
  SlashCommand(
    'compact',
    tr('压缩对话，保留摘要', 'Compact the conversation into a summary'),
    hint: tr('[摘要要求]', '[instructions]'),
  ),
  SlashCommand('context', tr('查看上下文占用', 'Show context usage')),
  SlashCommand('usage', tr('查看用量', 'Show usage')),
  SlashCommand('clear', tr('清空对话，重新开始', 'Clear the conversation')),
  SlashCommand('goal', tr('设个目标，做到为止', 'Keep working until a goal is met')),
  SlashCommand('recap', tr('一句话回顾这段对话', 'A one-line recap of the session')),
  SlashCommand(
    'rename',
    tr('重命名对话', 'Rename the conversation'),
    hint: tr('[名字]', '[name]'),
  ),
  SlashCommand('insights', tr('分析近期对话的报告', 'A report on your sessions')),
  SlashCommand('init', tr('生成 CLAUDE.md', 'Create a CLAUDE.md')),
  SlashCommand(
    'security-review',
    tr('安全审查代码改动', 'Security review of the changes'),
  ),
  SlashCommand(
    'code-review',
    tr('审查改动里的 bug', 'Review the changes for bugs'),
    hint: '[low|medium|high]',
    kind: SlashKind.skill,
  ),
  SlashCommand(
    'simplify',
    tr('精简改过的代码', 'Simplify the changed code'),
    kind: SlashKind.skill,
  ),
  SlashCommand(
    'verify',
    tr('实际跑一遍，验证改动', 'Verify a change end to end'),
    kind: SlashKind.skill,
  ),
  SlashCommand(
    'debug',
    tr('开调试日志，排查 Claude Code 的问题', 'Debug this Claude Code session'),
    hint: tr('[问题描述]', '[issue]'),
    kind: SlashKind.skill,
  ),
  SlashCommand(
    'deep-research',
    tr('多方搜索查证，写成带出处的报告', 'Researched report with sources'),
    kind: SlashKind.skill,
  ),
];

/// 项目 `.claude/commands` 里的一个命令文件：名字取文件名，说明和参数提示
/// 取开头 `---` 之间的 `description`、`argument-hint`，没写说明就用正文第一行。
SlashCommand? projectSlashCommand(String fileName, String text) {
  if (!fileName.endsWith('.md')) return null;
  final name = fileName.substring(0, fileName.length - 3);
  if (name.isEmpty) return null;
  final fields = <String, String>{};
  var body = text;
  final front = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)')
      .firstMatch(text);
  if (front != null) {
    body = text.substring(front.end);
    final lines = front[1]!.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon <= 0 || _indented(line)) continue;
      var value = line.substring(colon + 1).trim();
      // `>`、`|` 写的多行值：后面缩进的那几行，并成一行。
      if (RegExp(r'^[>|][+-]?$').hasMatch(value)) {
        final block = <String>[];
        while (i + 1 < lines.length &&
            (lines[i + 1].trim().isEmpty || _indented(lines[i + 1]))) {
          block.add(lines[++i].trim());
        }
        value = block.where((part) => part.isNotEmpty).join(' ');
      }
      fields[line.substring(0, colon).trim()] = _unquote(value);
    }
  }
  final firstLine = body
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^#+\s*'), '').trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final description = fields['description'] ?? '';
  return SlashCommand(
    name,
    description.isEmpty ? firstLine : description,
    hint: fields['argument-hint'] ?? '',
    kind: SlashKind.command,
    project: true,
  );
}

bool _indented(String line) => line.startsWith(RegExp(r'[ \t]'));

String _unquote(String value) =>
    value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))
    ? value.substring(1, value.length - 1)
    : value;

/// 输入框正在打的命令名（`/` 后面、还没空格的部分）；不是在打命令就是 null。
String? slashQuery(String text) =>
    RegExp(r'^/([\w:.-]*)$').firstMatch(text)?[1];

/// [commands] 里名字含 [query] 的，开头就对上的排前面；同名只留先来的。
List<SlashCommand> matchSlashCommands(
  List<SlashCommand> commands,
  String query,
) {
  final q = query.toLowerCase();
  final seen = <String>{};
  final hits = [
    for (final command in commands)
      if (command.name.toLowerCase().contains(q) && seen.add(command.name))
        command,
  ];
  return [
    ...hits.where((command) => command.name.toLowerCase().startsWith(q)),
    ...hits.where((command) => !command.name.toLowerCase().startsWith(q)),
  ];
}

/// 输入框上方的命令列表，点一条把它填进输入框。
class SlashCommandMenu extends StatelessWidget {
  const SlashCommandMenu({
    super.key,
    required this.commands,
    required this.onPick,
    required this.projectLabel,
  });

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand> onPick;

  /// 项目自己的命令后面那个小标签的字。
  final String projectLabel;

  static IconData iconOf(SlashKind kind) => switch (kind) {
    SlashKind.builtin => Icons.keyboard_command_key_rounded,
    SlashKind.skill => Icons.auto_awesome_outlined,
    SlashKind.command => Icons.description_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Container(
      key: const ValueKey('slash-menu'),
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: muted.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final command in commands)
            InkWell(
              onTap: () => onPick(command),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(iconOf(command.kind), size: 16, color: muted),
                    const SizedBox(width: 10),
                    Text(
                      '/${command.name}',
                      style: TextStyle(
                        fontSize: MobileType.secondary,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (command.project) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          projectLabel,
                          style: TextStyle(
                            fontSize: MobileType.caption,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        command.hint.isEmpty
                            ? command.description
                            : '${command.hint}  ${command.description}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MobileType.aside,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
