import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  Object? download = const {'data': 'AAH/'};
  final downloads = <Map<String, Object?>>[];
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => true;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.download) {
      downloads.add(params);
      return download;
    }
    return {'binary': true};
  }
}

void main() {
  const channel = MethodChannel('local.baocode.mobile/platform');
  testWidgets('无法预览的文件仍可下载，取消保存不提示成功', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    final saves = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      saves.add(call);
      return false;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FileViewerPage(
          state: state,
          project: const ProjectRef(
            'b',
            ProjectInfo(id: 'p', name: '项目', path: '/p'),
          ),
          path: 'folder/data.bin',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法预览二进制文件'), findsOneWidget);
    await tester.tap(find.byTooltip('下载文件'));
    await tester.pumpAndSettle();
    expect(state.downloads.single, {'project': 'p', 'path': 'folder/data.bin'});
    expect(saves.single.method, 'saveFile');
    expect(saves.single.arguments, {
      'name': 'data.bin',
      'bytes': [0, 1, 255],
    });
    expect(find.text('文件已保存'), findsNothing);
    state.download = {'tooLarge': true, 'size': 9000000};
    await tester.tap(find.byTooltip('下载文件'));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(find.textContaining('8 MiB'), findsOneWidget);
  });
}
