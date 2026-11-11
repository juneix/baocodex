import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('字号页面展示真实消息样式且控件不随阅读倍率变化', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    state.settings.textScale = 1.6;
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light, messageScale: 1.6),
        home: TextSizePage(state: state),
      ),
    );
    expect(
      tester.widget<Text>(find.text('这段代码做什么？')).style?.fontSize,
      closeTo(MobileType.body * 1.6, .001),
    );
    expect(find.text('消息阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 代码块的语法高亮有个异步计时器：先撤掉组件树，再让时间走完。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('分割线从文字开始，不划到图标下面', (tester) async {
    Future<double> indentOf(List<Widget> rows) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GroupCard(children: rows)),
        ),
      );
      return tester.widget<Divider>(find.byType(Divider)).indent!;
    }

    final withIcons = await indentOf(const [
      SettingsRow('甲', icon: 'bell'),
      SettingsRow('乙', icon: 'lock'),
    ]);
    final text = tester.getTopLeft(find.text('乙')).dx;
    expect(withIcons, text);
    expect(await indentOf(const [SettingsRow('甲'), SettingsRow('乙')]), 16);
  });
}
