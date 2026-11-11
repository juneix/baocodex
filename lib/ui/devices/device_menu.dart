import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../link/phone_link.dart' show DesktopLinkStatus;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/dropdown_panel.dart';
import 'devices_page.dart';
import '../user_message.dart';

/// 一台电脑连没连上，一个词说：在线、连接中…、离线、需要重新配对。
/// 哪里说到连接状态都用它，措辞只在这一处。
String linkStatusLabel(AppState state, DesktopLinkStatus status) =>
    switch (status) {
      DesktopLinkStatus.online => state.tr('在线', 'Online'),
      DesktopLinkStatus.connecting => state.tr('连接中…', 'Connecting…'),
      DesktopLinkStatus.offline => state.tr('离线', 'Offline'),
      DesktopLinkStatus.needsPairing => state.tr('需要重新配对', 'Pair again'),
    };

/// 「在线 · 局域网直连 · 12 毫秒」, 「连接中…」, 「离线 5 分钟 · 正在重连」.
String devicePathText(AppState state, String desktopId) {
  final status = state.linkStatus(desktopId);
  switch (status) {
    case DesktopLinkStatus.needsPairing:
    case DesktopLinkStatus.connecting:
      return linkStatusLabel(state, status);
    case DesktopLinkStatus.offline:
      final seen = state.lastSeenOf(desktopId);
      return [
        [
          linkStatusLabel(state, status),
          if (seen != null) agoText(seen, zh: state.tr('中', 'en') == '中'),
        ].join(' '),
        state.tr('正在重连', 'Reconnecting'),
      ].join(' · ');
    case DesktopLinkStatus.online:
      final path = state.pathOf(desktopId);
      final kind = switch (path.kind) {
        LinkPathKind.lan => state.tr('局域网直连', 'LAN'),
        LinkPathKind.direct => state.tr('直连', 'Direct'),
        LinkPathKind.relay => state.tr('经中继', 'Via relay'),
        LinkPathKind.none => null,
      };
      final rtt = path.rtt;
      return [
        linkStatusLabel(state, status),
        ?kind,
        if (kind != null && rtt != null)
          state.tr('${rtt.inMilliseconds} 毫秒', '${rtt.inMilliseconds} ms'),
      ].join(' · ');
  }
}

String agoText(DateTime since, {required bool zh}) {
  final gone = DateTime.now().difference(since);
  if (gone.inMinutes < 1) return zh ? '不到 1 分钟' : 'under a minute';
  if (gone.inHours < 1) {
    return zh ? '${gone.inMinutes} 分钟' : '${gone.inMinutes} min';
  }
  if (gone.inDays < 1) return zh ? '${gone.inHours} 小时' : '${gone.inHours} h';
  return zh ? '${gone.inDays} 天' : '${gone.inDays} d';
}

