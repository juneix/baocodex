import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/conversations/delete_conversation.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  bool fail = false;
  Completer<void>? pending;
  final calls = <(String, String, Map<String, Object?>)>[];
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => true;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktopId, method, params));
    if (fail) throw const UserFacingError('删除失败');
    await pending?.future;
    return null;
  }
}

void main() {
  testWidgets('删除前必须确认，取消不请求，确认只删除指定电脑会话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => deleteConversation(
                context,
                state,
                desktopId: '电脑乙',
                sessionId: 'same',
                title: '同名对话',
              ),
              child: const Text('删除'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, '电脑乙');
    expect(state.calls.single.$2, LinkMethods.delete);
    expect(state.calls.single.$3, {'session': 'same'});
  });

  testWidgets('失败不报告删除成功，进行中的删除不重复提交', (tester) async {
    final state = _State()..pending = Completer<void>();
    addTearDown(state.dispose);
    var deleted = false;
    late BuildContext page;
    Future<void> remove() => runUi(page, () async {
      deleted = await deleteConversation(
        page,
        state,
        desktopId: 'a',
        sessionId: 's',
        title: '对话',
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return Scaffold(
              body: TextButton(onPressed: remove, child: const Text('删除')),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    await remove();
    expect(state.calls, hasLength(1));
    state.pending!.completeError(const UserFacingError('删除失败'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });
}
