import 'dart:async';

import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowStore extends MemoryLinkStore {
  final gate = Completer<void>();
  bool blocked = false;
  @override
  Future<void> write(String key, String value) async {
    if (key == 'drafts' && !blocked) {
      blocked = true;
      await gate.future;
    }
    await super.write(key, value);
  }
}

class _State extends AppState {
  _State(_SlowStore store) : super(store: store, demo: true);
  @override
  Future<void> openSession(String desktop, String session) async {}
  @override
  Future<void> closeSession(String desktop, String session) async {}
}

void main() {
  testWidgets('安全存储慢写时跨页恢复最新内存草稿，而不是等待旧写入', (tester) async {
    final store = _SlowStore();
    final state = _State(store);
    addTearDown(state.dispose);
    addTearDown(() {
      if (!store.gate.isCompleted) store.gate.complete();
    });
    await state.initialize();
    Widget page() => MaterialApp(
      home: ChatPage(
        state: state,
        desktopId: 'demo-desktop',
        sessionId: 's',
        title: '任务',
      ),
    );
    await tester.pumpWidget(page());
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'first');
    await tester.pump(const Duration(milliseconds: 350));
    expect(store.blocked, isTrue);
    await tester.enterText(find.byType(TextField).first, 'newest');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'newest',
    );
    store.gate.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
