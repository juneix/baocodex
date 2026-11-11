// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../chat/message_view.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import 'task_stop_button.dart';

Color _statusColor(BuildContext context, String status) {
  final colors = MobileTheme.statusColorsOf(context);
  return switch (status) {
    'running' => colors.info,
    'succeeded' => colors.success,
    'failed' => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    required this.task,
  });
  final AppState state;
  final String desktopId, sessionId;
  final LinkTask task;
  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> with WidgetsBindingObserver {
  bool _stopping = false, _foreground = true, _watching = false;
  String? _error;
  LinkTask get _task {
    for (final task
        in widget.state.buffer(widget.desktopId, widget.sessionId).tasks) {
      if (task.id == widget.task.id) return task;
    }
    return widget.task;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_changed);
    _lastStatus = _task.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncWatch());
    });
  }

  String? _lastStatus;
  void _changed() {
    final status = _task.status;
    final finished = _lastStatus == 'running' && status != 'running';
    _lastStatus = status;
    if (mounted) setState(() {});
    unawaited(_syncWatch());
    if (finished) unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_syncWatch());
  }

  Future<void> _syncWatch() async {
    final wanted = _foreground && _task.output;
    if (wanted == _watching) return;
    _watching = wanted;
    if (wanted) {
      await widget.state.taskOutputs.retain(
        widget.desktopId,
        widget.sessionId,
        widget.task.id,
      );
    } else {
      await widget.state.taskOutputs.release(
        widget.desktopId,
        widget.sessionId,
        widget.task.id,
      );
    }
  }

  Future<void> _refresh() => widget.state.taskOutputs.refresh(
    widget.desktopId,
    widget.sessionId,
    widget.task.id,
  );

  bool get _canStop =>
      !_stopping &&
      widget.state.isOnline(widget.desktopId) &&
      _task.status == 'running';

  Future<void> _stop() async {
    if (!_canStop) return;
    final confirmed = await confirmTaskStop(
      context,
      state: widget.state,
      description: taskTitle(widget.state, _task),
    );
    if (!confirmed || !mounted || !_canStop) return;
    setState(() {
      _stopping = true;
      _error = null;
    });
    try {
      await widget.state.request(widget.desktopId, LinkMethods.stopTask, {
        'session': widget.sessionId,
        'task': widget.task.id,
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = taskStopFailure(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    if (_watching) {
      _watching = false;
      unawaited(
        widget.state.taskOutputs.release(
          widget.desktopId,
          widget.sessionId,
          widget.task.id,
        ),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.state.tr;
    final output = widget.state.taskOutputs.peek(
      widget.desktopId,
      widget.sessionId,
      widget.task.id,
    );
    final text = output?.text ?? '';
    final error = _error ?? output?.error;
    return Scaffold(
      appBar: AppBar(
        title: Text(taskKindLabel(widget.state, _task.kind)),
        actions: [
          IconButton(
            tooltip: tr('刷新输出', 'Refresh output'),
            onPressed: _refresh,
            icon: const LucideIcon('refresh-cw', size: 20),
          ),
          if (_task.status == 'running')
            StopActionButton(
              tooltip: tr('停止任务', 'Stop task'),
              busy: _stopping,
              onPressed: _canStop ? _stop : null,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            taskTitle(widget.state, _task),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            taskStatusLabel(widget.state, _task.status),
            style: MobileTheme.hintStyleOf(
              context,
              color: _statusColor(context, _task.status),
            ),
          ),
          const SizedBox(height: 8),
          if (_task.command != null)
            CodePanel(code: _task.command!, language: 'command'),
          if (_task.summary != null) Text(_task.summary!),
          if (error != null)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_task.output)
            CodePanel(
              code: text.isEmpty ? tr('尚无输出', 'No output yet') : text,
              language: 'output',
            )
          else
            Text(
              tr(
                '此任务不提供终端输出。进度会随会话更新。',
                'This task has no terminal output. Progress updates with the conversation.',
              ),
            ),
        ],
      ),
    );
  }
}

class TasksPage extends StatelessWidget {
  const TasksPage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
  });
  final AppState state;
  final String desktopId, sessionId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final tasks = state.buffer(desktopId, sessionId).tasks;
      return Scaffold(
        appBar: AppBar(title: Text(state.tr('后台任务', 'Background tasks'))),
        body: tasks.isEmpty
            ? EmptyPanel(
                state.tr('没有后台任务', 'No background tasks'),
                icon: Icons.task_alt,
              )
            : ListView.separated(
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final task = tasks[i];
                  final status = taskStatusLabel(state, task.status);
                  final summary = task.summary?.trim();
                  return ListTile(
                    key: ValueKey('task-row-${task.id}'),
                    leading: LucideIcon(taskKindIcon(task.kind), size: 22),
                    title: Text(
                      taskTitle(state, task),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: status,
                            style: TextStyle(
                              color: _statusColor(context, task.status),
                            ),
                          ),
                          TextSpan(
                            text: ' · ${taskKindLabel(state, task.kind)}',
                          ),
                          if (summary != null && summary.isNotEmpty)
                            TextSpan(text: '\n$summary'),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const LucideIcon('chevron-right', size: 18),
                    onTap: () => openPage<void>(
                      context,
                      TaskPage(
                        state: state,
                        desktopId: desktopId,
                        sessionId: sessionId,
                        task: task,
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}
