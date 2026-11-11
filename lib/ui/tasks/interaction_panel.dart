// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'approval_card.dart';
import '../user_message.dart';
import '../widgets/fold_row.dart';

/// The answers here are the public InteractionCodec.decodeAnswer wire shapes.
class InteractionPanel extends StatefulWidget {
  const InteractionPanel({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    required this.request,
    this.projectId,
    this.enabled = true,
  });
  final AppState state;
  final String desktopId, sessionId;
  final String? projectId;
  final Map<String, Object?> request;
  final bool enabled;
  @override
  State<InteractionPanel> createState() => _InteractionPanelState();
}

class _InteractionPanelState extends State<InteractionPanel> {
  final _picks = <int, Set<String>>{};
  final _other = <int, String>{};
  final _otherEnabled = <int>{};
  bool _busy = false;

  /// Skip was tapped: it is asked once more, beside the way back.
  bool _skipping = false;
  String? _error;

  Future<void> _answer(Map<String, Object?> answer) async {
    if (_busy || !widget.enabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Typed literal: tests match the captured record's runtime type.
      await widget.state.request(
        widget.desktopId,
        LinkMethods.answer,
        <String, Object>{
          'session': widget.sessionId,
          'request': widget.request['id']!,
          'answer': answer,
        },
      );
      // Leave disabled until the authoritative interaction disappears. Never replay a write.
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = userMessage(widget.state, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.state.tr;
    final request = widget.request;
    if (request['t'] == 'approval') {
      return ApprovalCard(
        state: widget.state,
        desktopId: widget.desktopId,
        projectId: widget.projectId,
        request: request,
        busy: _busy,
        enabled: widget.enabled,
        error: _error,
        onAnswer: _answer,
      );
    }
    final questions = (request['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList();
    final theme = Theme.of(context);
    final isQuestion = request['t'] == 'question';
    final ready =
        questions.isNotEmpty &&
        !List.generate(questions.length, (i) => i).any(
          (i) =>
              (_picks[i]?.isEmpty ?? true) &&
              (!_otherEnabled.contains(i) ||
                  (_other[i]?.trim().isEmpty ?? true)),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              ((MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          MediaQuery.paddingOf(context).vertical) *
                      .45)
                  .clamp(96, double.infinity)
                  .toDouble(),
        ),
        // The questions scroll; the title and the buttons stay in sight.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // The desktop's title for a question is a fixed English line.
              isQuestion
                  ? tr('需要你回答', 'Your answer is needed')
                  : request['title'] as String? ??
                        tr('需要你的答复', 'Your response is needed'),
              style: theme.textTheme.titleSmall,
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isQuestion)
                      for (var i = 0; i < questions.length; i++)
                        _question(i, questions[i])
                    else
                      SelectableText(
                        tr(
                          '此交互类型尚不支持，请在电脑端处理。',
                          'This interaction is not supported yet. Respond on the desktop.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (!widget.enabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(
                    '电脑离线，暂不能提交；连接后继续',
                    'Computer offline. Reconnect to continue.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_busy) const ThinProgress(),
            if (isQuestion && _skipping)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('不回答，让它自己判断？', 'Skip, and let it decide?'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _skipping = false),
                    child: Text(tr('返回', 'Back')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('question-skip-confirm'),
                    onPressed: _busy || !widget.enabled
                        ? null
                        : () => _answer({'t': 'question', 'skipped': true}),
                    child: Text(tr('确认跳过', 'Skip')),
                  ),
                ],
              )
            else if (isQuestion)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy || !widget.enabled
                        ? null
                        : () => setState(() => _skipping = true),
                    child: Text(tr('跳过', 'Skip')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy || !widget.enabled || !ready
                        ? null
                        : () => _answer({
                            't': 'question',
                            'picks': [
                              for (var i = 0; i < questions.length; i++)
                                [
                                  ...?_picks[i],
                                  if (_otherEnabled.contains(i) &&
                                      (_other[i]?.trim().isNotEmpty ?? false))
                                    _other[i]!.trim(),
                                ],
                            ],
                          }),
                    child: Text(tr('回答', 'Answer')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _question(int i, Map<String, Object?> question) {
    final multiple = question['multiple'] == true;
    final options = (question['options'] as List? ?? const []).whereType<Map>();
    void select(String label, bool selected) => setState(() {
      if (!multiple) {
        _picks[i] = {};
        _otherEnabled.remove(i);
      }
      final picks = _picks.putIfAbsent(i, () => <String>{});
      selected ? picks.add(label) : picks.remove(label);
    });
    final theme = Theme.of(context);
    Widget checkbox({
      required bool value,
      required Widget title,
      Widget? subtitle,
      required ValueChanged<bool?>? onChanged,
    }) => Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        dense: true,
        minVerticalPadding: 2,
        horizontalTitleGap: 4,
        visualDensity: VisualDensity.standard,
        minTileHeight: 48,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        // A long description must not leave the box floating mid-way.
        titleAlignment: ListTileTitleAlignment.top,
        // One answer: round, as a radio button is.
        checkboxShape: multiple ? null : const CircleBorder(),
        value: value,
        title: title,
        subtitle: subtitle,
        onChanged: onChanged,
      ),
    );
    final description = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question['header'] != null)
            Text(
              '${question['header']}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              '${question['prompt'] ?? ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Own Material per tile: the panel Container's background would otherwise
          // hide the tile's ink splashes (framework assertion in widget tests).
          for (final option in options)
            checkbox(
              value: _picks[i]?.contains(option['label']) ?? false,
              title: Text('${option['label'] ?? ''}'),
              subtitle: option['description'] == null
                  ? null
                  : Text('${option['description']}', style: description),
              onChanged: _busy
                  ? null
                  : (selected) =>
                        select('${option['label'] ?? ''}', selected ?? false),
            ),
          if (question.containsKey('other')) ...[
            checkbox(
              title: Text(
                (question['other'] as String? ?? '').isEmpty
                    ? widget.state.tr('其他', 'Other')
                    : question['other'] as String,
              ),
              value: _otherEnabled.contains(i),
              onChanged: _busy
                  ? null
                  : (selected) => setState(() {
                      if (selected == true) {
                        if (!multiple) _picks[i] = {};
                        _otherEnabled.add(i);
                      } else {
                        _otherEnabled.remove(i);
                      }
                    }),
            ),
            if (_otherEnabled.contains(i))
              TextField(
                enabled: !_busy,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.state.tr('你的回答', 'Your answer'),
                ),
                onChanged: (value) => setState(() => _other[i] = value),
              ),
          ],
        ],
      ),
    );
  }
}
