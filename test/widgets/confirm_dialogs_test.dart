import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
}

Widget _host(Widget home) =>
    MaterialApp(theme: MobileTheme.build(Brightness.light), home: home);

void main() {
  testWidgets('危险操作的确认按钮是红色并写明动作，普通操作保持主色', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final colors = Theme.of(context).colorScheme;

    final deleting = confirmAction(
      context,
      state,
      '删除对话？',
      '无法撤销',
      action: '删除',
      destructive: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('确认'), findsNothing);
    final delete = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    expect(delete.style!.backgroundColor!.resolve({}), colors.error);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await deleting, isTrue);

    final archiving = confirmAction(
      context,
      state,
      '归档对话？',
      '标题',
      action: '归档',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '归档'))
          .style,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await archiving, isFalse);
  });

  testWidgets('有未保存修改时返回先问，取消留在页面，放弃才离开', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    var dirty = true;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatefulBuilder(
                      builder: (context, setState) => DiscardGuard(
                        state: state,
                        dirty: dirty,
                        child: Scaffold(
                          appBar: AppBar(title: const Text('编辑页')),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('编辑页'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '放弃'));
    await tester.pumpAndSettle();
    expect(find.text('编辑页'), findsNothing);

    dirty = false;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsNothing);
    expect(find.text('编辑页'), findsNothing);
  });

  testWidgets('我的资料改一项就保存，不用再点完成，返回也不会丢', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(MyProfilePage(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    await tester.tap(find.text('名字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  小涛  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.settings.name, '小涛');
    expect(find.text('小涛'), findsOneWidget);
  });
}
