import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/tasks/model_settings_sheet.dart';
import 'package:baocode_mobile/ui/widgets/scale_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const models = LinkChoice(
  kind: 'model',
  selected: 'a',
  options: [
    LinkOption(id: 'a', label: '模型甲', groupLabel: '提供方'),
    LinkOption(id: 'b', label: '模型乙', groupLabel: '提供方'),
  ],
);
const contextChoice = LinkChoice(
  kind: 'context',
  selected: '1m',
  options: [
    LinkOption(id: '272k', label: '272K'),
    LinkOption(id: '1m', label: '1M'),
  ],
);
const effort = LinkChoice(
  kind: 'effort',
  selected: 'high',
  options: [
    LinkOption(id: 'low', label: 'Low'),
    LinkOption(id: 'medium', label: 'Medium'),
    LinkOption(id: 'high', label: 'High'),
    LinkOption(id: 'xhigh', label: 'X-High'),
    LinkOption(id: 'max', label: 'Max'),
    LinkOption(id: 'ultra', label: 'Ultra'),
  ],
);

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  final history = SessionBuffer('desktop', 'session')
    ..choices = [models, contextChoice, effort];
  final calls = <Map<String, Object?>>[];
  int quotaCalls = 0;
  bool online = true, fail = false;
  Completer<void>? pending;
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => online;
  @override
  SessionBuffer buffer(String desktopId, String sessionId) => history;
  @override
  SessionBuffer? peekBuffer(String desktopId, String sessionId) => history;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    expect(desktopId, 'desktop');
    if (method == LinkMethods.quota) {
      quotaCalls++;
      expect(params.containsKey('provider'), isFalse);
      return {'providers': []};
    }
    expect(method, LinkMethods.choose);
    calls.add(params);
    await pending?.future;
    if (fail) throw const UserFacingError('设置被拒绝');
    return null;
  }

  void update(List<LinkChoice> choices) {
    history.choices = choices;
    notifyListeners();
  }
}

Widget host(
  AppState state, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: MobileTheme.build(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: ModelSettingsSheet(
        state: state,
        desktopId: 'desktop',
        sessionId: 'session',
      ),
    ),
  ),
);

