import 'dart:convert';

import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/chat/widgets/step_images.dart';
import 'package:baocode_mobile/ui/widgets/image_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
);

/// 每张图字节不同（尾部附加序号），便于断言保存的是哪一张。
List<GalleryImage> _images(int count) => [
  for (var i = 0; i < count; i++)
    GalleryImage(Uint8List.fromList([..._png, i]), name: 'pic-$i.png'),
];

Widget _app(Widget home) => MaterialApp(home: home);

/// 打开画廊的按钮，用来验证关闭后回到原页面。
Widget _opener(List<GalleryImage> images, int index, {GallerySaver? saver}) =>
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showImageGallery(
            context,
            images,
            initialIndex: index,
            saver: saver,
          ),
          child: const Text('open'),
        ),
      ),
    );

Future<void> _swipe(WidgetTester tester, Offset by) async {
  await tester.fling(find.byType(PageView), by, 1500);
  await tester.pumpAndSettle();
}

void main() {
  // 这些文字跟着界面语言走；测试里按中文看。
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  testWidgets('从点击的索引打开并显示 n / total 与文件名', (tester) async {
    await tester.pumpWidget(
      _app(ImageGalleryPage(images: _images(3), initialIndex: 2)),
    );
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('pic-2.png'), findsOneWidget);
  });

  testWidgets('越界起始索引被夹到有效范围', (tester) async {
    await tester.pumpWidget(
      _app(ImageGalleryPage(images: _images(2), initialIndex: 9)),
    );
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('左右滑动切换图片，首尾不越界', (tester) async {
    await tester.pumpWidget(
      _app(ImageGalleryPage(images: _images(3), initialIndex: 1)),
    );
    await _swipe(tester, const Offset(-400, 0));
    expect(find.text('3 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(-400, 0));
    expect(find.text('3 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(400, 0));
    await _swipe(tester, const Offset(400, 0));
    expect(find.text('1 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(400, 0));
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('单张图片不显示计数', (tester) async {
    await tester.pumpWidget(_app(ImageGalleryPage(images: _images(1))));
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('pic-0.png'), findsOneWidget);
    await _swipe(tester, const Offset(-400, 0));
    expect(find.text('pic-0.png'), findsOneWidget);
  });

  testWidgets('预览复制的是当前页原图，而不是文件名或图片编号', (tester) async {
    Map? copied;
    const channel = MethodChannel('local.baocode.mobile/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'writeChatClipboard') copied = call.arguments as Map;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(_app(ImageGalleryPage(images: _images(3))));
    await _swipe(tester, const Offset(-400, 0));
    await tester.tap(find.byTooltip('复制图片'));
    await tester.pump();
    expect(copied, isNotNull);
    expect(copied!['text'], '');
    expect((copied!['image'] as Map)['bytes'], _images(3)[1].bytes);
    expect((copied!['image'] as Map)['type'], 'image/png');
    expect(find.text('图片已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存的是当前所在页的图片', (tester) async {
    final saved = <Uint8List>[];
    await tester.pumpWidget(
      _app(
        ImageGalleryPage(
          images: _images(3),
          saver: (context, bytes) async => saved.add(bytes),
        ),
      ),
    );
    await _swipe(tester, const Offset(-400, 0));
    await tester.tap(find.byTooltip('保存到相册'));
    await tester.pump();
    expect(saved, hasLength(1));
    expect(saved.single.last, 1);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('关闭后画廊整体移除并回到原页面', (tester) async {
    await tester.pumpWidget(_opener(_images(3), 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ImageGalleryPage), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('键盘与输入焦点', () {
    Widget host(
      TextEditingController c,
      FocusNode f,
      List<GalleryImage> imgs,
    ) => _app(
      Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextField(controller: c, focusNode: f),
              TextButton(
                onPressed: () => showImageGallery(context, imgs),
                child: const Text('open'),
              ),
            ],
          ),
        ),
      ),
    );

    Future<void> openAndClose(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageGalleryPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ImageGalleryPage), findsNothing);
    }

    testWidgets('输入中打开预览：收起焦点，关闭后不自动回焦，草稿与光标保留', (tester) async {
      final c = TextEditingController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(f.dispose);
      await tester.pumpWidget(host(c, f, _images(1)));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hello world');
      c.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      expect(f.hasFocus, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(f.hasFocus, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(f.hasFocus, isFalse);
      expect(c.text, 'hello world');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('有焦点但键盘已收起：打开关闭后仍不回焦', (tester) async {
      final c = TextEditingController(text: 'draft');
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(f.dispose);
      await tester.pumpWidget(host(c, f, _images(1)));
      f.requestFocus();
      await tester.pump();
      tester.testTextInput.hide();
      await tester.pump();
      expect(f.hasFocus, isTrue);

      await openAndClose(tester);
      expect(f.hasFocus, isFalse);
      expect(c.text, 'draft');
    });

    testWidgets('关闭后再次手动点击输入框能正常获得焦点并弹键盘', (tester) async {
      final c = TextEditingController(text: 'draft');
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(f.dispose);
      await tester.pumpWidget(host(c, f, _images(1)));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await openAndClose(tester);
      expect(f.hasFocus, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(f.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(c.text, 'draft');
    });
  });

  testWidgets('MemoryPicture 带分组时从被点的那张打开', (tester) async {
    final group = _images(3);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            for (var i = 0; i < group.length; i++)
              MemoryPicture(
                bytes: group[i].bytes,
                name: group[i].name,
                group: group,
                index: i,
                height: 40,
                width: 300,
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(MemoryPicture).at(1));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(-400, 0));
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('MemoryPicture 无分组时仍是单张画廊', (tester) async {
    await tester.pumpWidget(
      _app(MemoryPicture(bytes: _png, name: 'solo.png', height: 40)),
    );
    await tester.tap(find.byType(MemoryPicture));
    await tester.pumpAndSettle();
    expect(find.text('solo.png'), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('不同分组互不串页', (tester) async {
    final a = _images(3), b = _images(2);
    Widget row(List<GalleryImage> g) => Row(
      children: [
        for (var i = 0; i < g.length; i++)
          Expanded(
            child: MemoryPicture(
              bytes: g[i].bytes,
              name: g[i].name,
              group: g,
              index: i,
              height: 30,
              width: 300,
            ),
          ),
      ],
    );
    await tester.pumpWidget(_app(Column(children: [row(a), row(b)])));
    await tester.tap(find.byType(MemoryPicture).at(3));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await _swipe(tester, const Offset(-400, 0));
    await _swipe(tester, const Offset(-400, 0));
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('工具步骤缩略图同一组可左右翻看', (tester) async {
    final images = [
      for (var i = 0; i < 3; i++)
        ImageAttachment(
          name: 'step-$i.png',
          mediaType: 'image/png',
          bytes: Uint8List.fromList([..._png, i]),
        ),
    ];
    await tester.pumpWidget(
      _app(Scaffold(body: StepThumbnails(images: images))),
    );
    await tester.tap(find.byType(Image).at(2));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(400, 0));
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('同一份字节重复出现在组内时，翻页与保存仍按页对应', (tester) async {
    final shared = Uint8List.fromList([..._png, 7]);
    final saved = <Uint8List>[];
    await tester.pumpWidget(
      _app(
        ImageGalleryPage(
          images: [
            for (var i = 0; i < 3; i++)
              GalleryImage(shared, name: 'dup-$i.png'),
          ],
          saver: (context, bytes) async => saved.add(bytes),
        ),
      ),
    );
    // 翻页途中相邻两页同时存在，重复附件也应正常显示。
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('dup-1.png'), findsOneWidget);
    await tester.tap(find.byTooltip('保存到相册'));
    await tester.pump();
    expect(saved.single, same(shared));
  });

  testWidgets('真实双指放大后单指横拖只平移，不翻页', (tester) async {
    await tester.pumpWidget(
      _app(ImageGalleryPage(images: _images(3), initialIndex: 1)),
    );
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final a = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final b = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center - Offset(20.0 + i * 12, 0));
      await b.moveTo(center + Offset(20.0 + i * 12, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.5));

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget, reason: '放大后单指拖动不应翻页');
  });
}