/// The dot or spinner before a desktop's status.
class DeviceStatusMark extends StatelessWidget {
  const DeviceStatusMark({super.key, required this.status, this.size = 8});
  final DesktopLinkStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => switch (status) {
    DesktopLinkStatus.connecting => ConnectingSpinner(
      size: size + 2,
      color: Theme.of(context).colorScheme.primary,
    ),
    DesktopLinkStatus.online => _Dot(
      color: MobileTheme.statusColorsOf(context).success,
      size: size,
    ),
    DesktopLinkStatus.offline => _Dot(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: size,
    ),
    DesktopLinkStatus.needsPairing => _Dot(
      color: Theme.of(context).colorScheme.error,
      size: size,
    ),
  };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 切换按钮的箭头：别的电脑上有等着用户的对话时挂个红点，不用点开面板才知道。
/// 正看着的那台不算，它的数在底部对话标签上。
class _SwitcherChevron extends StatelessWidget {
  const _SwitcherChevron({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedDesktopId;
    final othersWaiting = state.desktops.any(
      (desktop) =>
          desktop.id != selected && state.awaitingOn(desktop.id).waiting > 0,
    );
    return Badge(
      key: const ValueKey('desktop-switcher-dot'),
      isLabelVisible: othersWaiting,
      smallSize: 7,
      child: LucideIcon(
        'chevron-down',
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 对话、Bot 与文件页的电脑标题；点按打开底部设备选择面板。
class DesktopSwitcherTitle extends StatelessWidget {
  const DesktopSwitcherTitle({super.key, required this.state, this.onChanged});
  final AppState state;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktopId = state.selectedDesktopId;
    final name = state.desktops
        .where((desktop) => desktop.id == desktopId)
        .firstOrNull
        ?.name;
    final status = desktopId == null ? null : state.linkStatus(desktopId);
    return Semantics(
      button: true,
      child: Tooltip(
        message: state.tr('切换电脑', 'Switch desktop'),
        child: InkWell(
          borderRadius: BorderRadius.circular(MobileSpace.sm),
          onTap: () async {
            final chosen = await showDeviceMenu(
              context,
              state,
              selectedId: desktopId,
            );
            if (chosen == null || chosen == desktopId) return;
            state.selectDesktop(chosen);
            onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileSpace.sm,
              vertical: MobileSpace.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name ?? state.tr('选择电脑', 'Choose desktop'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MobileType.title,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: MobileSpace.xs),
                    _SwitcherChevron(state: state),
                  ],
                ),
                if (desktopId != null && status != null)
                  Row(
                    key: ValueKey('desktop-status-$desktopId'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DeviceStatusMark(status: status, size: 6),
                      const SizedBox(width: MobileSpace.xs),
                      Flexible(
                        child: Text(
                          devicePathText(state, desktopId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: MobileType.caption,
                            fontWeight: FontWeight.normal,
                            color: status == DesktopLinkStatus.needsPairing
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A desktop's outline screen with its status dot at the lower right. A
/// laptop (as the desktop says of itself) shows as one.
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({super.key, this.status, this.color, this.laptop});
  final DesktopLinkStatus? status;
  final Color? color;

  /// Whether the desktop says it is a laptop; null before it says.
  final bool? laptop;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    return SizedBox.square(
      dimension: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          LucideIcon(
            laptop == true ? 'laptop' : 'monitor',
            size: 22,
            color: color,
          ),
          if (status != null)
            Positioned(
              right: -2,
              bottom: -1,
              child: DeviceStatusMark(status: status, size: 8),
            ),
        ],
      ),
    );
  }
}

/// A page's action for the desktop it shows: the screen and its status dot,
/// opening the same device sheet as [DesktopSwitcherTitle].
class DesktopSwitcherButton extends StatelessWidget {
  const DesktopSwitcherButton({super.key, required this.state, this.onChanged});
  final AppState state;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktopId = state.selectedDesktopId;
    final status = desktopId == null ? null : state.linkStatus(desktopId);
    return Padding(
      padding: const EdgeInsets.only(right: MobileSpace.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MobileSizes.radius),
        child: InkWell(
          key: const ValueKey('desktop-switcher-button'),
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          onTap: () async {
            final chosen = await showDeviceMenu(
              context,
              state,
              selectedId: desktopId,
            );
            if (chosen == null || chosen == desktopId) return;
            state.selectDesktop(chosen);
            onChanged?.call();
          },
          child: Tooltip(
            message: state.tr('切换电脑', 'Switch desktop'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileSpace.sm,
                vertical: MobileSpace.xs + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DeviceIcon(
                    status: status,
                    laptop: state.desktops
                        .where((desktop) => desktop.id == desktopId)
                        .firstOrNull
                        ?.laptop,
                  ),
                  const SizedBox(width: MobileSpace.xs),
                  _SwitcherChevron(state: state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 贴着按钮弹出的设备面板：显示连接状态、附近电脑与配对入口，返回选中电脑的 id。
Future<String?> showDeviceMenu(
  BuildContext anchor,
  AppState state, {
  String? selectedId,
}) => showDropdownPanel<String>(
  anchor,
  width: 340,
  builder: (menuContext) =>
      _DeviceSheet(state: state, selectedId: selectedId, pageContext: anchor),
);

class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet({
    required this.state,
    required this.selectedId,
    required this.pageContext,
  });
  final AppState state;
  final String? selectedId;
  final BuildContext pageContext;

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  AppState get state => widget.state;
  Timer? _tick;
  bool _detecting = false;

  /// The user checked again since the sheet opened: say what it found.
  bool _checked = false;
  String? _discoveryError;
  final _reconnecting = <String>{};
  final _connectionErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_detect());
    // 只更新时间；连接层负责自动重连，不因面板刷新反复打断连接。
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _detect({bool manual = false}) async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _discoveryError = null;
    });
    final started = DateTime.now();
    try {
      if (!state.demo) {
        // Asked for: the paired desktops that dropped are dialled again too
        // (those online are left alone), and the LAN is browsed afresh.
        await Future.wait([
          state.discovery.refresh(),
          if (manual)
            for (final desktop in state.desktops)
              if (state.linkStatus(desktop.id) == DesktopLinkStatus.offline)
                _reconnect(desktop.id),
        ]);
      }
      // The desktops nearby answer over the next moment, not with the
      // refresh: the check shows long enough to be seen, and to hear them.
      if (manual) {
        final rest = _checkAtLeast - DateTime.now().difference(started);
        if (rest > Duration.zero) await Future<void>.delayed(rest);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _discoveryError = state.tr(
            '局域网发现不可用，请检查系统权限和网络后重试。',
            'Discovery is unavailable. Check permissions and the network, then retry.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _detecting = false;
          if (manual) _checked = true;
        });
      }
    }
  }

  static const _checkAtLeast = Duration(milliseconds: 1500);

  Future<void> _reconnect(String desktopId) async {
    if (_reconnecting.contains(desktopId) ||
        state.linkStatus(desktopId) != DesktopLinkStatus.offline) {
      return;
    }
    setState(() {
      _reconnecting.add(desktopId);
      _connectionErrors.remove(desktopId);
    });
    try {
      if (!state.demo) {
        await state.link.reconnect(desktopId, reportFailure: true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _connectionErrors[desktopId] = userMessage(state, error),
        );
      }
    } finally {
      if (mounted) setState(() => _reconnecting.remove(desktopId));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _open(Widget page) {
    Navigator.pop(context);
    if (widget.pageContext.mounted) {
      openPage<void>(widget.pageContext, page);
    }
  }

  /// 这台电脑上等着用户的（见 [AppState.awaitingOn]）。正看着的那台不标：
  /// 它的红点在底部对话标签上，不在这里重复。
  ({int waiting, int needsInput}) _waitingOn(String desktopId) =>
      desktopId == widget.selectedId
      ? (waiting: 0, needsInput: 0)
      : state.awaitingOn(desktopId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([state, state.discovery]),
      builder: (context, _) {
        final desktops = state.desktops;
        final paired = {for (final desktop in desktops) desktop.id};
        final nearby = [
          for (final advert in state.discovery.desktops)
            if (!paired.contains(advert.id)) advert,
        ];
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final desktop in desktops) ...[
                _DeviceRow(
                  key: ValueKey('device-${desktop.id}'),
                  name: desktop.name,
                  laptop: desktop.laptop,
                  detail: devicePathText(state, desktop.id),
                  status: state.linkStatus(desktop.id),
                  // 这台电脑做完没看的对话：在列表里看不到它们，标在这里。
                  waiting: _waitingOn(desktop.id),
                  selected: desktop.id == widget.selectedId,
                  onTap: () => Navigator.pop(context, desktop.id),
                  action: switch (state.linkStatus(desktop.id)) {
                    DesktopLinkStatus.offline => TextButton(
                      onPressed: _reconnecting.contains(desktop.id)
                          ? null
                          : () => _reconnect(desktop.id),
                      child: Text(
                        _reconnecting.contains(desktop.id)
                            ? state.tr('重连中…', 'Reconnecting…')
                            : state.tr('重连', 'Reconnect'),
                      ),
                    ),
                    DesktopLinkStatus.needsPairing => TextButton(
                      onPressed: () => _open(PairDevicePage(state: state)),
                      child: Text(state.tr('重新配对', 'Pair again')),
                    ),
                    _ => null,
                  },
                ),
                if (_connectionErrors[desktop.id] case final error?)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MobileSpace.lg,
                      vertical: MobileSpace.xs,
                    ),
                    child: Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
              if (nearby.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MobileSpace.lg,
                    MobileSpace.sm,
                    MobileSpace.lg,
                    0,
                  ),
                  child: Text(
                    state.tr('附近的电脑', 'Nearby desktops'),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                for (final advert in nearby)
                  _DeviceRow(
                    name: advert.name,
                    detail: state.tr('未配对 · 点按配对', 'Not paired · tap to pair'),
                    onTap: () => _open(PairDevicePage(state: state)),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileSpace.lg,
                  vertical: MobileSpace.sm,
                ),
                child: Column(
                  children: [
                    // One line: the hint gives way (wraps) before the button does.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (nearby.isEmpty)
                          Flexible(
                            child: Text(
                              _checked && !_detecting
                                  ? state.tr(
                                      '已检测，未发现其他电脑',
                                      'Checked: no other desktops found',
                                    )
                                  : state.tr(
                                      '暂未发现其他电脑',
                                      'No other desktops found',
                                    ),
                              // As large as the button beside it.
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(width: MobileSpace.xs),
                        TextButton(
                          style: TextButton.styleFrom(
                            textStyle: theme.textTheme.labelMedium,
                          ),
                          onPressed: _detecting
                              ? null
                              : () => _detect(manual: true),
                          child: Text(
                            _detecting
                                ? state.tr('检测中…', 'Scanning…')
                                : state.tr('重新检测', 'Scan again'),
                          ),
                        ),
                      ],
                    ),
                    if (_discoveryError case final error?)
                      Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileSpace.lg,
                  vertical: MobileSpace.sm,
                ),
                child: OutlinedButton.icon(
                  style: MobileSizes.wideButton,
                  onPressed: () => _open(PairDevicePage(state: state)),
                  icon: const LucideIcon('qr-code', size: 20),
                  label: Text(state.tr('配对新电脑', 'Pair a desktop')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: MobileSpace.xs,
                  bottom: MobileSpace.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LucideIcon('lock', size: 12, color: theme.hintColor),
                    const SizedBox(width: MobileSpace.xs),
                    Text(
                      state.tr('端到端加密', 'End-to-end encrypted'),
                      style: TextStyle(
                        fontSize: MobileType.caption,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 设备行展示连接状态、当前选中态，以及不切换设备的重连操作。
class _DeviceRow extends StatelessWidget {
  static const _icon = 40.0;

  const _DeviceRow({
    super.key,
    required this.name,
    required this.detail,
    this.status,
    this.laptop,
    this.selected = false,
    this.waiting = (waiting: 0, needsInput: 0),
    required this.onTap,
    this.action,
  });
  final String name;
  final String detail;
  final bool? laptop;
  final DesktopLinkStatus? status;
  final bool selected;

  /// 别的电脑上等着你看的：一共几个，其中几个卡在等你批准或回答。
  final ({int waiting, int needsInput}) waiting;
  final VoidCallback onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = this.status;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileSpace.md,
        vertical: MobileSpace.xs,
      ),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MobileSpace.lg,
                        vertical: MobileSpace.sm,
                      ),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: _icon,
                            child: Center(
                              child: DeviceIcon(
                                status: status,
                                laptop: laptop,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: MobileSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium!.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: MobileSpace.xs),
                                Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall!.copyWith(
                                    color:
                                        status == DesktopLinkStatus.needsPairing
                                        ? theme.colorScheme.error
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (waiting.waiting > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: MobileSpace.xs,
                              ),
                              // 一个点，和标题旁那个一样：不数几条，只说要你看。
                              child: Badge(
                                key: ValueKey('device-badge-$name'),
                                smallSize: 7,
                                backgroundColor: theme.colorScheme.error,
                              ),
                            ),
                          if (selected)
                            LucideIcon(
                              'check',
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(right: MobileSpace.sm),
                  child: action!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