Future<void> expandSettings(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ListTile, '模型甲'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('同一模型弹窗多个分组只请求一次额度，普通标题保持纯文字', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'model',
        selected: 'a',
        options: [
          LinkOption(
            id: 'a',
            label: '模型甲',
            group: 'chatgpt',
            groupLabel: 'ChatGPT',
          ),
          LinkOption(id: 'b', label: '模型乙', group: 'acme', groupLabel: 'acme'),
        ],
      ),
    ];
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(state.quotaCalls, 1);
    expect(find.text('acme'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'acme'), findsNothing);
    expect(find.byTooltip('刷新额度'), findsNothing);
    await tester.enterText(find.byType(TextField), '模型');
    await tester.pumpAndSettle();
    expect(state.quotaCalls, 1);
  });
  testWidgets('默认折叠，点击选中模型开合不发送请求，重开恢复折叠', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await expandSettings(tester);
    expect(find.text('推理强度'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await expandSettings(tester);
    expect(find.byType(ChoiceChip), findsNothing);
    await expandSettings(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(state));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(state.calls, isEmpty);
  });
  testWidgets('上下文和推理强度都是滑块，窄屏大字号不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      host(state, brightness: Brightness.dark, scale: 1.4),
    );
    await tester.pumpAndSettle();
    await expandSettings(tester);
    expect(find.text('上下文'), findsOneWidget);
    expect(find.text('推理强度'), findsOneWidget);
    // 档位多少都一样：一格一档的滑块，当前档写在标题右边，首尾两档在轨道下面。
    for (final kind in ['context', 'effort']) {
      expect(find.byKey(ValueKey('$kind:slider')), findsOneWidget);
      expect(find.byKey(ValueKey('$kind:value')), findsOneWidget);
    }
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context:value'))).data,
      '1M',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('effort:value'))).data,
      'High',
    );
    // 首尾两档都露在外面，名字完整不省略；当前档与末档同名时就出现两次。
    for (final label in ['272K', 'Low', 'Ultra']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('1M'), findsNWidgets(2));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖一个滑块时另一个不跟着动', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await expandSettings(tester);
    // 按住上下文拖到最左，还没松手：只是先显示，推理强度不能读到它的值。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('context:slider'))),
    );
    await gesture.moveBy(const Offset(-400, 0));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context:value'))).data,
      '272K',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('effort:value'))).data,
      'High',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('effort:value'))).data,
      'High',
    );
  });

  testWidgets('键盘占位时内容仍可滚动、完整选项可达', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: 360),
            ),
            child: ModelSettingsSheet(
              state: state,
              desktopId: 'desktop',
              sessionId: 'session',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expandSettings(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('effort:slider')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('effort:slider')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置请求带会话且按桌面新快照更新选中态，弹层不关闭', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await expandSettings(tester);
    // 上下文拖到最左（272K）才发。
    await tester.drag(
      find.byKey(const ValueKey('context:slider')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(state.calls.single, {
      'session': 'session',
      'kind': 'context',
      'option': '272k',
    });
    // Request completion alone is not an optimistic selection:
    // 请求回来前，滑块跟着手指停在 272K，但电脑上还没换成这一档。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context:value'))).data,
      '272K',
    );
    state.update([
      models,
      LinkChoice(
        kind: 'context',
        selected: '272k',
        options: contextChoice.options,
      ),
      effort,
    ]);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context:value'))).data,
      '272K',
    );
    // 推理强度是一格一档的滑块：拖到最右一档才发，拖的路上不发。
    await tester.drag(
      find.byKey(const ValueKey('effort:slider')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(state.calls.last, {
      'session': 'session',
      'kind': 'effort',
      'option': 'ultra',
    });
    expect(find.byType(ModelSettingsSheet), findsOneWidget);
  });

  testWidgets('换到另一个上游的模型先问一声，取消不发，切换才发', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.add({'t': 'user', 'text': '你好'});
    state.history.choices = [
      const LinkChoice(
        kind: 'model',
        selected: '@a/claude-sonnet',
        options: [
          LinkOption(
            id: '@a/claude-sonnet',
            label: 'Claude',
            group: 'a',
            groupLabel: '上游甲',
          ),
          LinkOption(
            id: '@b/deepseek-v3',
            label: 'DeepSeek',
            group: 'b',
            groupLabel: '上游乙',
          ),
        ],
      ),
    ];
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'DeepSeek'));
    await tester.pumpAndSettle();
    // 电脑要重启 Claude Code 接续对话，先说清楚。
    expect(find.text('切换到 上游乙？'), findsOneWidget);
    expect(find.textContaining('--resume'), findsOneWidget);
    // 和电脑端同一句：还有回复在进行，发下一条时会先停掉。
    expect(find.textContaining('发送下一条消息时会先停止它'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    expect(find.text('切换到 上游乙？'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '切换'));
    await tester.pumpAndSettle();
    expect(state.calls.single, {
      'session': 'session',
      'kind': 'model',
      'option': '@b/deepseek-v3',
    });
  });

  testWidgets('同一上游内换模型不问，对话还没开始时也不问', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'model',
        selected: '@a/claude-sonnet',
        options: [
          LinkOption(id: '@a/claude-sonnet', label: 'Claude', group: 'a'),
          LinkOption(id: '@a/claude-opus', label: 'Opus', group: 'a'),
          LinkOption(id: '@b/deepseek-v3', label: 'DeepSeek', group: 'b'),
        ],
      ),
    ];
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Opus'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    // 没开始过的对话：换上游也不用重启，直接发。
    await tester.tap(find.widgetWithText(ListTile, 'DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.calls.map((call) => call['option']), [
      '@a/claude-opus',
      '@b/deepseek-v3',
    ]);
  });

  testWidgets('切换模型等新快照，不复用旧模型的设置', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await expandSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, '模型乙'));
    await tester.pump();
    expect(state.calls.single['kind'], 'model');
    expect(find.text('正在更新设置…'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    state.update([
      LinkChoice(kind: 'model', selected: 'b', options: models.options),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('正在更新设置…'), findsNothing);
    expect(find.text('推理强度'), findsNothing);
  });

  testWidgets('失败留在弹层，不改选中态、不自动重试，离线禁用', (tester) async {
    final state = _State()..fail = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await expandSettings(tester);
    // 滑块拖到最左一档：发出去，被拒，滑回电脑上仍选着的 High。
    await tester.drag(
      find.byKey(const ValueKey('effort:slider')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('设置被拒绝'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('effort:value'))).data,
      'High',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(state.calls, hasLength(1));
    state.online = false;
    state.update(state.history.choices);
    await tester.pump();
    // 离线时滑块不再能动。
    expect(
      tester
          .widget<ScaleSlider>(find.byKey(const ValueKey('effort:slider')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('搜索不误发请求，空结果有反馈，快速按toggle协议发送', (tester) async {
    final state = _State();
    state.history.choices = [
      models,
      const LinkChoice(
        kind: 'fast',
        options: [LinkOption(id: 'fast', label: 'Fast')],
      ),
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await expandSettings(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(state.calls.single, {
      'session': 'session',
      'kind': 'fast',
      'option': 'fast',
    });
    await tester.enterText(find.byType(TextField), '不存在的模型');
    await tester.pump();
    expect(find.text('没有匹配模型'), findsOneWidget);
    expect(state.calls, hasLength(1));
  });
}
