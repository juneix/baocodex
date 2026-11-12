import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  bool? pinned = false;
  bool hidden = false, fail = false;
  final calls = <(String, String, Map<String, Object?>)>[];

  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => true;
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'a', name: '电脑甲', publicKey: ''),
    KeptDesktop(id: 'b', name: '电脑乙', publicKey: ''),
  ];
  @override
  Map<String, LinkState> get snapshots => {
    for (final id in ['a', 'b'])
      id: LinkState(
        device: const DeviceInfo(name: '电脑', kind: 'mac', system: 'macOS'),
        projects: [
          const ProjectInfo(
            id: 'other',
            name: '普通项目',
            path: '/other',
            pinned: false,
          ),
          if (id != 'a' || !hidden)
            ProjectInfo(
              id: 'same',
              name: '同名项目',
              path: '/same',
              pinned: pinned,
            ),
        ],
        sessions: const [],
      ),
  };
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktop, method, params));
    if (fail) throw const UserFacingError('合成请求失败');
    if (method == LinkMethods.pinProject) pinned = params['pinned'] as bool;
    if (method == LinkMethods.hideProject) hidden = true;
    notifyListeners();
    return null;
  }
}

void main() {
  testWidgets('项目置顶只请求所选电脑，并保持普通项目原顺序', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: FilesTab(state: state)));
    await tester.longPress(
      find.byKey(const ValueKey('project-actions-a-same')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, 'a');
    expect(state.calls.single.$2, LinkMethods.pinProject);
    expect(state.calls.single.$3, {'project': 'same', 'pinned': true});
    expect(
      state.projects
          .where((ref) => ref.desktopId == 'a')
          .map((ref) => ref.project.id),
      ['same', 'other'],
    );
  });

  testWidgets('隐藏项目取消不发请求，确认后不隐藏另一台电脑的同名项目', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: FilesTab(state: state)));
    Future<void> menu() async {
      await tester.longPress(
        find.byKey(const ValueKey('project-actions-a-same')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
    }

    await menu();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await menu();
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, 'a');
    expect(state.calls.single.$2, LinkMethods.hideProject);
    expect(state.calls.single.$3, {'project': 'same'});
    expect(
      state.projects
          .where((ref) => ref.project.id == 'same')
          .map((ref) => ref.desktopId),
      ['b'],
    );
  });

  testWidgets('旧桌面不提供项目置顶入口，失败保留项目并显示错误', (tester) async {
    final state = _State()
      ..pinned = null
      ..fail = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: FilesTab(state: state)));
    await tester.longPress(
      find.byKey(const ValueKey('project-actions-a-same')),
    );
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsNothing);
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('合成请求失败'), findsOneWidget);
    expect(state.hidden, isFalse);
  });
}
