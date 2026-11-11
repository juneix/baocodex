import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../link/phone_link.dart';
import '../../link/desktop_address.dart';
import '../../link/link_errors.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import 'device_menu.dart';
import 'qr_scan_view.dart';
import '../../models/user_facing_error.dart';
import '../widgets/formats.dart';
import '../widgets/fold_row.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(state.tr('已配对的电脑', 'Paired desktops'))),
      body: state.desktops.isEmpty
          ? EmptyPanel(
              state.tr('还没有配对的电脑', 'No paired desktops'),
              icon: Icons.computer_outlined,
              actionLabel: state.tr('配对新电脑', 'Pair a desktop'),
              onAction: () =>
                  openPage<void>(context, PairDevicePage(state: state)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GroupCard(
                  children: [
                    for (final desktop in [
                      ...state.desktops.where((d) => state.isOnline(d.id)),
                      ...state.desktops.where((d) => !state.isOnline(d.id)),
                    ])
                      ListTile(
                        leading: SizedBox(
                          width: 28,
                          height: 28,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              const LucideIcon('monitor', size: 24),
                              Positioned(
                                right: -3,
                                bottom: -3,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: DeviceStatusMark(
                                      status: state.linkStatus(desktop.id),
                                      size: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: Text(
                          desktop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          devicePathText(state, desktop.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: LucideIcon(
                          'chevron-right',
                          size: 18,
                          color: Theme.of(context).hintColor,
                        ),
                        onTap: () => openPage<void>(
                          context,
                          DevicePage(state: state, desktopId: desktop.id),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    state.tr(
                      '手机与每台电脑之间各有一条独立的端到端加密通道。',
                      'Each desktop has its own end-to-end encrypted channel to this phone.',
                    ),
                    style: MobileTheme.hintStyleOf(context),
                  ),
                ),
                GroupCard(
                  children: [
                    ListTile(
                      leading: LucideIcon(
                        'qr-code',
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(state.tr('配对新电脑', 'Pair a desktop')),
                      trailing: LucideIcon(
                        'chevron-right',
                        size: 18,
                        color: Theme.of(context).hintColor,
                      ),
                      onTap: () =>
                          openPage<void>(context, PairDevicePage(state: state)),
                    ),
                  ],
                ),
              ],
            ),
    ),
  );
}

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.state, required this.desktopId});
  final AppState state;
  final String desktopId;
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  AppState get state => widget.state;
  String get desktopId => widget.desktopId;
  bool _checking = false;
  String? _checkResult;

  /// 测一测当前这条连接；结果写在同一行的说明里，成功失败都是。
  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _checkResult = null;
    });
    String result;
    try {
      await state.link.checkConnection(desktopId);
      result = state.tr(
        '已通过电脑身份认证，当前连接可用；不代表每个保存地址均可达。',
        'The authenticated connection works; this does not test every saved address.',
      );
    } on Object catch (error) {
      result = connectionCheckErrorMessage(error, state.tr);
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkResult = result;
    });
  }

  List<int> _ports(KeptDesktop desktop) {
    final ports = <int>{};
    for (final address in desktop.addresses) {
      try {
        ports.add(DesktopAddress.parse(address).port);
      } on UserFacingError {
        // 旧记录中的无效地址不能被展示成有效监听端口。
      }
    }
    return ports.toList();
  }

  /// 「11月4日」这样：配对那天，旧记录没有就是 null。
  String? _pairedOn(KeptDesktop desktop) {
    final at = desktop.pairedAt;
    if (at == null) return null;
    return formatDay(state, at);
  }

  /// 「离线 · 2 天前在线」：头像下面那行，跟设备列表里同一套说法。
  String _presence(KeptDesktop desktop) {
    if (desktop.needsPairing) {
      return linkStatusLabel(state, DesktopLinkStatus.needsPairing);
    }
    if (state.isOnline(desktop.id)) return devicePathText(state, desktop.id);
    return switch (state.lastSeenOf(desktop.id)) {
      null => state.tr('未连接过', 'Never connected'),
      final seen => state.tr(
        '离线 · ${agoText(seen, zh: true)}前在线',
        'Offline · last seen ${agoText(seen, zh: false)} ago',
      ),
    };
  }

  /// 「在线」「离线」「需要重新配对」：连接方式那一行的值。
  String _linkState(KeptDesktop desktop) => linkStatusLabel(
    state,
    desktop.needsPairing
        ? DesktopLinkStatus.needsPairing
        : state.isOnline(desktop.id)
        ? DesktopLinkStatus.online
        : DesktopLinkStatus.offline,
  );

  /// 中继那几行怎么说：只走直连、电脑公布了（空的也算）、还用着旧版提示、
  /// 什么都没收到。返回值和说明一一对应。
  String _relayValue(KeptDesktop desktop) =>
      desktop.direct || desktop.relaysPublished
      ? state.tr('跟随电脑', 'Follows desktop')
      : state.tr('等待电脑公布', 'Awaiting desktop');

  String _relayDetail(KeptDesktop desktop) {
    if (desktop.direct) return state.tr('仅直连，不使用中继', 'Direct only, no relays');
    if (desktop.relaysPublished) {
      return desktop.relays.isEmpty
          ? state.tr('电脑未提供中继', 'The desktop provides no relays')
          : desktop.relays.join('\n');
    }
    if (desktop.relays.isNotEmpty) {
      return '${state.tr('尚未收到电脑的中继策略，暂用旧版保存的提示：', 'No relay policy from the desktop yet; using a hint saved by an older version:')}\n${desktop.relays.join('\n')}';
    }
    return state.tr(
      '尚未收到电脑的中继策略，暂用内置中继',
      'No relay policy from the desktop yet; using built-in relays',
    );
  }

  /// 改这台电脑在手机上叫什么。空名不收，跟没改一样。
  Future<void> _rename(KeptDesktop desktop) async {
    final name = await askText(
      context,
      state,
      state.tr('名称', 'Name'),
      value: desktop.name,
      hint: state.tr('这台电脑在手机上叫什么', 'What this desktop is called here'),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await state.link.renameDesktop(desktop.id, name);
  }

  /// 顶上那块：电脑图标、状态一行。点图标下的状态不做事，只是让人一眼知道
  /// 这台在不在线。
  Widget _heading(BuildContext context, KeptDesktop desktop) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox.square(
          dimension: 56,
          child: Center(
            child: DeviceIcon(
              status: state.linkStatus(desktop.id),
              laptop: desktop.laptop,
              color: colors.onSurface,
            ),
          ),
        ),
        const SizedBox(height: MobileSpace.sm),
        Text(
          _presence(desktop),
          key: const ValueKey('device-presence'),
          textAlign: TextAlign.center,
          style: MobileTheme.hintStyleOf(context),
        ),
      ],
    );
  }

  /// 这台电脑上手机知道的项目：地址下面那一块，只是让人认得出机器。
  List<ProjectRef> _projects(KeptDesktop desktop) => [
    for (final project in state.projects)
      if (project.desktopId == desktop.id) project,
  ];

  /// 名称、系统、配对时间：都不是连接状态，是这台机器本身。
  Widget _identityCard(BuildContext context, KeptDesktop desktop) => GroupCard(
    children: [
      SettingsRow(
        state.tr('名称', 'Name'),
        value: desktop.name,
        // 只在手机上改：电脑那边不知道，重连也不会被它的名字盖回。
        onTap: () => runUi(context, () => _rename(desktop)),
      ),
      // 电脑自己报的系统，连上过才有；它不随改名变。
      if (desktop.system case final system? when system.isNotEmpty)
        SettingsRow(state.tr('系统', 'System'), value: system),
      if (_pairedOn(desktop) case final paired?)
        SettingsRow(state.tr('配对时间', 'Paired'), value: paired),
    ],
  );

  /// 指纹：让人拿它和电脑上显示的那串对一遍，不一样就是中间有人。
  Widget _encryptionCard(BuildContext context, KeptDesktop desktop) {
    final groups = state.demo
        ? const ['DEMO']
        : fingerprintOf(decodeKey(desktop.publicKey)).split(' ');
    return GroupCard(
      children: [
        Padding(
          key: const ValueKey('device-fingerprint'),
          padding: const EdgeInsets.fromLTRB(
            MobileSpace.lg,
            MobileSpace.lg,
            MobileSpace.lg,
            MobileSpace.md,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LucideIcon('lock', size: 14),
                  const SizedBox(width: MobileSpace.xs),
                  Text(
                    state.tr('端到端加密', 'End-to-end encrypted'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              for (var row = 0; row < groups.length; row += 4)
                SelectableText(
                  groups.skip(row).take(4).join('  '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: MobileType.body,
                    height: 1.6,
                    letterSpacing: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileSpace.lg,
            0,
            MobileSpace.lg,
            MobileSpace.lg,
          ),
          child: Text(
            state.tr(
              '与电脑上「设置 → 移动设备」中显示的指纹核对，不一致请立即取消配对。',
              'Check this against the fingerprint under Settings → Mobile devices on the desktop. Unpair if they differ.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 这台电脑上手机知道的项目；一个都没有时整块不出。
  List<Widget> _projectsCard(BuildContext context, KeptDesktop desktop) {
    final projects = _projects(desktop);
    if (projects.isEmpty) return const [];
    return [
      SectionLabel(state.tr('项目', 'Projects'), inset: 4),
      GroupCard(
        children: [
          for (final project in projects)
            ListTile(
              leading: const LucideIcon('folder', size: 22),
              title: Text(project.project.name),
              subtitle: Text(
                [
                  project.project.path,
                  if (project.project.branch case final branch?
                      when branch.isNotEmpty)
                    branch,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ];
  }

  Widget _unpairButton(BuildContext context, KeptDesktop desktop) =>
      OutlinedButton.icon(
        icon: const LucideIcon('unlink', size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          minimumSize: const Size.fromHeight(MobileSizes.control),
        ),
        label: Text(state.tr('取消配对', 'Unpair')),
        onPressed: state.demo
            ? null
            : () => runUi(context, () async {
                if (!await confirmAction(
                  context,
                  state,
                  state.tr('取消配对？', 'Unpair desktop?'),
                  state.tr(
                    '将移除本机信任记录。电脑离线时，仍需在电脑端移除手机授权。',
                    'Remove trust on this phone. If offline, also revoke the phone on the desktop.',
                  ),
                  action: state.tr('取消配对', 'Unpair'),
                  destructive: true,
                )) {
                  return;
                }
                await state.link.forget(desktop.id);
                if (context.mounted) Navigator.pop(context);
              }),
      );

  /// 连接：一条状态，下面能重新连、测一测；中继和端口归在说明里。
  Widget _connectionCard(BuildContext context, KeptDesktop desktop) {
    final ports = _ports(desktop);
    return GroupCard(
      children: [
        SettingsRow(state.tr('连接方式', 'Connection'), value: _linkState(desktop)),
        SettingsRow(
          state.tr('电脑的中继', 'Desktop relays'),
          // 只走直连也留着这一行：没中继是它说的话，不是缺了一项。
          value: _relayValue(desktop),
          subtitle: _relayDetail(desktop),
        ),
        SettingsRow(
          state.tr('连接端口（UDP）', 'Connection ports (UDP)'),
          value: ports.isEmpty
              ? state.tr('尚无地址', 'No addresses')
              : ports.join(', '),
          subtitle: state.tr(
            '来自保存的连接地址，监听端口仍在电脑端设置。',
            'From saved addresses. Configure the listening port on the desktop.',
          ),
        ),
        SettingsRow(
          desktop.needsPairing
              ? state.tr('重新配对', 'Pair again')
              : state.tr('重新连接', 'Reconnect'),
          icon: 'refresh-cw',
          onTap: state.demo
              ? null
              : desktop.needsPairing
              ? () => openPage<void>(context, PairDevicePage(state: state))
              : () => runUi(context, () => state.link.reconnect(desktop.id)),
        ),
        SettingsRow(
          state.tr('测试连接', 'Test connection'),
          icon: 'shield-check',
          value: _checking ? state.tr('检查中…', 'Checking…') : null,
          subtitle:
              _checkResult ??
              state.tr(
                '在线时检查当前认证连接；测试新地址请先重新连接。',
                'Checks the current connection when online. Reconnect first to test new addresses.',
              ),
          onTap: state.demo || desktop.needsPairing || _checking
              ? null
              : _check,
        ),
      ],
    );
  }

  /// 电脑的地址：一条一行，标着局域网还是公网，点一下复制。
  Widget _addressesCard(BuildContext context, KeptDesktop desktop) {
    final theme = Theme.of(context);
    return GroupCard(
      children: [
        if (desktop.addresses.isEmpty)
          ListTile(
            title: Text(state.tr('尚无地址', 'No addresses')),
            subtitle: Text(
              state.tr(
                '连上电脑后会自动记下它说过的地址。',
                'Addresses the desktop reports are saved once it connects.',
              ),
            ),
          ),
        for (final address in desktop.addresses)
          ListTile(
            key: ValueKey('device-address-$address'),
            title: SelectableText(
              address,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            subtitle: Text(
              isLanAddress(address)
                  ? state.tr('局域网', 'LAN')
                  : state.tr('公网', 'Public'),
            ),
            trailing: IconButton(
              tooltip: state.tr('复制地址', 'Copy address'),
              icon: const LucideIcon('copy', size: 18),
              onPressed: () => _copyAddress(context, address),
            ),
          ),
        ListTile(
          leading: const LucideIcon('plus', size: 20),
          title: Text(state.tr('添加地址', 'Add an address')),
          subtitle: Text(
            state.tr(
              '电脑在路由器后面用端口转发，或者用动态域名时，在这里填「域名或 IP:端口」。',
              'Behind a router with port forwarding, or on a dynamic DNS name: enter “host or IP:port” here.',
            ),
          ),
          onTap: state.demo
              ? null
              : () => runUi(context, () => _editAddresses(desktop)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileSpace.lg,
            MobileSpace.sm,
            MobileSpace.lg,
            MobileSpace.lg,
          ),
          child: Text(
            state.tr(
              '电脑上次连上时告诉手机这些地址；中继和端口在电脑的「设置 → 手机 → 中继」里改。',
              'These are the addresses the desktop last reported. Its relays and ports are set under Settings → Phone → Relays on the desktop.',
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _copyAddress(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(state.tr('已复制', 'Copied'))));
  }

  /// 改保存的连接地址，一次一行（或逗号隔开）。
  Future<void> _editAddresses(KeptDesktop desktop) async {
    final text = await askText(
      context,
      state,
      state.tr('电脑的地址', 'Desktop addresses'),
      value: desktop.addresses.join('\n'),
      lines: 4,
      hint: 'desk.example.com:47100\n192.168.1.20:47100\n[::1]:47100',
    );
    if (text == null || !mounted) return;
    final addresses = text
        .split(RegExp(r'[\n,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await state.link.updateAddresses(desktop.id, addresses);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final desktop = state.desktops
          .where((desktop) => desktop.id == desktopId)
          .firstOrNull;
      if (desktop == null) {
        return Scaffold(
          appBar: AppBar(),
          body: EmptyPanel(state.tr('设备已移除', 'Device removed')),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(desktop.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _heading(context, desktop),
            const SizedBox(height: 16),
            _identityCard(context, desktop),
            SectionLabel(state.tr('端到端加密', 'End-to-end encryption'), inset: 4),
            _encryptionCard(context, desktop),
            SectionLabel(state.tr('连接', 'Connection'), inset: 4),
            _connectionCard(context, desktop),
            if (desktop.needsPairing)
              CardNote(
                state.tr(
                  '连接协议已升级，旧授权不能继续使用。请更新电脑并重新扫码；确认新连接后可手动移除旧记录。',
                  'The link protocol changed. Update the desktop and pair again. Remove the old record manually after checking the new connection.',
                ),
              ),
            if (state.link.hasUnsavedAddress(desktop.id))
              CardNote(
                state.tr(
                  '连接已建立，但新的连接地址或中继策略未能保存。重启后可能需要重新发现电脑或重新获取中继策略。',
                  'Connected, but the new connection addresses or relay policy could not be saved. Rediscovery or a fresh relay policy may be needed after restarting.',
                ),
              ),
            SectionLabel(state.tr('电脑的地址', 'Desktop addresses'), inset: 4),
            _addressesCard(context, desktop),
            ..._projectsCard(context, desktop),
            const SizedBox(height: 24),
            _unpairButton(context, desktop),
          ],
        ),
      );
    },
  );
}

class PairDevicePage extends StatefulWidget {
  const PairDevicePage({super.key, required this.state});
  final AppState state;
  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  final _code = TextEditingController();
  // Null in demo mode: no camera is opened there.
  late final MobileScannerController? _scanner = widget.state.demo
      ? null
      : createPairingScannerController();
  bool _working = false;
  bool _paste = false;
  bool _foreign = false;
  PairingAttempt? _attempt;
  Timer? _rediscover;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.state.demo) return;
    void refresh() =>
        unawaited(widget.state.discovery.refresh().catchError((Object _) {}));
    refresh();
    _rediscover = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    _rediscover?.cancel();
    _code.dispose();
    final scanner = _scanner;
    if (scanner != null) unawaited(scanner.dispose().catchError((Object _) {}));
    final attempt = _attempt;
    if (attempt != null) {
      unawaited(
        widget.state.link.cancelPairing(attempt).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  void _pauseCamera() {
    final scanner = _scanner;
    if (scanner != null) unawaited(scanner.stop().catchError((Object _) {}));
  }

  void _resumeCamera() {
    final scanner = _scanner;
    if (scanner != null && !_paste) {
      unawaited(scanner.start().catchError((Object _) {}));
    }
  }

  void _togglePaste() {
    setState(() {
      _paste = !_paste;
      _error = null;
      _foreign = false;
    });
    if (_paste) {
      _pauseCamera();
    } else {
      _resumeCamera();
    }
  }

  void _detect(BarcodeCapture capture) {
    if (_working || _paste) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      if (value.startsWith('baocode://')) {
        _code.text = value;
        unawaited(_pair(() => widget.state.link.pair(value)));
        return;
      }
      if (!_foreign) setState(() => _foreign = true);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _pair(Future<PairingAttempt> Function() begin) async {
    if (_working) return;
    setState(() {
      _working = true;
      _foreign = false;
      _error = null;
    });
    _pauseCamera();
    try {
      final attempt = await begin();
      if (!mounted) {
        await widget.state.link.cancelPairing(attempt);
        return;
      }
      _attempt = attempt;
      final success = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SafetyDialog(state: widget.state, attempt: attempt),
      );
      if (success != true) await widget.state.link.cancelPairing(attempt);
      _attempt = null;
      if (success == true && mounted) {
        // Paired: now the app has something to notify of.
        unawaited(widget.state.askNotificationsOnce());
        Navigator.pop(context);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = pairingErrorMessage(error, widget.state.tr));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _resumeCamera();
      }
    }
  }

  Widget _viewfinder(BuildContext context) {
    final scanner = _scanner;
    final bracket = MobileTheme.statusColorsOf(context).success;
    final square = Center(
      child: ConstrainedBox(
        key: const ValueKey('pair-viewfinder'),
        constraints: const BoxConstraints(maxWidth: 240),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: scanner == null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      const ScanPlaceholder(),
                      CustomPaint(painter: ScanBracketsPainter(color: bracket)),
                    ],
                  )
                : QrScanView(
                    controller: scanner,
                    onDetect: _detect,
                    tr: widget.state.tr,
                    bracketColor: bracket,
                    foreign: _foreign,
                  ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        square,
        const SizedBox(height: MobileSpace.md),
        Text(
          widget.state.tr(
            '让二维码填满方框；识别不到时离远一点，或双指放大',
            'Fill the frame with the code. If it is not read, step back a little or pinch to zoom.',
          ),
          textAlign: TextAlign.center,
          style: MobileTheme.hintStyleOf(context),
        ),
      ],
    );
  }

  Widget _step(BuildContext context, int number, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: MobileSpace.xs + 2),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: MobileType.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: MobileSpace.md),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: MobileType.secondary),
          ),
        ),
      ],
    ),
  );

  Widget _nearbyRow(BuildContext context, LinkAdvert advert) {
    final state = widget.state;
    final theme = Theme.of(context);
    final paired = state.desktops.any(
      (desktop) => desktop.id == advert.id && !desktop.needsPairing,
    );
    final ready = !paired && advert.pairing;
    final notReady = state.tr(
      '在电脑上点「显示二维码」后可配对',
      'Tap Show QR code on the desktop to pair',
    );
    // The advert's pairing flag is a hint that can lag behind: the desktop
    // itself refuses when its pairing is closed.
    return ListTile(
      leading: LucideIcon(
        'monitor',
        size: 24,
        color: ready ? theme.colorScheme.primary : theme.hintColor,
      ),
      title: Text(advert.name),
      subtitle: Text(
        paired
            ? state.tr('已配对', 'Paired')
            : advert.pairing
            ? state.tr('可以配对', 'Ready to pair')
            : notReady,
      ),
      trailing: LucideIcon('chevron-right', size: 18, color: theme.hintColor),
      onTap: _working
          ? null
          : paired
          ? () => _toast(state.tr('这台电脑已配对', 'Already paired'))
          : advert.pairing
          ? () => _pair(() => state.link.pairNearby(advert))
          : () => _toast(notReady),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('配对新电脑', 'Pair a desktop'))),
      body: AnimatedBuilder(
        animation: state.discovery,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(MobileSpace.lg),
          children: [
            if (!_paste) ...[
              _viewfinder(context),
              const SizedBox(height: MobileSpace.xl),
            ],
            _step(
              context,
              1,
              state.tr('在电脑上打开 BaoCode', 'Open BaoCode on the desktop'),
            ),
            _step(
              context,
              2,
              state.tr(
                '进入 设置 → 手机，点击「显示二维码」',
                'Go to Settings → Phone and tap Show QR code',
              ),
            ),
            _step(
              context,
              3,
              state.tr('用手机扫描电脑上显示的二维码', 'Scan the code shown on the desktop'),
            ),
            const SizedBox(height: MobileSpace.lg),
            OutlinedButton(
              style: MobileSizes.wideButton,
              onPressed: _working ? null : _togglePaste,
              child: Text(
                _paste
                    ? state.tr('改为扫描二维码', 'Scan instead')
                    : state.tr('改为粘贴配对链接', 'Paste a pairing link instead'),
              ),
            ),
            if (_paste) ...[
              const SizedBox(height: MobileSpace.lg),
              ValueListenableBuilder(
                valueListenable: _code,
                builder: (context, value, _) => TextField(
                  controller: _code,
                  maxLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: state.tr('粘贴配对链接', 'Paste pairing link'),
                    hintText: 'baocode://pair?...',
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: state.tr('清空', 'Clear'),
                            icon: const LucideIcon('x', size: 18),
                            onPressed: () => setState(() {
                              _code.clear();
                              _error = null;
                            }),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: MobileSpace.md),
              FilledButton(
                style: MobileSizes.wideButton,
                onPressed: _working || state.demo
                    ? null
                    : () => _pair(() => state.link.pair(_code.text)),
                child: Text(
                  state.tr('连接并核对安全码', 'Connect and compare safety codes'),
                ),
              ),
            ],
            if (_working)
              const Padding(
                padding: EdgeInsets.all(MobileSpace.lg),
                child: ThinProgress(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MobileSpace.md),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            SectionLabel(state.tr('附近的电脑', 'Nearby desktops'), inset: 0),
            if (state.discovery.error != null)
              Text(
                state.tr(
                  '局域网发现不可用。你仍可扫码或粘贴链接。',
                  'Discovery is unavailable. You can still scan or paste a pairing link.',
                ),
              ),
            if (state.discovery.desktops.isEmpty)
              Text(
                state.tr(
                  '电脑需在同一网络，并保持配对窗口打开。',
                  'Keep the desktop pairing window open on the same network.',
                ),
                style: theme.textTheme.bodySmall,
              )
            else
              GroupCard(
                children: [
                  for (final advert in state.discovery.desktops)
                    _nearbyRow(context, advert),
                ],
              ),
            const SizedBox(height: MobileSpace.xl),
            ClipRRect(
              borderRadius: BorderRadius.circular(MobileSizes.radius),
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.all(MobileSpace.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LucideIcon('lock', size: 18, color: theme.hintColor),
                      const SizedBox(width: MobileSpace.md),
                      Expanded(
                        child: Text(
                          state.tr(
                            '二维码里有电脑的公钥和地址。手机经局域网或公网直接连接电脑，两端之间的所有内容都用只保存在两端的密钥加密。',
                            "The code holds the desktop's public key and addresses. The phone connects to the desktop directly over the LAN or internet, and everything between them is encrypted with keys kept only on the two devices.",
                          ),
                          style: MobileTheme.hintStyleOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyDialog extends StatefulWidget {
  const _SafetyDialog({required this.state, required this.attempt});
  final AppState state;
  final PairingAttempt attempt;
  @override
  State<_SafetyDialog> createState() => _SafetyDialogState();
}

class _SafetyDialogState extends State<_SafetyDialog> {
  bool _confirming = false;
  String? _error;
  Future<void> _confirm() async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await widget.state.link.confirmPairing(widget.attempt);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = pairingErrorMessage(error, widget.state.tr);
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return PopScope(
      canPop: !_confirming,
      child: AlertDialog(
        title: Text(state.tr('核对安全码', 'Compare safety codes')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.attempt.name),
            const SizedBox(height: 20),
            SelectableText(
              widget.attempt.safetyCode.join('  '),
              style: MobileTheme.codeStyleOf(context).copyWith(
                fontSize: Theme.of(context).textTheme.headlineSmall?.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              state.tr(
                '请确认电脑显示相同数字。不同请取消。',
                'Confirm the desktop shows the same digits. Cancel if they differ.',
              ),
            ),
            if (_confirming) ...[
              const SizedBox(height: 16),
              const ThinProgress(),
              Text(
                state.tr(
                  '正在确认；若电脑要求授权，请在电脑点击允许。',
                  'Confirming. Approve on the desktop if requested.',
                ),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: dialogButtons([
          OutlinedButton(
            onPressed: () async {
              try {
                await state.link.cancelPairing(widget.attempt);
                if (context.mounted) Navigator.pop(context, false);
              } catch (error) {
                if (mounted) {
                  setState(() => _error = pairingErrorMessage(error, state.tr));
                }
              }
            },
            child: Text(state.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: _confirming ? null : _confirm,
            child: Text(state.tr('确认', 'Confirm')),
          ),
        ]),
      ),
    );
  }
}
