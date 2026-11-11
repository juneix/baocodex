// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// 同步超过 300ms 才算“同步中”，快同步不闪；由标题下的状态行显示，不占独立一行。
class SessionSyncGate extends StatefulWidget {
  const SessionSyncGate({
    super.key,
    required this.online,
    required this.loading,
    required this.builder,
  });
  final bool online, loading;
  final Widget Function(BuildContext context, bool syncing) builder;

  @override
  State<SessionSyncGate> createState() => _SessionSyncGateState();
}

class _SessionSyncGateState extends State<SessionSyncGate> {
  Timer? _delay;
  bool _show = false;

  void _wait() {
    _delay?.cancel();
    if (!widget.online || !widget.loading) return;
    _delay = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !widget.online || !widget.loading) return;
      setState(() => _show = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _wait();
  }

  @override
  void didUpdateWidget(SessionSyncGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.online || !widget.loading) {
      _delay?.cancel();
      _show = false;
    } else if (!oldWidget.online || !oldWidget.loading) {
      _wait();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _show && widget.online && widget.loading);
}

/// 内容同步失败时保留旧消息并提供重试（同步中由标题状态行表示）。
class SessionSyncNotice extends StatefulWidget {
  const SessionSyncNotice({
    super.key,
    required this.state,
    required this.online,
    required this.loading,
    required this.onRetry,
    required this.onLayoutChange,
    this.error,
  });
  final AppState state;
  final bool online, loading;
  final String? error;
  final VoidCallback onRetry, onLayoutChange;

  @override
  State<SessionSyncNotice> createState() => _SessionSyncNoticeState();
}

class _SessionSyncNoticeState extends State<SessionSyncNotice> {
  bool _visible(SessionSyncNotice value) => value.online && value.error != null;

  @override
  void didUpdateWidget(SessionSyncNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visible(oldWidget) != _visible(widget) ||
        oldWidget.error != widget.error) {
      widget.onLayoutChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible(widget)) return const SizedBox.shrink();
    final tr = widget.state.tr;
    final error = widget.error!;
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(tr('同步失败', 'Sync failed')),
                    content: SelectableText(error),
                    actions: dialogButtons([
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('关闭', 'Close')),
                      ),
                    ]),
                  ),
                ),
                child: Text(
                  tr('内容未更新', 'Messages are not up to date'),
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ),
            TextButton(
              onPressed: widget.loading ? null : widget.onRetry,
              style: TextButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(tr('重试', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
