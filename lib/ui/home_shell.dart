import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/update_check.dart';
import '../theme/app_theme.dart';
import 'conversations/chats_tab.dart';
import 'settings/settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, this.updateChecker});
  final AppState state;

  /// 打开应用时的自动检查；测试里换成不联网的。
  final AutoUpdateChecker? updateChecker;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final _updates =
      widget.updateChecker ?? AutoUpdateChecker(currentVersion: appVersion);

  @override
  void initState() {
    super.initState();
    if (widget.state.demo) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  /// 冷启动之外，从后台回到应用也算一次打开。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _checkForUpdates();
  }

  /// 有可下载的新版本才弹窗；没有或失败都不打扰。
  Future<void> _checkForUpdates() async {
    if (UpdateDialog.isOpen) return;
    final check = await _updates.check();
    if (check == null || !mounted || UpdateDialog.isOpen) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(state: widget.state, release: check.latest),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          if (state.demo)
            SafeArea(
              bottom: false,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      state.tr(
                        '演示模式 · 不会执行命令',
                        'Demo mode · no commands are executed',
                      ),
                      textAlign: TextAlign.center,
                      style: MobileTheme.metaStyleOf(
                        context,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (state.startupError != null)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  state.startupError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(child: ChatsTab(state: state)),
        ],
      ),
    );
  }
}
