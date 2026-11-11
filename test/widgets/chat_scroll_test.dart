import 'dart:async';

import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

class _State extends ChatTestState {
  _State() : super(zh: true);
  int earlierCalls = 0;
  bool failEarlier = false;
  Completer<void>? earlierPending;
  List<Object?>? olderItems;
  final laterPages = <List<Object?>>[];

  @override
  Future<void> loadEarlier(String desktop, String session) async {
    earlierCalls++;
    history.loadingEarlier = true;
    update();
    try {
      await earlierPending?.future;
      if (failEarlier) throw const UserFacingError('历史消息加载失败');
      final page =
          olderItems ??
          [
            for (var i = -15; i < 0; i++)
              {'t': 'text', 'text': '第 $i 段回答\n第二行\n第三行'},
          ];
      if (laterPages.isNotEmpty) olderItems = laterPages.removeAt(0);
      history.prepend({
        'items': page,
        'earlier': !identical(page, olderItems) && olderItems != null,
      });
    } finally {
      history.loadingEarlier = false;
      update();
    }
  }

  @override
  String desktopName(String desktop) => '联调电脑';
}

void _add(_State state, int from, int to) {
  for (var i = from; i < to; i++) {
    state.history.items.add({'t': 'text', 'text': '第 $i 段回答\n第二行\n第三行'});
  }
}

Widget _chat(_State state) => MaterialApp(
  home: ChatPage(
    state: state,
    desktopId: 'desktop',
    sessionId: 'session',
    title: '对话',
  ),
);

/// A message action, read through its tooltip.
class IconButtonLike {
  IconButtonLike(this.tester, this.tooltip);
  final WidgetTester tester;
  final String tooltip;

  bool get enabled =>
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byTooltip(tooltip),
              matching: find.byType(InkWell),
            ),
          )
          .onTap !=
      null;
}

