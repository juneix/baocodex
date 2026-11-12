import 'dart:async';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'quota_panel.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/model_icon.dart';
import '../widgets/scale_slider.dart';
import '../user_message.dart';
import '../widgets/mobile_widgets.dart';

/// Uses the current desktop snapshot, including the selected model's settings.
/// No model capabilities or option labels are guessed on the phone.
class ModelSettingsSheet extends StatefulWidget {
  const ModelSettingsSheet({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    this.isCurrent,
  });

  final AppState state;
  final String desktopId, sessionId;
  final bool Function()? isCurrent;

  @override
  State<ModelSettingsSheet> createState() => _ModelSettingsSheetState();
}

class _ModelSettingsSheetState extends State<ModelSettingsSheet> {
  String _query = '';
  String? _error, _pendingModel;
  bool _busy = false;
  String? _expandedModel;
  Timer? _confirmation;
  late final QuotaController _quota;

  String tr(String zh, String en) => widget.state.tr(zh, en);
  List<LinkChoice> get _choices =>
      widget.state.buffer(widget.desktopId, widget.sessionId).choices;
  LinkChoice? get _model =>
      _choices.where((choice) => choice.kind == 'model').firstOrNull;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
    _quota = QuotaController(widget.state, widget.desktopId, widget.sessionId)
      ..addListener(_changed);
    _quota.load();
  }

  void _changed() {
    if (_pendingModel == _model?.selected) {
      _pendingModel = null;
      _confirmation?.cancel();
    }
    // 电脑上已经选上了这一档：滑块不再自己记着，跟着会话的快照走。
    _sliderCommitted.removeWhere(
      (kind, committed) => _choices.any(
        (choice) => choice.kind == kind && choice.selected == committed,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _quota.removeListener(_changed);
    _quota.dispose();
    _confirmation?.cancel();
    super.dispose();
  }

  /// 各滑块上还没送到电脑的取值，按 [LinkChoice.kind] 分开记：值一动就现显示，
  /// 停下来才发。共用一个的话，拖上下文时推理强度会读到别人的值跳走。
  final _sliderCommitted = <String, String>{};

  /// 现在能不能发：在线、不忙、会话还是同一个，模型也不在等新快照。
  bool get _ready =>
      !_busy &&
      _pendingModel == null &&
      widget.state.isOnline(widget.desktopId) &&
      (widget.isCurrent?.call() ?? true);

  /// 换成另一个上游的模型时，电脑要重启 Claude Code 并把当前对话接过去：
  /// 这会有一次较慢的首次处理，先问一声。对话还没开始时不用问，电脑直接换。
  bool _switchesUpstream(LinkChoice choice, LinkOption option) {
    if (choice.kind != 'model') return false;
    final buffer = widget.state.peekBuffer(widget.desktopId, widget.sessionId);
    if (buffer == null || buffer.items.isEmpty) return false;
    final current = choice.options
        .where((entry) => entry.id == choice.selected)
        .firstOrNull;
    if (current == null) return false;
    return (option.group ?? '') != (current.group ?? '');
  }

  /// 只讲一件事、只有一个「知道了」。
  Future<void> _note(String title, String body) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: dialogButtons([
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('知道了', 'Got it')),
        ),
      ]),
    ),
  );

  /// 一句标题、一段说明、取消和确认：换上游和开启有风险的选项都走这一张。
  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirm,
    bool warning = false,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: dialogButtons([
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            style: warning
                ? FilledButton.styleFrom(
                    backgroundColor: MobileTheme.statusColorsOf(context)
                        .warning,
                    foregroundColor: Colors.black,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ]),
      ),
    );
    // 确认的这会儿可能掉了线，或者会话已经换了。
    return mounted && answer == true && _ready;
  }

  /// Sends [option] to the desktop for [choice]; false when it did not go,
  /// so a slider can put its thumb back where the session still has it.
  Future<bool> _choose(LinkChoice choice, LinkOption option) async {
    if (!_ready) return false;
    if (choice.kind != 'fast' && choice.selected == option.id) return true;
    if (_switchesUpstream(choice, option)) {
      final name = option.groupLabel ?? option.group ?? option.label;
      final confirmed = await _confirm(
        title: tr('切换到 $name？', 'Switch to $name?'),
        content: tr(
          'Claude Code 会在新上游上重启，并用 --resume 接续当前对话。'
              '历史记录会原样发给新模型，部分上游首次处理会较慢。'
              '如果还有回复在进行，发送下一条消息时会先停止它。',
          'Claude Code restarts on the other upstream and resumes this '
              'conversation with --resume. Its history is sent to the new '
              'model as it is; some upstreams take it slower the first time. '
              'A reply still running stops when you send the next message.',
        ),
        confirm: tr('切换', 'Switch'),
      );
      if (!confirmed) return false;
    }
    if (option.caution) {
      final confirmed = await _confirm(
        title: option.label,
        content: option.description,
        confirm: tr('开启', 'Turn on'),
        warning: true,
      );
      if (!confirmed) return false;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (choice.kind == 'model') {
        _pendingModel = option.id;
        _expandedModel = null;
      }
    });
    try {
      await widget.state.request(widget.desktopId, LinkMethods.choose, {
        'session': widget.sessionId,
        'kind': choice.kind,
        'option': option.id,
      });
      if (!mounted) return false;
      if (_pendingModel == _model?.selected) _pendingModel = null;
      if (_pendingModel != null) {
        _confirmation?.cancel();
        _confirmation = Timer(const Duration(seconds: 8), () {
          if (!mounted) return;
          setState(() {
            _pendingModel = null;
            _error = tr(
              '尚未收到模型更新，请核对当前选中项。不会自动重试。',
              'Model update not received. Check the current selection. No automatic retry.',
            );
          });
        });
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      _pendingModel = null;
      _error = userMessage(widget.state, error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 和电脑端一样：模型名认得出的厂商 logo，认不出看上游，再认不出一个脑子。
  Widget _icon(LinkOption option) => ModelIcon.ofId(
    option.id,
    provider: option.group,
    providerLabel: option.groupLabel,
    size: 24,
    color: Theme.of(context).colorScheme.onSurface,
  );

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final colors = Theme.of(context).colorScheme;
    final online = widget.state.isOnline(widget.desktopId);
    final current = widget.isCurrent?.call() ?? true;
    // 能不能点跟 [_ready] 是同一条规矩；这里还要知道是哪一条不满足，好说清。
    final enabled = _ready;
    final options =
        model?.options
            .where(
              (option) =>
                  '${option.label} ${option.groupLabel ?? option.group ?? ''}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
            )
            .toList() ??
        [];
    final groups = <String>{};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('模型', 'Model'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: tr('关闭', 'Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        SearchCapsule(
          state: widget.state,
          hint: tr('搜索模型', 'Search models'),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (!online || !current || _error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              _error ??
                  (!current
                      ? tr(
                          '会话已变化，请关闭后重新选择模型。',
                          'Conversation changed. Close and reopen the model settings.',
                        )
                      : tr(
                          '电脑已离线，连接后可修改设置。',
                          'Desktop offline. Reconnect to change settings.',
                        )),
              style: TextStyle(color: colors.error),
            ),
          ),
        if (_busy || _pendingModel != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('正在更新设置…', 'Updating settings…')),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('没有匹配模型', 'No matching models')),
                ),
              for (final option in options) ...[
                if ((option.groupLabel ?? option.group)
                    case final String group
                    when group.isNotEmpty && groups.add(group)) ...[
                  // 换一个上游就是换一节：上面一条线，和电脑端的菜单一样。
                  if (groups.length > 1) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                    child: QuotaPanel(
                      key: ValueKey(option.group ?? group),
                      controller: _quota,
                      provider: option.group ?? group,
                      title: group,
                    ),
                  ),
                ],
                Material(
                  color: option.id == model?.selected
                      ? colors.surfaceContainerHighest
                      : colors.surface,
                  borderRadius: BorderRadius.circular(MobileSizes.radius),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        enabled: enabled,
                        leading: _icon(option),
                        title: Text(option.label),
                        trailing: option.id == model?.selected
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    _expandedModel == option.id
                                        ? Icons.expand_more
                                        : Icons.chevron_right,
                                  ),
                                ],
                              )
                            : option.caution
                            ? const Icon(Icons.warning_amber_rounded)
                            : null,
                        onTap: () {
                          if (option.id == model?.selected) {
                            setState(
                              () => _expandedModel =
                                  _expandedModel == option.id
                                  ? null
                                  : option.id,
                            );
                          } else {
                            _choose(model!, option);
                          }
                        },
                      ),
                      if (option.id == model?.selected &&
                          _expandedModel == option.id &&
                          _pendingModel == null)
                        for (final setting in _choices.where(
                          _shownAsSetting,
                        ))
                          _setting(setting, enabled),
                    ],
                  ),
                ),
              ],
              ListTile(
                key: const ValueKey('manage-models'),
                leading: const LucideIcon('settings', size: 22),
                title: Text(tr('管理模型…', 'Manage models…')),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MobileSizes.radius),
                ),
                onTap: () => _note(
                  tr('管理模型', 'Manage models'),
                  tr(
                    '上游和模型在电脑上的设置 → 模型里管理；'
                        '添加或改动后，这里会自动出现。',
                    'Upstreams and models are managed on the computer, '
                        'in Settings → Models. Whatever you add or change '
                        'shows up here.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 上下文、推理强度、快速：选中模型下面露出来的几行。只有一档的滑不动，
  /// 也就不画那根滑轨。
  static bool _shownAsSetting(LinkChoice choice) => switch (choice.kind) {
    'fast' => choice.options.isNotEmpty,
    'context' || 'effort' => choice.options.length > 1,
    _ => false,
  };

  Widget _setting(LinkChoice choice, bool enabled) {
    final label = switch (choice.kind) {
      'context' => tr('上下文', 'Context'),
      'effort' => tr('推理强度', 'Effort'),
      _ => tr('快速', 'Fast'),
    };
    if (choice.kind == 'fast') {
      return SwitchListTile(
        title: Text(label),
        value: choice.selected == 'fast',
        onChanged: enabled
            ? (_) => _choose(choice, choice.options.first)
            : null,
      );
    }
    return _sliderSetting(choice, label, enabled);
  }

  /// 一档一个刻度的滑块：标题在上、当前档在右，轨道下写着首尾两档。
  ///
  /// 手还没松时滑块停在 [_sliderCommitted] 上，只是先显示；松手才发给电脑，
  /// 没发出去就退回会话快照里的那一档。
  Widget _sliderSetting(LinkChoice choice, String label, bool enabled) {
    final options = choice.options;
    final selected =
        _sliderCommitted[choice.kind] ?? choice.selected ?? options.first.id;
    final at = math.max(0, options.indexWhere((o) => o.id == selected));
    final scheme = Theme.of(context).colorScheme;
    final ink = MobileTheme.metaStyleOf(context);
    LinkOption optionAt(double value) => options[value.round()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                options[at].label,
                key: ValueKey('${choice.kind}:value'),
                style: MobileTheme.metaStyleOf(context, color: scheme.primary),
              ),
            ],
          ),
          ScaleSlider(
            key: ValueKey('${choice.kind}:slider'),
            value: at.toDouble(),
            min: 0,
            max: (options.length - 1).toDouble(),
            divisions: options.length - 1,
            enabled: enabled,
            onTick: () => unawaited(widget.state.haptic('selection')),
            onChanged: (value) {
              final option = optionAt(value);
              if (option.id == selected) return;
              setState(() => _sliderCommitted[choice.kind] = option.id);
            },
            onChangeEnd: (value) async {
              final sent = await _choose(choice, optionAt(value));
              if (!mounted) return;
              if (!sent) setState(() => _sliderCommitted.remove(choice.kind));
            },
          ),
          Row(
            children: [
              Text(options.first.label, style: ink),
              const Spacer(),
              Text(options.last.label, style: ink),
            ],
          ),
        ],
      ),
    );
  }
}
