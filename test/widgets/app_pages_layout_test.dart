import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/devices/devices_page.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pages = <String, Widget Function(AppState)>{
    '设置': (state) => SettingsPage(state: state),
    '主题': (state) => ThemePage(state: state),
    '字号': (state) => TextSizePage(state: state),
    '通知': (state) => NotificationsPage(state: state),
    '安全': (state) => SecurityPage(state: state),
    '设备': (state) => DevicesPage(state: state),
    '配对': (state) => PairDevicePage(state: state),
    '编辑 Bot': (state) => BotEditPage(state: state),
    '文件': (state) => FilesTab(state: state),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key}在窄屏深色大字号下不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(demo: true, store: MemoryLinkStore());
      addTearDown(state.dispose);
      await state.initialize();
      state.settings.language = 'zh';
      await tester.pumpWidget(
        MaterialApp(
          theme: MobileTheme.build(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: entry.value(state),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final scrolls = find.byType(Scrollable);
      if (scrolls.evaluate().isNotEmpty) {
        for (var i = 0; i < 8; i++) {
          await tester.drag(scrolls.first, const Offset(0, -450));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('配对链接输入框有内容时可以一键清空', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(MaterialApp(home: PairDevicePage(state: state)));
    expect(find.byTooltip('清空'), findsNothing);

    await tester.ensureVisible(find.text('改为粘贴配对链接'));
    await tester.pump();
    await tester.tap(find.text('改为粘贴配对链接'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'baocode://pair?d=abc');
    await tester.pump();
    await tester.tap(find.byTooltip('清空'));
    await tester.pump();

    expect(find.text('baocode://pair?d=abc'), findsNothing);
    expect(find.byTooltip('清空'), findsNothing);
  });
}