void main() {
  const previousMine = '上一条我发的消息';
  const nextMine = '下一条我发的消息';

  void expectShown(WidgetTester tester, String text) {
    final list = tester.getRect(find.byType(CustomScrollView));
    final y = tester.getTopLeft(find.text(text)).dy;
    expect(y, greaterThanOrEqualTo(list.top), reason: text);
    expect(y, lessThan(list.center.dy), reason: text);
  }

  testWidgets('自己发的消息可以跳到上一条、下一条，隔着很长的回答也到得了', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    final long = List.filled(120, '很长的回答').join('\n');
    for (var i = 0; i < 4; i++) {
      state.history.items.addAll([
        {'t': 'user', 'text': '问题 $i'},
        {'t': 'text', 'text': i == 3 ? '短回答' : long},
      ]);
    }
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(find.text('问题 2'), findsNothing);

    IconButtonLike button(String tooltip) => IconButtonLike(tester, tooltip);
    expect(button(nextMine).enabled, isFalse);

    for (final target in ['问题 2', '问题 1', '问题 0']) {
      await tester.tap(find.byTooltip(previousMine));
      await tester.pumpAndSettle();
      expectShown(tester, target);
    }
    expect(button(previousMine).enabled, isFalse);

    await tester.tap(find.byTooltip(nextMine));
    await tester.pumpAndSettle();
    expectShown(tester, '问题 1');
    expect(tester.takeException(), isNull);
  });

  _State earlierChat({List<Object?>? older}) {
    final state = _State()
      ..olderItems =
          older ??
          [
            {'t': 'user', 'text': '更早的问题'},
            {'t': 'text', 'text': List.filled(120, '更早的回答').join('\n')},
          ];
    state.history
      ..earlier = true
      ..items.addAll([
        {'t': 'user', 'text': '现在的问题'},
        {'t': 'text', 'text': '短回答'},
      ]);
    return state;
  }

  testWidgets('上一条还没加载时提前取好，点了直接跳过去', (tester) async {
    final state = earlierChat();
    addTearDown(state.dispose);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1, reason: '不用等点击');
    expect(find.byTooltip(previousMine), findsOneWidget);

    await tester.tap(find.byTooltip(previousMine));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    expectShown(tester, '更早的问题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('还在加载时点上一条，加载完自动跳；尾部同时来了新内容也不错位', (tester) async {
    final state = earlierChat()..earlierPending = Completer<void>();
    addTearDown(state.dispose);
    await tester.pumpWidget(_chat(state));
    await tester.pump();
    await tester.pump();
    expect(state.earlierCalls, 1);

    await tester.tap(find.byTooltip(previousMine));
    await tester.pump();
    state.history.items.add({'t': 'text', 'text': '刚流入的内容'});
    state.update();
    await tester.pump();
    state.earlierPending!.complete();
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    expectShown(tester, '更早的问题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('一页里没有自己的消息时继续往前取，直到取到', (tester) async {
    final state = earlierChat(
      older: [
        {'t': 'text', 'text': '这一页只有回答'},
      ],
    );
    addTearDown(state.dispose);
    state.laterPages.add([
      {'t': 'user', 'text': '再早一页的问题'},
      {'t': 'text', 'text': List.filled(120, '回答').join('\n')},
    ]);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 2);

    await tester.tap(find.byTooltip(previousMine));
    await tester.pumpAndSettle();
    expectShown(tester, '再早一页的问题');
  });

  testWidgets('提前加载不打断跟随：停在底部仍跟着新内容走', (tester) async {
    final state = earlierChat();
    addTearDown(state.dispose);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    state.history.items.add({
      't': 'text',
      'text': List.filled(120, '新内容').join('\n'),
    });
    state.update();
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('提前加载失败不反复重试，断线时也不取', (tester) async {
    final failing = earlierChat()..failEarlier = true;
    addTearDown(failing.dispose);
    await tester.pumpWidget(_chat(failing));
    await tester.pumpAndSettle();
    failing.update();
    await tester.pumpAndSettle();
    expect(failing.earlierCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());

    final offline = earlierChat()..online = false;
    addTearDown(offline.dispose);
    await tester.pumpWidget(_chat(offline));
    await tester.pumpAndSettle();
    expect(offline.earlierCalls, 0);
  });

  testWidgets('打开长对话时列表到底部才显示，看不到从顶上滚下来', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    _add(state, 0, 60);
    await tester.pumpWidget(_chat(state));
    double opacity() => tester
        .widget<Opacity>(find.byKey(const ValueKey('history-reveal')))
        .opacity;
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(opacity(), 0);
    for (var frame = 0; frame < 30 && opacity() == 0; frame++) {
      await tester.pump();
    }
    expect(opacity(), 1);
    expect(position().pixels, position().maxScrollExtent);
    expect(find.textContaining('第 59 段回答'), findsOneWidget);
  });

  testWidgets('打开时只有最早的消息离屏幕远，就不提前加载', (tester) async {
    final state = earlierChat();
    addTearDown(state.dispose);
    state.history.items.insert(1, {
      't': 'text',
      'text': List.filled(200, '长回答').join('\n'),
    });
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跳转途中手动滑动，跳转就停下，不再把列表拉走', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    final long = List.filled(400, '很长的回答').join('\n');
    state.history.items.addAll([
      {'t': 'user', 'text': '远处的问题'},
      {'t': 'text', 'text': long},
      {'t': 'user', 'text': '现在的问题'},
      {'t': 'text', 'text': '短回答'},
    ]);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(previousMine));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(find.text('远处的问题'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有一条自己的消息时不显示跳转', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {'t': 'user', 'text': '唯一的问题'},
      {'t': 'text', 'text': '回答'},
    ]);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(find.byTooltip(previousMine), findsNothing);
    expect(find.byTooltip(nextMine), findsNothing);
    expect(find.byTooltip('复制'), findsWidgets);
  });

  testWidgets('展开多文件修改时折叠标题与首个文件共用历史索引也不会冲突', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history
      ..live = true
      ..items.addAll([
        for (var i = 0; i < 3; i++)
          {
            't': 'diff',
            'fileName': 'file-$i.dart',
            'directory': 'lib',
            'added': 1,
            'removed': 0,
            'lines': <Object?>[],
          },
      ]);
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    final fold = find.byKey(const ValueKey('edits-0'));
    expect(fold, findsOneWidget);
    await tester.tap(
      find.descendant(of: fold, matching: find.textContaining('3 次')).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey(0)), findsOneWidget);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    await tester.tap(
      find.descendant(of: fold, matching: find.textContaining('3 次')).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上滑接近顶部自动加载一页，加载中不重复请求且保留阅读位置', (tester) async {
    final state = _State()..earlierPending = Completer<void>();
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.earlier = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    expect(find.text('加载更早消息'), findsNothing);
    expect(state.earlierCalls, 0);
    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    expect(find.text('加载中…'), findsOneWidget);
    await tester.drag(list, const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    final before = tester.getTopLeft(find.byKey(const ValueKey(0))).dy;
    state.earlierPending!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(15))).dy,
      closeTo(before, 2),
    );
    expect(state.history.items.length, 45);
    expect(find.text('加载中…'), findsNothing);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待期间继续阅读且收到新输出，插入不同高度的历史仍保持当前位置', (tester) async {
    final state = _State()
      ..earlierPending = Completer<void>()
      ..olderItems = [
        for (var i = 0; i < 15; i++)
          {
            't': 'text',
            'text':
                '旧消息 $i\n${List.filled(i.isEven ? 1 : 7, '历史内容').join('\n')}',
          },
      ];
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.earlier = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    state.history.items.add({'t': 'text', 'text': '正在生成的新输出'});
    state.update();
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey(2))).dy;
    state.earlierPending!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(17))).dy,
      closeTo(before, 2),
    );
    expect(state.earlierCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('惯性滑动中加载到很高的一页：内容不跳、滑动不被打断', (tester) async {
    final state = _State()
      ..earlierPending = Completer<void>()
      ..olderItems = [
        for (var i = 0; i < 50; i++)
          {'t': 'text', 'text': List.filled(30, '很高的历史 $i').join('\n')},
      ];
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.earlier = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    final list = find.byType(CustomScrollView);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.fling(list, const Offset(0, 200), 700);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    final moving = position.pixels;
    expect(position.isScrollingNotifier.value, isTrue);

    state.earlierPending!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(state.history.items.length, 80);
    expect(position.isScrollingNotifier.value, isTrue);
    expect(position.pixels, lessThanOrEqualTo(moving));
    expect(position.maxScrollExtent - position.pixels, greaterThan(100));

    await tester.pumpAndSettle();
    expect(find.text('加载中…'), findsNothing);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(find.textContaining('很高的历史'), findsWidgets);
  });

  testWidgets('历史加载失败停止自动重试，点击重试后才重新加载', (tester) async {
    final state = _State()..failEarlier = true;
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.earlier = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('历史消息加载失败'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 1);
    state.failEarlier = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 2);
    expect(state.history.items.length, 45);
    expect(find.text('重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('断线时上滑不请求历史消息', (tester) async {
    final state = _State()..online = false;
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.earlier = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(state.earlierCalls, 0);
    expect(tester.takeException(), isNull);
  });

  group('运行中往回看', () {
    Future<(_State, ScrollPosition Function())> running(
      WidgetTester tester,
    ) async {
      final state = _State();
      addTearDown(state.dispose);
      state.history.items.add({'t': 'user', 'text': '运行中的问题'});
      for (var i = 0; i < 16; i++) {
        _add(state, i, i + 1);
        state.history.items.add({
          't': 'bash',
          'id': 'command-$i',
          'command': 'command $i',
          'output': 'line',
          'exit': 0,
        });
      }
      state.history.live = true;
      await tester.pumpWidget(_chat(state));
      await tester.pumpAndSettle();
      return (
        state,
        () => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position,
      );
    }

    void finishTurn(_State state) {
      state.history.items[0] = {'t': 'user', 'text': '运行中的问题', 'worked': 5000};
      state.history.items.add({'t': 'text', 'text': '最终回答'});
    }

    testWidgets('只往上拉一点也不被拉回，往下回到底部才重新跟随', (tester) async {
      final (state, position) = await running(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 80));
      await tester.pumpAndSettle();
      final held = position().pixels;
      expect(position().maxScrollExtent - held, greaterThan(16));
      _add(state, 30, 34);
      state.update();
      await tester.pumpAndSettle();
      expect(position().pixels, held);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      _add(state, 34, 38);
      state.update();
      await tester.pumpAndSettle();
      expect(position().pixels, position().maxScrollExtent);
    });

    testWidgets('回合结束不收起、不被顶到底部，点回到底部才收起', (tester) async {
      final (state, position) = await running(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      final held = position().pixels;
      final length = position().maxScrollExtent;

      finishTurn(state);
      state.history.live = false;
      state.update();
      await tester.pumpAndSettle();
      expect(position().pixels, held);
      expect(position().maxScrollExtent, greaterThanOrEqualTo(length));

      await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
      await tester.pumpAndSettle();
      expect(position().maxScrollExtent, lessThan(length));
      expect(position().pixels, position().maxScrollExtent);
      expect(find.text('最终回答'), findsOneWidget);
    });

    testWidgets('下一条开始时上一回合也不收起', (tester) async {
      final (state, position) = await running(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      final held = position().pixels;

      finishTurn(state);
      state.history.items.add({'t': 'user', 'text': '排队的下一条'});
      state.update();
      await tester.pumpAndSettle();
      expect(position().pixels, held);
    });
  });

  testWidgets('生成中用户上翻不被拉回，回到底部按钮恢复跟随', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    _add(state, 0, 30);
    state.history.live = true;
    await tester.pumpWidget(_chat(state));
    await tester.pumpAndSettle();
    final list = find.byType(CustomScrollView);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position().pixels, position().maxScrollExtent);
    expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);
    // Hidden (and inert) while at the end.
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('scroll-to-bottom')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    final held = position().pixels;
    expect(held, lessThan(position().maxScrollExtent - 100));

    _add(state, 30, 36);
    state.update();
    await tester.pumpAndSettle();
    expect(position().pixels, held);
    _add(state, 36, 40);
    state.update();
    await tester.pumpAndSettle();
    expect(position().pixels, held);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('scroll-to-bottom')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
    await tester.pumpAndSettle();
    expect(position().pixels, position().maxScrollExtent);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('scroll-to-bottom')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    _add(state, 40, 46);
    state.update();
    await tester.pumpAndSettle();
    expect(position().pixels, position().maxScrollExtent);
  });
}
