import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/markdown/markdown_view.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
  Map<String, Object?> file = {
    'text': '# 文件标题\n\n正文包含 **重点**。\n\n> 引用说明\n\n- 一条列表\n',
  };
  final calls = <String>[];

  @override
  bool isOnline(String desktop) => true;

  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add(method);
    return file;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _State state, {
  String path = 'docs/README.md',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MobileTheme.build(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FileViewerPage(
        state: state,
        project: const ProjectRef(
          'd',
          ProjectInfo(id: 'p', name: '项目', path: '/workspace'),
        ),
        path: path,
        sessionId: 's',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多文件操作'));
  await tester.pumpAndSettle();
}

void main() {
  for (final extension in ['md', 'MD', 'markdown']) {
    testWidgets('Markdown默认预览，可切源码再切回，保持只读：$extension', (tester) async {
      final state = _State();
      addTearDown(state.dispose);
      await _pump(tester, state, path: 'docs/readme.$extension');
      expect(find.byType(MarkdownBlocks), findsWidgets);
      expect(find.text('文件标题', findRichText: true), findsOneWidget);
      expect(find.textContaining('只读'), findsOneWidget);
      await tester.tap(find.text('源码'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBlocks), findsNothing);
      expect(find.textContaining('# 文件标题', findRichText: true), findsOneWidget);
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBlocks), findsWidgets);
      expect(state.calls, [LinkMethods.read]);
    });
  }

  testWidgets('普通文本的底部菜单包含阅读与复制操作，保留下载入口', (tester) async {
    final state = _State()..file = {'text': 'alpha\nbeta\ngamma'};
    addTearDown(state.dispose);
    await _pump(tester, state, path: 'dart_test.yaml');
    expect(find.byType(MarkdownBlocks), findsNothing);
    expect(find.text('只读 · 3 行'), findsOneWidget);
    await _menu(tester);
    for (final text in [
      '自动换行',
      '跳到行',
      '放大字号',
      '缩小字号',
      '复制路径',
      '复制内容',
      '下载文件',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.tap(find.text('自动换行'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制路径和内容使用真实原文，Markdown预览不改变剪贴板内容', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, state);
    await _menu(tester);
    expect(find.text('自动换行'), findsNothing);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(copies, [state.file['text']]);
    await _menu(tester);
    await tester.tap(find.text('复制路径'));
    await tester.pumpAndSettle();
    expect(copies.last, 'docs/README.md');
    expect(state.calls, [LinkMethods.read]);
  });

  testWidgets('长文件复制内容不截断，也不混入显示行号', (tester) async {
    final original = List.generate(900, (i) => '原文第${i + 1}行').join('\n');
    final state = _State()..file = {'text': original};
    addTearDown(state.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, state, path: 'large.txt');
    await _menu(tester);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(copied, original);
  });

  testWidgets('搜索大小写不敏感、支持前后匹配并定位远处行', (tester) async {
    final state = _State()
      ..file = {
        'text': List.generate(
          500,
          (i) => i == 0 || i == 400 ? 'needle 第${i + 1}行' : '正文第${i + 1}行',
        ).join('\n'),
      };
    addTearDown(state.dispose);
    await _pump(tester, state, path: 'notes.txt');
    await tester.tap(find.byTooltip('搜索文件内容'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NEEDLE');
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一个匹配'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(
      find.textContaining('needle 第401行', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('上一个匹配'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '没有的内容');
    await tester.pumpAndSettle();
    expect(find.text('0 / 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跳到行验证范围，Markdown从预览切到源码并定位实际行', (tester) async {
    final state = _State()
      ..file = {'text': List.generate(600, (i) => '正文第${i + 1}行').join('\n')};
    addTearDown(state.dispose);
    await _pump(tester, state);
    await _menu(tester);
    await tester.tap(find.text('跳到行'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–600 之间的行号'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '589');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBlocks), findsNothing);
    expect(find.textContaining('正文第589行', findRichText: true), findsOneWidget);
    expect(state.calls, [LinkMethods.read]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件字号只影响当前文件，不改全局设置', (tester) async {
    final state = _State()..file = {'text': 'alpha'};
    addTearDown(state.dispose);
    await _pump(tester, state, path: 'test.txt');
    await _menu(tester);
    await tester.tap(find.text('放大字号'));
    await tester.pumpAndSettle();
    final body = tester.widget<Text>(
      find.byKey(const ValueKey('file-source-text-1')),
    );
    expect(body.style!.fontSize, 16);
    expect(state.settings.codeFontSize, 14);
    await _menu(tester);
    await tester.tap(find.text('缩小字号'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('file-source-text-1')))
          .style!
          .fontSize,
      14,
    );
  });

  testWidgets('Markdown差异保留对比和审核入口，切换预览不发写入', (tester) async {
    final state = _State()..file = {'text': '# 新标题', 'original': '# 旧标题'};
    addTearDown(state.dispose);
    await _pump(tester, state);
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.text('保留'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBlocks), findsWidgets);
    expect(find.text('新标题', findRichText: true), findsOneWidget);
    expect(state.calls, [LinkMethods.read]);
  });

  testWidgets('窄屏深色大字号下预览、搜索、操作菜单不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    await _pump(tester, state, brightness: Brightness.dark, textScale: 1.5);
    await _menu(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('跳到行'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索文件内容'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '正文');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
