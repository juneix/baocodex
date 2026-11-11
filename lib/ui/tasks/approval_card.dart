// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

import '../../chat/message_view.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';

/// 审批只改变展示方式；决定仍由用户明确提交，操作详情不触发授权。
class ApprovalCard extends StatefulWidget {
  const ApprovalCard({
    super.key,
    required this.state,
    required this.desktopId,
    required this.request,
    required this.busy,
    required this.onAnswer,
    this.projectId,
    this.error,
    this.enabled = true,
  });

  final AppState state;
  final String desktopId;
  final String? projectId, error;
  final Map<String, Object?> request;
  final bool busy;
  final bool enabled;
  final ValueChanged<Map<String, Object?>> onAnswer;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  final _reason = TextEditingController();

  /// Deny was tapped: it waits for a reason, or for deny without one.
  bool _denying = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _deny(String message) => widget.onAnswer({
    't': 'approval',
    'decision': 'deny',
    if (message.isNotEmpty) 'message': message,
  });

  @override
  Widget build(BuildContext context) {
    final tr = widget.state.tr;
    final request = widget.request;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    final rawTitle = request['title'] as String?;
    final title = rawTitle == 'Run this command?'
        ? tr('允许执行此命令？', 'Run this command?')
        : rawTitle ?? tr('需要你的批准', 'Approval needed');
    final rawReason = '${request['reason'] ?? ''}';
    final reason =
        rawReason ==
            "A variable in this command can't be checked before it runs"
        ? tr('命令包含运行前无法检查的变量。', rawReason)
        : rawReason;
    final preview = request['preview'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (available * .42).clamp(160.0, 360.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            LucideIcon(
                              'shield-alert',
                              size: 18,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (request['tool'] case final String tool) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 88),
                                child: Text(
                                  tool,
                                  style: theme.textTheme.labelSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (widget.busy) ...[
                              const SizedBox(width: 8),
                              const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              reason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        // What is approved is shown as is: never behind a tap.
                        if (preview is Map)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: preview['t'] == 'diff'
                                ? MessageView(
                                    state: widget.state,
                                    desktopId: widget.desktopId,
                                    projectId: widget.projectId,
                                    item: {
                                      't': 'diff',
                                      'fileName': preview['path'] ?? '',
                                      'directory': '',
                                      'lines': preview['lines'] ?? [],
                                    },
                                  )
                                : DecoratedBox(
                                    key: const ValueKey('approval-command'),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: SelectableText(
                                        '${preview['command'] ?? preview['text'] ?? ''}',
                                        style: MobileTheme.codeStyleOf(context),
                                      ),
                                    ),
                                  ),
                          ),
                        // 总是允许放行什么，逐条列在按钮上方；长了也只占三行。
                        if (!_denying)
                          if (request['always'] case final String always)
                            _AlwaysRules(
                              text: always,
                              tr: tr,
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontFamily: 'monospace',
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        if (_denying)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              key: const ValueKey('approval-deny-reason'),
                              controller: _reason,
                              enabled: !widget.busy && widget.enabled,
                              autofocus: true,
                              minLines: 1,
                              maxLines: 3,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: tr(
                                  '告诉它为什么拒绝、该怎么做（可选）',
                                  'Why, and what to do instead (optional)',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  ),
                if (!widget.enabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      tr(
                        '电脑离线，暂不能提交；连接后继续',
                        'Computer offline. Reconnect to continue.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_denying)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: widget.busy || !widget.enabled
                            ? null
                            : () => _deny(''),
                        child: Text(tr('直接拒绝', 'Just deny')),
                      ),
                      ListenableBuilder(
                        listenable: _reason,
                        builder: (context, _) => FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.error,
                            foregroundColor: colors.onError,
                          ),
                          onPressed:
                              widget.busy ||
                                  !widget.enabled ||
                                  _reason.text.trim().isEmpty
                              ? null
                              : () => _deny(_reason.text.trim()),
                          child: Text(tr('拒绝并发送', 'Deny and send')),
                        ),
                      ),
                    ],
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: widget.busy || !widget.enabled
                            ? null
                            : () => setState(() => _denying = true),
                        child: Text(tr('拒绝', 'Deny')),
                      ),
                      if (request['always'] is String)
                        OutlinedButton(
                          onPressed: widget.busy || !widget.enabled
                              ? null
                              : () => widget.onAnswer({
                                  't': 'approval',
                                  'decision': 'allowAlways',
                                }),
                          child: Text(tr('总是允许', 'Always allow')),
                        ),
                      FilledButton(
                        onPressed: widget.busy || !widget.enabled
                            ? null
                            : () => widget.onAnswer({
                                't': 'approval',
                                'decision': 'allowOnce',
                              }),
                        child: Text(tr('允许一次', 'Allow once')),
                      ),
                    ],
                  ),
                if (_denying)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      onPressed: widget.busy
                          ? null
                          : () => setState(() => _denying = false),
                      child: Text(tr('返回', 'Back')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「总是允许」会放行的那串规则：电脑端给的是一整句 `Always allow Bash(grep …),
/// always allow Read(…)`。按逗号拆成一行一条，最多三行，点开看全部；它放在
/// 按钮上方而不是按钮文字里，规则再长也挤不掉命令和按钮。
class _AlwaysRules extends StatelessWidget {
  const _AlwaysRules({
    required this.text,
    required this.tr,
    required this.style,
  });

  final String text;
  final String Function(String zh, String en) tr;
  final TextStyle style;

  static const _limit = 3;

  /// 逗号分开的规则；括号里的逗号不算。
  static List<String> split(String text) {
    final parts = <String>[];
    var depth = 0, start = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '(':
          depth++;
        case ')':
          if (depth > 0) depth--;
        case ',' when depth == 0:
          parts.add(text.substring(start, i).trim());
          start = i + 1;
      }
    }
    parts.add(text.substring(start).trim());
    return parts.where((part) => part.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rules = split(text);
    final shown = rules.take(_limit).toList();
    final rest = rules.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('总是允许', 'Always allow')),
            content: SingleChildScrollView(
              child: Text(rules.join('\n'), style: style),
            ),
            actions: dialogButtons([
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('关闭', 'Close')),
              ),
            ]),
          ),
        ),
        child: Container(
          key: const ValueKey('approval-always-rules'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('总是允许会放行：', 'Always allow would let through:'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final rule in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    rule,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              if (rest > 0)
                Text(
                  tr(
                    '还有 ${rules.length - shown.length} 项，点开查看',
                    '${rules.length - shown.length} more; tap to see',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
