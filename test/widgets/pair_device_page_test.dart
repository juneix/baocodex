import 'package:baocode_mobile/link/link_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/devices/devices_page.dart';
import 'package:baocode_mobile/ui/devices/qr_scan_view.dart';
import 'package:baocode_mobile/theme/app_theme.dart';

void main() {
  testWidgets('配对页：三步说明、粘贴模式与安全说明', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(MaterialApp(home: PairDevicePage(state: state)));

    expect(find.text('在电脑上打开 BaoCode'), findsOneWidget);
    expect(find.text('进入 设置 → 手机，点击「显示二维码」'), findsOneWidget);
    expect(find.text('用手机扫描电脑上显示的二维码'), findsOneWidget);
    expect(find.text('让二维码填满方框；识别不到时离远一点，或双指放大'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.ensureVisible(find.text('改为粘贴配对链接'));
    await tester.pump();
    await tester.tap(find.text('改为粘贴配对链接'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('改为扫描二维码'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('二维码里有电脑的公钥和地址'));
    await tester.pump();
    expect(find.textContaining('二维码里有电脑的公钥和地址'), findsOneWidget);
  });

  testWidgets('常规手机首屏可见粘贴入口和附近电脑，说明不抢正文层级', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: PairDevicePage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    final paste = find.text('改为粘贴配对链接');
    expect(paste.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(find.text('附近的电脑')).dy, lessThanOrEqualTo(820));
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏大字下取景框继续自适应保持正方形', (tester) async {
    tester.view.physicalSize = const Size(220, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.dark),
        home: PairDevicePage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getSize(find.byKey(const ValueKey('pair-viewfinder')));
    expect(box.width, box.height);
    expect(box.width, lessThanOrEqualTo(188));
    expect(box.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  test('配对扫码默认放大、分析更勤，只认二维码', () {
    final controller = createPairingScannerController();
    addTearDown(controller.dispose);
    expect(controller.formats, [BarcodeFormat.qrCode]);
    expect(controller.initialZoom, pairingInitialZoom);
    expect(pairingInitialZoom, greaterThan(1));
    expect(controller.detectionTimeoutMs, lessThan(250));
    expect(controller.autoZoom, isTrue);
  });
}
