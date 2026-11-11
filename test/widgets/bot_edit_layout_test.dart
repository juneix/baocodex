import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('新建明确展示官方默认执行模式，而不是把附加能力当权限', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: BotEditPage(state: state)));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bot-chat-only')),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('bot-chat-only')))
          .value,
      isFalse,
    );
    expect(find.text('干活方式'), findsOneWidget);
    expect(find.text('只聊天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bot-chat-only')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('bot-chat-only')))
          .value,
      isTrue,
    );
  });

  testWidgets('编辑分组、多行字段和能力切换在窄屏大字号可用', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: BotEditPage(state: state),
      ),
    );
    expect(find.text('新 Bot'), findsOneWidget);
    final doneRect = tester.getRect(find.widgetWithText(FilledButton, '完成'));
    expect(doneRect.right, lessThanOrEqualTo(348));
    expect(doneRect.height, lessThanOrEqualTo(40));
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pump();
    expect(find.text('请填写名字'), findsOneWidget);
    await tester.tap(find.text('名字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '测试小宝');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('测试小宝'), findsOneWidget);
    final pageScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final entry in {'身份设定': 1, '说话风格': 1}.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.scrollUntilVisible(field, 220, scrollable: pageScroll);
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .minLines,
        entry.value,
      );
      expect(
        find.ancestor(of: field, matching: find.byType(GroupCard)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(
      find.text('管智能体'),
      160,
      scrollable: pageScroll,
    );
    await tester.tap(find.text('管智能体'));
    await tester.pumpAndSettle();
    final toggle = find.ancestor(
      of: find.text('管智能体'),
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      find.ancestor(of: toggle, matching: find.byType(GroupCard)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
