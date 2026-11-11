// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/mobile_widgets.dart' show openPage;
import '../widgets/lucide_icon.dart';
import 'changes_page.dart';
import 'running_agents.dart';
import 'task_stop_button.dart';

/// 输入框上方的托盘：运行中的任务与未处理的改动。
///
/// 平时收成输入框上方居中的小胶囊，只显示摘要，里面没有可误触的操作；
/// 点开向上长成面板：任务和文件各是一个圆角块，可进入、停止、保留、撤回。
/// 再点、滚动消息或返回都会收起。
class ChatActivityCard extends StatefulWidget {
  const ChatActivityCard({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    required this.agents,
    required this.onOpenAgent,
    this.projectId,
    this.foldSignal,
  });

  final AppState state;
  final String desktopId, sessionId;
  final String? projectId;
  final List<RunningAgent> agents;

  /// 打开子代理或后台命令的页面。命令任务只带 [RunningAgent.task]。
  final ValueChanged<RunningAgent> onOpenAgent;

  /// 用户开始滚动消息时触发，面板随之收起。
  final Listenable? foldSignal;

  @override
  State<ChatActivityCard> createState() => _ChatActivityCardState();
}

/// 堆叠里的一项：子代理或后台命令，统一成标题、动作和停止参数。
class _Entry {
  const _Entry({
    required this.key,
    required this.title,
    required this.target,
    this.activity,
    required this.agent,
    required this.background,
    this.stop,
    this.at,
  });

  final String key, title;
  final bool agent;

  /// Left running on its own; a subagent of the turn under way is not.
  final bool background;
  final String? activity;
  final RunningAgent target;

  /// stopTask 的 `agent` / `task` 参数；两者都没有时不能停止。
  final Map<String, Object?>? stop;
  final DateTime? at;
}

/// 任务行与文件行同高，面板块间距同一档。
const _rowHeight = 48.0;
const _blockGap = 6.0;
final _runningPrefix = RegExp(r'^running\s+', caseSensitive: false);

