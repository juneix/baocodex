import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/models/project_icon.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/conversations/chats_tab.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:baocode_mobile/ui/widgets/project_icon_view.dart';
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('侧栏项目行读取并展示已有项目图标', (
    tester,
  ) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';

    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: ChatsTab(state: state),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('项目与对话'));
    await tester.pumpAndSettle();

    // 侧栏继续复用 IconCache，文件页仍使用文件夹入口。
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('baocode'), findsWidgets);
  });

  testWidgets('emoji, codicon, brand, and fallback render without requests', (
    tester,
  ) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();

    Widget view(ProjectIcon? icon) => ProjectIconView(
      state: state,
      ref: ProjectRef(
        'demo-desktop',
        ProjectInfo(
          id: 'p',
          name: 'p',
          path: 'D:/p',
          icon: {
            'type': switch (icon) {
              ProjectEmojiIcon() => 'emoji',
              ProjectCodiconIcon() => 'codicon',
              ProjectImageIcon() => 'image',
              ProjectBrandIcon() => 'brand',
              null => 'unknown',
            },
            'emoji': icon is ProjectEmojiIcon ? icon.emoji : null,
            'name': icon is ProjectCodiconIcon
                ? icon.name
                : icon is ProjectBrandIcon
                ? icon.name
                : null,
            'id': icon is ProjectImageIcon ? icon.id : null,
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            view(const ProjectEmojiIcon('📦')),
            view(const ProjectCodiconIcon('rocket')),
            view(const ProjectBrandIcon('Anthropic')),
            view(null),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('📦'), findsOneWidget);
    expect(find.byIcon(Icons.rocket_launch_outlined), findsOneWidget);
    expect(find.text('A'), findsOneWidget, reason: 'brand shows its initial');
    expect(find.text('p'), findsOneWidget, reason: '没有图标时显示项目名首字');
  });

  testWidgets('没有图标的项目：项目名首字用色调写在浅底上，带文件夹角标，和对话的实心头像分得开', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Center(
          child: ProjectIconView(
            state: state,
            ref: ProjectRef(
              'demo-desktop',
              ProjectInfo(id: 'p', name: '测试项目', path: 'D:/p'),
            ),
          ),
        ),
      ),
    );

    final letter = tester.widget<Text>(find.text('测'));
    // 对话头像是白字；项目的字是它自己的色调。
    expect(letter.style?.color, letterToneOf('测试项目'));
    expect(find.byKey(const ValueKey('project-folder-badge')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('电脑取不到的图片图标退回项目名首字', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectIconView(
          state: state,
          ref: ProjectRef(
            'demo-desktop',
            ProjectInfo(
              id: 'p',
              name: 'p',
              path: 'D:/p',
              icon: {'type': 'image', 'id': 'missing-icon'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('p'), findsOneWidget);
  });
}
