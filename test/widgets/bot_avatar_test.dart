import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  bool online = true;
  int failures = 0;
  int requests = 0;

  @override
  bool isOnline(String desktopId) => online;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    requests++;
    if (failures > 0) {
      failures--;
      throw StateError('合成失败');
    }
    return {'data': _pixel, 'type': 'image/png'};
  }
}

const _ref = BotRef('d', LinkBot(id: 'x', name: '小宝', avatar: 'xiaobao.png'));

Future<void> _pump(WidgetTester tester, _State state) => tester.pumpWidget(
  MaterialApp(
    home: AnimatedBuilder(
      animation: state,
      builder: (_, _) => Scaffold(
        body: BotAvatar(state: state, ref: _ref),
      ),
    ),
  ),
);

bool _hasPicture(WidgetTester tester) =>
    tester.widget<LetterAvatar>(find.byType(LetterAvatar)).imageBytes != null;

void main() {
  testWidgets('页面先于连接建好，连上后补取头像', (tester) async {
    final state = _State()..online = false;
    addTearDown(state.dispose);
    await _pump(tester, state);
    await tester.pump();
    expect(_hasPicture(tester), isFalse);
    expect(state.requests, 0);
    state.online = true;
    state.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(_hasPicture(tester), isTrue);
  });

  testWidgets('连上瞬间请求失败也会补取，页面不用重开', (tester) async {
    final state = _State()..failures = 1;
    addTearDown(state.dispose);
    await _pump(tester, state);
    await tester.pump();
    expect(_hasPicture(tester), isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_hasPicture(tester), isTrue);
    expect(state.requests, 2);
  });

  testWidgets('一直取不到时有限次重试后停下', (tester) async {
    final state = _State()..failures = 1000;
    addTearDown(state.dispose);
    await _pump(tester, state);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 40));
    }
    expect(state.requests, 5);
    expect(_hasPicture(tester), isFalse);
  });
}
