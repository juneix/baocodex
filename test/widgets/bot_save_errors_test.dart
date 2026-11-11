import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktop) => true;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.botMemory) return {'text': '旧记忆', 'self': '旧备注'};
    throw const LinkRemoteException(
      LinkErrors.unsupported,
      'synthetic-private-error',
    );
  }
}

void main() {
  const ref = BotRef('a', LinkBot(id: 'b', name: '助手', chatOnly: true));

  testWidgets('资料保存明确不支持时显示拒绝原因，不伪装成网络未确认', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BotEditPage(state: state, ref: ref),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('电脑不支持该保存操作'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('电脑不支持该保存操作'), findsOneWidget);
    expect(find.textContaining('synthetic-private-error'), findsNothing);
  });

  testWidgets('记忆保存保留编辑内容，并区分明确拒绝', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BotMemoryPage(state: state, ref: ref),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新记忆');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('电脑不支持该保存操作'), findsOneWidget);
    expect(find.text('新记忆'), findsOneWidget);
    expect(find.textContaining('synthetic-private-error'), findsNothing);
  });
}
