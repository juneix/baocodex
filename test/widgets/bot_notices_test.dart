import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/link/phone_link.dart' show KeptDesktop;
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
  List<KeptDesktop> kept = const [
    KeptDesktop(id: 'd1', name: '电脑一', publicKey: ''),
    KeptDesktop(id: 'd2', name: '电脑二', publicKey: ''),
  ];
  Set<String> online = {'d1', 'd2'};
  List<BotRef> botList = [];

  @override
  List<KeptDesktop> get desktops => kept;
  @override
  bool isOnline(String id) => online.contains(id);
  @override
  List<BotRef> get bots => botList;
}

void main() {
  testWidgets('Bot 列表优先显示最近一句，其次签名，不露身份设定', (tester) async {
    LinkBot bot(String id, {String? last, String signature = ''}) => LinkBot(
      id: id,
      name: id,
      identity: '身份设定-$id',
      signature: signature,
      last: last,
    );
    final state = _State()
      ..botList = [
        BotRef('d1', bot('聊过', last: '最近一句', signature: '签名甲')),
        BotRef('d1', bot('没聊过', signature: '签名乙')),
        BotRef('d1', bot('都没有', last: '')),
      ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotsTab(state: state),
      ),
    );
    expect(find.textContaining('最近一句', findRichText: true), findsOneWidget);
    expect(find.textContaining('签名甲', findRichText: true), findsNothing);
    expect(find.textContaining('签名乙', findRichText: true), findsOneWidget);
    expect(find.textContaining('身份设定', findRichText: true), findsNothing);
  });

  testWidgets('主动通知说明讲清有的只记下或直接通知，不再声称每条都用模型', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotEditPage(state: state),
      ),
    );
    await tester.scrollUntilVisible(
      find.textContaining('不用模型'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('由它决定要不要找你'), findsOneWidget);
    expect(find.textContaining('只记下'), findsOneWidget);
    expect(find.textContaining('tell'), findsNothing);
    expect(find.textContaining('每条通知都会用一次模型'), findsNothing);
  });
}
