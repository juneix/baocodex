import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/main.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore(), demo: true);
  void poke() => notifyListeners();
}

void main() {
  testWidgets('状态通知不换主题，改了设置才换', (tester) async {
    final state = _State();
    await tester.pumpWidget(MobileApp(state: state));
    ThemeData theme() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    ThemeData dark() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).darkTheme!;
    final light = theme(), night = dark();

    state.poke();
    await tester.pump();
    expect(identical(theme(), light), isTrue);
    expect(identical(dark(), night), isTrue);

    state.settings.textScale = state.settings.textScale + .1;
    state.poke();
    await tester.pump();
    expect(identical(theme(), light), isFalse);
    expect(identical(dark(), night), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
