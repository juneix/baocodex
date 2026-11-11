import 'dart:ui' as ui;

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/conversations/open_conversation.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  @override
  List<SessionRef> get sessions => [
    for (final desktop in ['a', 'b'])
      SessionRef(
        desktop,
        SessionSummary(
          id: 'same',
          project: '$desktop-project',
          title: '$desktop 的真实任务',
          updatedAt: DateTime(2026),
        ),
      ),
  ];
  @override
  List<ProjectRef> get projects => const [
    ProjectRef('a', ProjectInfo(id: 'a-project', name: '项目', path: '/a')),
  ];
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Android 进入和退出页面的中间帧保持不透明：$brightness', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      const incoming = Color(0xff006b45);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: MobileTheme.build(brightness)
                .copyWith(platform: TargetPlatform.android),
            home: Scaffold(
              backgroundColor: const Color(0xff93254a),
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => openPage<void>(
                      context,
                      Scaffold(
                        backgroundColor: incoming,
                        appBar: AppBar(title: const Text('聊天页')),
                        body: const Center(child: Text('聊天正文')),
                      ),
                    ),
                    child: const Text('进入聊天'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入聊天'));
      await tester.pump();
      Future<void> expectOpaque() async {
        final pixel = await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (400 * image.width + 350) * 4;
          final color = Color.fromARGB(
            rgba.getUint8(offset + 3),
            rgba.getUint8(offset),
            rgba.getUint8(offset + 1),
            rgba.getUint8(offset + 2),
          );
          image.dispose();
          return color;
        });
        expect(pixel, incoming, reason: '新页面不能透出旧页面文字或与浅色背景混合');
      }

      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 70));
        await expectOpaque();
      }
      await tester.pump(const Duration(milliseconds: 70));
      final route = ModalRoute.of(tester.element(find.text('聊天正文')))!;
      expect(route.animation!.isCompleted, isTrue, reason: '进入页面应在 300ms 内完成');
      await tester.pumpAndSettle();
      expect(find.text('聊天正文'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await expectOpaque();
      await tester.pumpAndSettle();
      expect(find.text('进入聊天'), findsOneWidget);
      expect(find.text('聊天正文'), findsNothing);
      await tester.tap(find.text('进入聊天'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('进入聊天'), findsOneWidget);
      expect(find.text('聊天正文'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('任务卡片按电脑和会话解析真实标题与项目，不继承 Bot 项目', () {
    final state = _State();
    addTearDown(state.dispose);
    final a = resolveConversation(state, desktopId: 'a', sessionId: 'same');
    expect(a.title, 'a 的真实任务');
    expect(a.projectId, 'a-project');
    expect(a.projectUnavailable, isFalse);
    final b = resolveConversation(state, desktopId: 'b', sessionId: 'same');
    expect(b.title, 'b 的真实任务');
    expect(b.projectId, isNull);
    expect(b.projectUnavailable, isTrue);
  });

  test('未列出的会话保留真实 id 供只读打开，不自动取消归档或伪造项目', () {
    final state = _State();
    addTearDown(state.dispose);
    final target = resolveConversation(
      state,
      desktopId: 'a',
      sessionId: 'archived',
    );
    expect(target.sessionId, 'archived');
    expect(target.projectId, isNull);
    expect(target.projectUnavailable, isTrue);
  });
}