class _ChatActivityCardState extends State<ChatActivityCard>
    with ChangeActions {
  bool _open = false;
  final Set<String> _stopping = {};
  String? _stopError;

  @override
  AppState get state => widget.state;
  @override
  String get desktopId => widget.desktopId;
  @override
  String get sessionId => widget.sessionId;

  @override
  void initState() {
    super.initState();
    widget.foldSignal?.addListener(_fold);
  }

  @override
  void didUpdateWidget(ChatActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.foldSignal == widget.foldSignal) return;
    oldWidget.foldSignal?.removeListener(_fold);
    widget.foldSignal?.addListener(_fold);
  }

  @override
  void dispose() {
    widget.foldSignal?.removeListener(_fold);
    super.dispose();
  }

  void _fold() {
    if (_open) setState(() => _open = false);
  }

  List<_Entry> _entries(List<LinkTask> tasks) {
    final tr = state.tr;
    final entries = <_Entry>[];
    for (final agent in widget.agents) {
      final task = agent.task, item = agent.item;
      final toolUse = task?.toolUseId ?? item?.id;
      final description = task?.description.isNotEmpty == true
          ? task!.description
          : (item?.description.isNotEmpty == true
                ? item!.description
                : tr('子代理', 'Subagent'));
      entries.add(
        _Entry(
          key: 'agent:${toolUse ?? task?.id ?? description}',
          title: description,
          activity: task?.summary ?? item?.activity,
          target: agent,
          agent: true,
          // The desktop reports only background tasks.
          background: task != null || (item?.background ?? false),
          stop: toolUse != null
              ? {'agent': toolUse}
              : (task != null ? {'task': task.id} : null),
          at: task?.startedAt ?? item?.startedAt,
        ),
      );
    }
    for (final task in tasks) {
      // Agents come above, by their cards; commands and any other kind
      // (a monitor, a workflow) here, as the desktop's strip lists them.
      if (task.kind == 'agent' || task.status != 'running') continue;
      entries.add(
        _Entry(
          key: 'task:${task.id}',
          title: taskTitle(state, task),
          activity: task.summary ?? task.command,
          target: RunningAgent(task: task),
          agent: false,
          background: true,
          stop: {'task': task.id},
          at: task.startedAt,
        ),
      );
    }
    // 最近启动的在最前；没有时间的按出现顺序，后出现的更新。
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
    indexed.sort((a, b) {
      final byTime = (b.$2.at ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.$2.at ?? DateTime.fromMillisecondsSinceEpoch(0));
      return byTime != 0 ? byTime : b.$1.compareTo(a.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  String _countLabel(List<_Entry> entries) {
    final n = entries.length;
    if (n == 0) return state.tr('待处理改动', 'Unkept changes');
    if (entries.every((e) => e.agent)) {
      return state.tr('$n 个子代理运行中', '$n subagents running');
    }
    if (entries.every((e) => e.background)) {
      return state.tr('$n 个后台任务运行中', '$n background tasks running');
    }
    return state.tr('$n 个任务运行中', '$n tasks running');
  }

  Future<void> _stop(_Entry entry) async {
    final stop = entry.stop;
    if (stop == null ||
        _stopping.contains(entry.key) ||
        !state.isOnline(desktopId)) {
      return;
    }
    final confirmed = await confirmTaskStop(
      context,
      state: state,
      description: entry.title,
    );
    if (!confirmed ||
        !mounted ||
        !state.isOnline(desktopId) ||
        _stopping.contains(entry.key)) {
      return;
    }
    setState(() {
      _stopping.add(entry.key);
      _stopError = null;
    });
    try {
      await state.request(desktopId, LinkMethods.stopTask, {
        'session': sessionId,
        ...stop,
      });
    } catch (failure) {
      if (mounted) setState(() => _stopError = taskStopFailure(state, failure));
    } finally {
      if (mounted) setState(() => _stopping.remove(entry.key));
    }
  }

  Widget _stopButton(_Entry entry) => StopActionButton(
    key: ValueKey('task-stop-${entry.key}'),
    tooltip: state.tr('停止', 'Stop'),
    busy: _stopping.contains(entry.key),
    onPressed: entry.stop == null || !state.isOnline(desktopId)
        ? null
        : () => _stop(entry),
  );

  /// 面板里的一块：圆角、页面底色，块与块之间露出面板。
  Widget _block({Key? key, required Widget child}) => Material(
    key: key,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _taskRow(_Entry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 卡片本身已表示运行中，桌面端摘要开头的 Running 不再重复。
    final activity = entry.activity?.trim().replaceFirst(_runningPrefix, '');
    return InkWell(
      key: ValueKey('task-card-${entry.key}'),
      onTap: () => widget.onOpenAgent(entry.target),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: const EdgeInsets.only(
            left: MobileSpace.md,
            right: MobileSpace.xs,
          ),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 24,
                child: Center(child: _RunningRing(size: 18)),
              ),
              const SizedBox(width: MobileSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (activity != null &&
                        activity.isNotEmpty &&
                        activity != entry.title.trim())
                      Text(
                        activity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: MobileType.aside,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              _stopButton(entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _changesRow(List<Map<String, Object?>> changes) {
    final tr = state.tr;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (added, removed) = changeTotals(changes);
    final auto = state.settings.autoKeep;
    final summary = InkWell(
      key: const ValueKey('activity-changes-toggle'),
      onTap: () => openPage<void>(
        context,
        ChangesPage(
          state: state,
          desktopId: desktopId,
          sessionId: sessionId,
          projectId: widget.projectId,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MobileSpace.md),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: Center(
                  child: LucideIcon(
                    'file-diff',
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: MobileSpace.md),
              Flexible(
                child: Text(
                  tr(
                    '${changes.length} 个文件',
                    changes.length == 1 ? '1 file' : '${changes.length} files',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: MobileSpace.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ChangeCounts(added: added, removed: removed),
                ),
              ),
              // Kept as the turn ends: the count only, the switch in the page.
              if (auto) ...[
                const Spacer(),
                Text(
                  tr('自动保留', 'Auto keep'),
                  key: const ValueKey('activity-auto-keep'),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: MobileSpace.xs),
                LucideIcon(
                  'chevron-right',
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (auto) return summary;
    return Row(
      children: [
        Expanded(child: summary),
        Tooltip(
          message: tr('撤回全部改动', 'Undo all changes'),
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: MobileSpace.md),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: enabled ? () => apply(true) : null,
            child: Text(tr('撤回', 'Undo')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: MobileSpace.sm),
          child: Tooltip(
            message: tr('保留全部改动', 'Keep all changes'),
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: MobileSpace.lg),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: enabled ? () => apply(false) : null,
              child: Text(tr('保留', 'Keep')),
            ),
          ),
        ),
      ],
    );
  }

  /// 折叠时的胶囊：只有摘要，宽度随内容，点开才有操作。
  Widget _pill(
    List<_Entry> entries,
    List<Map<String, Object?>> changes, {
    required bool attention,
  }) {
    final tr = state.tr;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(
      fontSize: MobileType.aside,
    );
    final (added, removed) = changeTotals(changes);
    final files = Text(
      tr(
        '${changes.length} 个文件',
        changes.length == 1 ? '1 file' : '${changes.length} files',
      ),
      style: style,
    );
    final tasks = entries.length;
    return Center(
      heightFactor: 1,
      child: Semantics(
        button: true,
        label: tr('展开任务和改动', 'Show tasks and changes'),
        child: GestureDetector(
          key: const ValueKey('activity-tasks-expand'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = true),
          // 视觉 32 高，点击区上下各多 6，凑够 44。
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              key: const ValueKey('activity-pill'),
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: MobileSpace.md),
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerLowest,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: scheme.onSurfaceVariant.withValues(alpha: .18),
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (attention)
                    Container(
                      key: const ValueKey('activity-attention'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (tasks > 0)
                    const _RunningRing(size: 14)
                  else
                    LucideIcon(
                      'file-diff',
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: MobileSpace.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (tasks > 0)
                            Text(
                              tr(
                                '$tasks 个任务',
                                tasks == 1 ? '1 task' : '$tasks tasks',
                              ),
                              style: style,
                            ),
                          if (tasks > 0 && changes.isNotEmpty)
                            Text(' · ', style: style),
                          if (changes.isNotEmpty) ...[
                            if (tasks == 0 || changes.length > 1) files,
                            if (tasks == 0)
                              const SizedBox(width: MobileSpace.sm),
                            if (tasks == 0 || changes.length == 1)
                              ChangeCounts(
                                added: added,
                                removed: removed,
                                compact: true,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: MobileSpace.xs),
                  LucideIcon(
                    'chevron-up',
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 展开时的面板：任务在内部滚动，文件块固定在最下面。
  Widget _panel(List<_Entry> entries, List<Map<String, Object?>> changes) {
    final tr = state.tr;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        key: const ValueKey('activity-tasks-open'),
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.onSurfaceVariant.withValues(alpha: .18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _blockGap,
            0,
            _blockGap,
            _blockGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const ValueKey('activity-tasks-collapse'),
                onTap: _fold,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MobileSpace.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _countLabel(entries),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Text(
                          tr('收起', 'Collapse'),
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: MobileSpace.xs),
                        LucideIcon(
                          'chevron-down',
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (entries.isNotEmpty)
                Flexible(
                  // 约三块半，多的在面板里滚动。
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 192),
                    child: ListView.separated(
                      key: const ValueKey('activity-task-list'),
                      shrinkWrap: true,
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: _blockGap),
                      itemBuilder: (_, i) =>
                          _block(child: _taskRow(entries[i])),
                    ),
                  ),
                ),
              if (entries.isNotEmpty && changes.isNotEmpty)
                const SizedBox(height: _blockGap),
              if (changes.isNotEmpty)
                _block(
                  key: const ValueKey('activity-changes-block'),
                  child: _changesRow(changes),
                ),
              if (busy) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buffer = state.buffer(desktopId, sessionId);
    final changes = buffer.changes;
    final entries = _entries(buffer.tasks);
    if (entries.isEmpty && changes.isEmpty) {
      _open = false;
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final available =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                kToolbarHeight -
                160)
            .clamp(160.0, double.infinity)
            .toDouble();

    return PopScope(
      // 返回先收起面板，再离开对话。
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _fold();
      },
      child: Column(
        key: const ValueKey('chat-activity-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: available * .7),
              child: _open
                  ? _panel(entries, changes)
                  : _pill(
                      entries,
                      changes,
                      attention: buffer.interaction != null,
                    ),
            ),
          ),
          if (_stopError != null) ChangeError(_stopError!),
          if (error != null) ChangeError(error!),
        ],
      ),
    );
  }
}

/// 运行中的转圈，所有任务共用，里面不放图标。
class _RunningRing extends StatelessWidget {
  const _RunningRing({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 1.5,
      color: MobileTheme.statusColorsOf(context).info,
    ),
  );
}
