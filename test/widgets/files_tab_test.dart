import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/link/phone_link.dart' show KeptDesktop;
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  final online = <String>{};
  void setOnline(String id, bool value) {
    value ? online.add(id) : online.remove(id);
    notifyListeners();
  }

  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => online.contains(desktopId);
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'a', name: '离线甲', publicKey: 'k'),
    KeptDesktop(id: 'b', name: '在线乙', publicKey: 'k'),
    KeptDesktop(id: 'c', name: '启动时离线丙', publicKey: 'k'),
  ];
  @override
  List<ProjectRef> get projects => [
    for (final id in ['a', 'b', 'c'])
      ProjectRef(id, ProjectInfo(id: 'p$id', name: '项目$id', path: 'E:/$id')),
  ];
}

Future<void> _pump(WidgetTester tester, _State state) async {
  await tester.pumpWidget(MaterialApp(home: FilesTab(state: state)));
  await tester.pump();
}

void main() {
  testWidgets('标题是设备切换，只列出当前电脑的项目', (tester) async {
    final state = _State()..online.add('b');
    addTearDown(state.dispose);
    await _pump(tester, state);
    expect(find.text('在线乙'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-status-b')), findsOneWidget);
    expect(find.text('项目b'), findsOneWidget);
    expect(find.text('项目a'), findsNothing);
    expect(find.text('离线甲'), findsNothing);
  });

  testWidgets('切换到离线电脑时提示离线，切换在各页共享', (tester) async {
    final state = _State()..online.add('b');
    addTearDown(state.dispose);
    await _pump(tester, state);
    state.selectDesktop('a');
    await tester.pump();
    expect(find.text('离线甲'), findsOneWidget);
    expect(find.text('项目b'), findsNothing);
    expect(find.text('电脑离线'), findsOneWidget);
  });

  testWidgets('未手动选择时跟随第一台上线的电脑', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _pump(tester, state);
    expect(find.text('离线甲'), findsOneWidget);
    state.setOnline('c', true);
    await tester.pump();
    expect(find.text('启动时离线丙'), findsOneWidget);
    expect(find.text('项目c'), findsOneWidget);
  });

  test('文件页把主目录下的路径缩写成 ~', () {
    expect(
      shortPath('/Users/developer/Desktop/project/app'),
      '~/Desktop/project/app',
    );
    expect(shortPath('/home/acme'), '~');
    expect(shortPath(r'C:\Users\acme\code'), r'~\code');
    expect(shortPath('/root'), '/root');
    expect(shortPath('/Users'), '/Users');
  });
}
