import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/formats.dart';

class QuotaController extends ChangeNotifier {
  QuotaController(this.state, this.desktopId, this.sessionId) {
    _online = state.isOnline(desktopId);
    // The last quota this desktop gave, shown at once while a fresh one loads.
    if (_cache[state]?[desktopId] case final cached?) {
      _providers = [...cached];
      _schedule();
    }
    state.addListener(_changed);
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed) notifyListeners();
    });
  }
  final AppState state;
  final String desktopId, sessionId;
  bool busy = false, _unsupported = false, _disposed = false;
  late bool _online;
  List<Map> _providers = [];
  static final _expanded = Expando<Map<String, bool>>();
  static final _cache = Expando<Map<String, List<Map>>>();
  Timer? _minute, _reset;
  bool failed = false;
  bool get unsupported => _unsupported;
  bool isOpen(String provider) =>
      (_expanded[state] ??= {})['$desktopId/$provider'] ?? false;
  void toggle(String provider) {
    final values = _expanded[state] ??= {};
    values['$desktopId/$provider'] = !isOpen(provider);
    notifyListeners();
  }

  void _schedule() {
    _reset?.cancel();
    final now = DateTime.now();
    final times = <DateTime>[];
    for (final provider in _providers) {
      for (final account in accounts(provider['id'] as String)) {
        for (final window
            in (account['windows'] as List? ?? []).whereType<Map>()) {
          if (window['resetsAt'] case final num at) {
            final reset = DateTime.fromMillisecondsSinceEpoch(at.toInt())
                .add(const Duration(seconds: 2));
            if (reset.isAfter(now)) times.add(reset);
          }
        }
      }
    }
    times.sort();
    if (times.isNotEmpty) {
      _reset = Timer(times.first.difference(now), () => load(refresh: true));
    }
  }

  List<Map> accounts(String provider) =>
      (_providers
                      .where((entry) => entry['id'] == provider)
                      .firstOrNull?['accounts']
                  as List? ??
              [])
          .whereType<Map>()
          .toList();
  void _changed() {
    final online = state.isOnline(desktopId);
    if (online && !_online) {
      _unsupported = false;
      load();
    }
    _online = online;
  }

  Future<void> load({String? provider, bool refresh = false}) async {
    if (busy || _unsupported) return;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      final result = await state
          .request(desktopId, LinkMethods.quota, {
            'session': sessionId,
            'provider': ?provider,
            if (refresh) 'refresh': true,
          })
          .timeout(const Duration(seconds: 25));
      if (_disposed) return;
      final incoming =
          (result is Map ? result['providers'] as List? : null)
              ?.whereType<Map>()
              .toList() ??
          <Map>[];
      if (provider == null) {
        _providers = incoming;
      } else {
        _providers = [
          ..._providers.where((entry) => entry['id'] != provider),
          ...incoming,
        ];
      }
      (_cache[state] ??= {})[desktopId] = [..._providers];
      _schedule();
    } catch (error) {
      _unsupported =
          error is LinkRemoteException &&
          (error.code == 'unknown' || error.code == 'unsupported');
      failed = !_unsupported;
      if (_unsupported) {
        _reset?.cancel();
        _providers = [];
        _cache[state]?.remove(desktopId);
      }
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
    if (!refresh && !_disposed && !_unsupported && !failed) {
      final now = DateTime.now();
      final stale = _providers
          .where((entry) => provider == null || entry['id'] == provider)
          .any((entry) {
            final current = accounts(entry['id'] as String)
                .where((account) => account['current'] == true)
                .firstOrNull;
            final at = current?['at'];
            return at is! num ||
                now.difference(
                      DateTime.fromMillisecondsSinceEpoch(at.toInt()),
                    ) >
                    const Duration(minutes: 5);
          });
      if ((_providers.isEmpty && provider != null) || stale) {
        await load(provider: provider, refresh: true);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _minute?.cancel();
    _reset?.cancel();
    state.removeListener(_changed);
    super.dispose();
  }
}

class QuotaPanel extends StatefulWidget {
  const QuotaPanel({
    super.key,
    required this.controller,
    required this.provider,
    required this.title,
  });
  final QuotaController controller;
  final String provider, title;
  @override
  State<QuotaPanel> createState() => _QuotaPanelState();
}

class _QuotaPanelState extends State<QuotaPanel> {
  bool get _open => widget.controller.isOpen(widget.provider);
  String tr(String zh, String en) => widget.controller.state.tr(zh, en);
  DateTime? _time(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal()
      : null;
  String _clock(DateTime value) => formatClock(value);
  String _reset(DateTime value) {
    final span = value.difference(DateTime.now());
    if (span.isNegative) return tr('即将重置', 'Resetting soon');
    if (span.inHours < 24) {
      return tr(
        '${span.inHours} 小时 ${span.inMinutes % 60} 分钟后重置',
        'Resets in ${span.inHours}h ${span.inMinutes % 60}m',
      );
    }
    return tr(
      '${value.month}/${value.day} ${_clock(value)} 重置',
      'Resets ${value.month}/${value.day} ${_clock(value)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accounts = widget.controller.accounts(widget.provider);
    if (accounts.isEmpty) {
      final meta = MobileTheme.metaStyleOf(context);
      // Name and note on one line: with no numbers under it, a second line
      // only pushed the models apart.
      return Row(
        children: [
          Flexible(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (widget.controller.unsupported) ...[
            const SizedBox(width: MobileSpace.sm),
            Flexible(
              child: Text(
                tr('此电脑不支持额度查询', 'This desktop does not support quota queries'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ),
          ],
          if (widget.controller.failed) ...[
            const SizedBox(width: MobileSpace.sm),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tr('额度查询失败', 'Quota query failed'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : () => widget.controller.load(refresh: true),
                    child: Text(tr('重试', 'Retry')),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }
    final current = accounts
        .where((account) => account['current'] == true)
        .firstOrNull;
    final windows = (current?['windows'] as List? ?? [])
        .whereType<Map>()
        .toList();
    var summary = windows
        .map(
          (window) =>
              '${window['minutes'] == 300 ? tr('5 小时', '5h') : tr('每周', 'Weekly')}${tr('剩', ' left ')} ${(window['leftPercent'] as num).round()}%',
        )
        .join(' · ');
    if (accounts.length > 1) {
      var name = '${current?['displayName'] ?? ''}'.split('@').first;
      if (name.length > 15) name = '${name.substring(0, 15)}…';
      final enabled = accounts
          .where((account) => account['enabled'] != false)
          .toList();
      final available = enabled
          .where(
            (account) =>
                _time(account['limitedUntil'])?.isAfter(DateTime.now()) != true,
          )
          .length;
      summary = '$name · $summary · 可用 $available/${enabled.length}';
    }

    final meta = MobileTheme.metaStyleOf(context);
    final ink = MobileTheme.metaStyleOf(context, color: colors.onSurface);
    final updated = accounts
        .map((account) => _time(account['at']))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => widget.controller.toggle(widget.provider),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: AnimatedRotation(
                              key: const ValueKey('quota-chevron'),
                              turns: _open ? 0.25 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: LucideIcon(
                                'chevron-right',
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Its own line: beside the title it lost the numbers.
                      if (summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MobileTheme.metaStyleOf(
                              context,
                              color: quotaColor(
                                context,
                                windows,
                                summary: true,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: tr('刷新额度', 'Refresh quota'),
              onPressed: widget.controller.busy
                  ? null
                  : () => widget.controller.load(
                      provider: widget.provider,
                      refresh: true,
                    ),
              icon: widget.controller.busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const LucideIcon('refresh-cw', size: 20),
            ),
          ],
        ),
        // Whole, in the sheet's own scroll: no box scrolling inside it.
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(MobileSizes.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, account) in accounts.indexed) ...[
                  if (index > 0)
                    Divider(height: 1, color: colors.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${account['displayName'] ?? account['id']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            if (account['plan'] case final String plan)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(plan, style: meta),
                              ),
                            if (account['current'] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  tr('当前对话', 'Current conversation'),
                                  style: MobileTheme.metaStyleOf(
                                    context,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (account['enabled'] == false)
                          Text(tr('已停用', 'Disabled'), style: meta),
                        if (_time(account['limitedUntil']) case final until?
                            when until.isAfter(DateTime.now()))
                          Text(
                            tr(
                              '${DateUtils.isSameDay(until, DateTime.now()) ? '' : '${until.month}/${until.day} '}${_clock(until)} 恢复',
                              'Available ${_clock(until)}',
                            ),
                            style: MobileTheme.metaStyleOf(
                              context,
                              color: colors.error,
                            ),
                          ),
                        for (final window
                            in (account['windows'] as List? ?? [])
                                .whereType<Map>()) ...[
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final left =
                                  ((window['leftPercent'] as num?)
                                              ?.toDouble() ??
                                          0)
                                      .clamp(0, 100);
                              final color = left <= 10
                                  ? colors.error
                                  : left <= 30
                                  ? MobileTheme.statusColorsOf(context).warning
                                  : MobileTheme.statusColorsOf(context).success;
                              return Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      window['minutes'] == 300
                                          ? tr('5 小时', '5 hours')
                                          : tr('每周', 'Weekly'),
                                      style: ink,
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        minHeight: 4,
                                        value: left / 100,
                                        color: color,
                                        backgroundColor:
                                            colors.surfaceContainerHighest,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 56,
                                    ),
                                    child: Text(
                                      tr(
                                        '剩余 ${left.round()}%',
                                        '${left.round()}% left',
                                      ),
                                      textAlign: TextAlign.end,
                                      style: MobileTheme.metaStyleOf(
                                        context,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (_time(window['resetsAt']) case final reset?)
                            Padding(
                              padding: const EdgeInsets.only(left: 48),
                              child: Text(_reset(reset), style: meta),
                            ),
                        ],
                        if (account['error'] case final String error)
                          Text(
                            error,
                            style: MobileTheme.metaStyleOf(
                              context,
                              color: colors.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (updated != null)
                  Text(
                    tr(
                      widget.controller.busy
                          ? '正在刷新…'
                          : widget.controller.failed
                          ? '刷新失败，显示的是 ${_clock(updated)} 的数据'
                          : '上次更新 ${DateUtils.isSameDay(updated, DateTime.now()) ? '' : '${updated.month}/${updated.day} '}${_clock(updated)}',
                      widget.controller.busy
                          ? 'Refreshing…'
                          : 'Last updated ${_clock(updated)}',
                    ),
                    style: meta,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

Color quotaColor(
  BuildContext context,
  List<Map> windows, {
  bool summary = false,
}) {
  final left = windows
      .map((window) => (window['leftPercent'] as num).toDouble())
      .fold<double>(100, (a, b) => a < b ? a : b);
  if (left <= 10) return Theme.of(context).colorScheme.error;
  if (left <= 30) {
    return MobileTheme.statusColorsOf(context).warning;
  }
  return summary
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : MobileTheme.statusColorsOf(context).success;
}
