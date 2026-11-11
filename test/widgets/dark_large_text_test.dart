import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/devices/devices_page.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/conversations/chats_tab.dart';
import 'package:baocode_mobile/chat/widgets/turn_footer.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pages = <String, Widget Function(AppState)>{
    '设置': (state) => SettingsPage(state: state),
    '主题': (state) => ThemePage(state: state),
    '字号': (state) => TextSizePage(state: state),
    '通知': (state) => NotificationsPage(state: state),
    '安全': (state) => SecurityPage(state: state),
    '设备': (state) => DevicesPage(state: state),
    '配对': (state) => PairDevicePage(state: state),
    '编辑 Bot': (state) => BotEditPage(state: state),
    '文件': (state) => FilesTab(state: state),
    '扩展': (state) => ExtensionsPage(state: state),
    '首页': (state) => ChatsTab(state: state),
    '侧栏': (state) => ChatsTab(state: state),
    '资料': (state) => BotProfilePage(state: state, ref: state.bots.first),
    '项目文件': (state) => FilesPage(
      state: state,
      project: state.projects.first,
      listing: const {
        'paths': ['lib/a.dart', 'lib/b.dart', 'README.md'],
      },
    ),
    '项目聊天': (state) => ChatPage(
      state: state,
      desktopId: state.desktops.first.id,
      sessionId: state.sessions.first.session.id,
      title: '测试项目',
      projectId: state.projects.first.project.id,
    ),
    'Bot聊天': (state) => ChatPage(
      state: state,
      desktopId: state.bots.first.desktopId,
      sessionId: state.bots.first.bot.session ?? 'bot:test',
      title: '小宝',
      botId: state.bots.first.bot.id,
    ),
    '统计行': (state) => const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: TurnFooter(
          answer: '回答',
          worked: Duration(seconds: 96),
          usage: TurnUsage(
            inputTokens: 200000,
            outputTokens: 2070,
            tokensPerSecond: 37.16,
            costUsd: .15,
          ),
          zh: true,
        ),
      ),
    ),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key}在窄屏深色大字号下不溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(demo: true, store: MemoryLinkStore());
      addTearDown(state.dispose);
      await state.initialize();
      state.settings.language = 'zh';
      state.settings.textScale = 1.6;
      await tester.pumpWidget(
        MaterialApp(
          theme: MobileTheme.build(
            Brightness.dark,
            messageScale: state.settings.textScale,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: entry.value(state),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (entry.key == '侧栏') {
        await tester.tap(find.byTooltip('项目与对话'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      if (entry.key == 'Bot聊天') {
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(scaffold.backgroundColor, isNot(const Color(0xFFEDEDED)));
      }
      final scrolls = entry.key == '侧栏'
          ? find.descendant(
              of: find.byKey(const ValueKey('conversation-navigation-list')),
              matching: find.byType(Scrollable),
            )
          : find.byType(Scrollable);
      if (scrolls.evaluate().isNotEmpty) {
        for (var i = 0; i < 8; i++) {
          await tester.drag(scrolls.first, const Offset(0, -450));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
