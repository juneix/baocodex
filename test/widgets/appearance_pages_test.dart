import 'package:baocode_mobile/chat/widgets/pixel_loader.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget home) => MaterialApp(
  theme: MobileTheme.build(Brightness.light, codeFontSize: 14),
  home: home,
);

void main() {
  tearDown(() {
    for (final role in PixelLoaderRole.values) {
      role.style.value = PixelLoaderStyle.fill;
      role.speed.value = role.defaultSpeed;
    }
  });

  test('默认字号为百分之百和十四，已保存字号保持不变', () {
    for (final settings in [AppSettings(), AppSettings.fromJson({})]) {
      expect(settings.textScale, 1.0);
      expect(settings.codeFontSize, 14);
    }
    final saved = AppSettings.fromJson({'textScale': 0.95, 'codeFontSize': 13});
    expect(saved.textScale, 0.95);
    expect(saved.codeFontSize, 13);
  });

  testWidgets('恢复默认将字号重置为百分之百和十四', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    state.settings.textScale = 1.2;
    state.settings.codeFontSize = 18;
    await tester.pumpWidget(host(TextSizePage(state: state)));
    await tester.ensureVisible(find.text('恢复默认'));
    await tester.tap(find.text('恢复默认'));
    await tester.pump();
    expect(state.settings.textScale, 1.0);
    expect(state.settings.codeFontSize, 14);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  test('旧的三种加载设置迁移到桌面样式键', () {
    final key = PixelLoaderRole.agent.styleKey;
    expect(AppSettings.fromJson({'loader': 'dots'}).loaders[key], 'dots');
    expect(AppSettings.fromJson({'loader': 'ring'}).loaders[key], 'circle');
    expect(AppSettings.fromJson({'loader': 'pixels'}).loaders[key], isNull);
    final saved = AppSettings.fromJson({
      'loaders': {key: 'rain'},
      'loader': 'dots',
    });
    expect(saved.loaders[key], 'rain');
    expect(AppSettings.fromJson(saved.toJson()).loaders[key], 'rain');
  });

  testWidgets('字号页用真实代码块预览，窄屏大字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.dark, codeFontSize: 14),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: TextSizePage(state: state),
      ),
    );
    await tester.pump();
    expect(find.byType(CodePanelPreview), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    // 代码块在滑块下面：拖动时就在眼前变，不用往上翻。
    final sliders = find.byType(Slider);
    expect(
      tester.getTopLeft(find.byType(CodePanelPreview)).dy,
      greaterThan(tester.getBottomLeft(sliders.last).dy),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  test('每个主题色在明暗下按钮字与主题色有足够反差，未知主题色退回绿色', () {
    for (final accent in MobileAccent.values) {
      for (final brightness in Brightness.values) {
        final scheme = MobileTheme.build(
          brightness,
          accent: accent,
        ).colorScheme;
        expect(scheme.primary, accent.of(brightness));
        // 按钮上的字和主题色有足够反差。
        final contrast =
            (scheme.primary.computeLuminance() -
                    scheme.onPrimary.computeLuminance())
                .abs();
        expect(contrast, greaterThan(.3), reason: '${accent.name} $brightness');
      }
    }
    expect(MobileAccent.parse('nope'), MobileAccent.amber);
  });

  testWidgets('主题页可选多款主题色并保存', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(host(ThemePage(state: state)));
    expect(find.text('主题色'), findsOneWidget);
    // 琥珀排第一，是默认项。
    expect(MobileAccent.values.first, MobileAccent.amber);
    for (final accent in MobileAccent.values) {
      await tester.ensureVisible(find.byKey(ValueKey('accent-${accent.name}')));
      expect(find.text(accent.zh), findsOneWidget);
    }
    expect(state.settings.accent, 'amber');
    await tester.tap(find.byKey(const ValueKey('accent-blue')));
    await tester.pump();
    expect(state.settings.accent, 'blue');
    expect(AppSettings.fromJson(state.settings.toJson()).accent, 'blue');
    // 早先自动写入的旧键不算用户选择，读回默认金色。
    expect(AppSettings.fromJson({'accent': 'blue'}).accent, 'amber');
    // 用户明确选过的主题色都保留，包括绿色。
    expect(AppSettings.fromJson({'accentColor': 'green'}).accent, 'green');
    expect(AppSettings.fromJson({'accentColor': 'indigo'}).accent, 'indigo');
  });
}
