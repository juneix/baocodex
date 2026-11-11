import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/chat_output.dart';
import 'package:flutter_test/flutter_test.dart';

List<ChatRow> rows(
  List<Object?> items, {
  bool live = false,
  bool open = false,
}) => foldRows(items, live: live, isOpen: (_) => open);

void main() {
  test('回合统计取自对应用户消息，只挂到最后助手行', () {
    final result = rows([
      const UserMessageItem(
        text: '问题一',
        worked: Duration(seconds: 9),
        usage: TurnUsage(inputTokens: 20, outputTokens: 3, costUsd: .072),
      ),
      const AssistantTextItem('第一段'),
      const ThinkingItem(text: '检查', tokens: 1, seconds: 1),
      const AssistantTextItem('第二段'),
      const UserMessageItem(
        text: '问题二',
        worked: Duration(seconds: 2),
        usage: TurnUsage(outputTokens: 4),
      ),
      const AssistantTextItem('另一轮'),
    ]);
    final footers = result.where((row) => row.footer != null).toList();
    expect(footers, hasLength(2));
    expect(footers.first.index, 3);
    expect(footers.first.footer!.answer, '第一段\n\n第二段');
    expect(footers.first.footer!.usage!.totalTokens, 23);
    expect(footers.last.footer!.usage!.costUsd, isNull);
    expect(footers.last.footer!.answer, '另一轮');
  });

  test('回答后的两条通知不拆散完整回合统计', () {
    final result = rows([
      const UserMessageItem(
        text: '问题',
        worked: Duration(seconds: 9),
        usage: TurnUsage(outputTokens: 12, costUsd: .03),
      ),
      const AssistantTextItem('第一段'),
      const ThinkingItem(text: '检查', tokens: 1, seconds: 1),
      const AssistantTextItem('最终回答'),
      const NoticeItem(NoticeKind.command, 'Set model to 模型甲'),
      const NoticeItem(NoticeKind.command, 'Set model to 模型乙'),
    ]);
    final footers = result.where((row) => row.footer != null).toList();
    expect(footers, hasLength(1));
    expect(footers.single.index, 3);
    expect(footers.single.footer!.answer, '第一段\n\n最终回答');
    expect(footers.single.footer!.worked, const Duration(seconds: 9));
    expect(footers.single.footer!.usage!.costUsd, .03);
    expect(
      result
          .where((row) => row.shown is NoticeItem)
          .every((row) => row.footer == null),
      isTrue,
    );
  });

  test('工具与回答之间的通知不把工具前正文合入答案', () {
    final result = rows([
      const UserMessageItem(text: '问题', worked: Duration(seconds: 9)),
      const AssistantTextItem('工具前正文'),
      const ToolCallItem(
        kind: ToolKind.read,
        target: '文件',
        status: ToolStatus.succeeded,
      ),
      const NoticeItem(NoticeKind.command, 'Set model to 模型甲'),
      const AssistantTextItem('最终回答'),
      const NoticeItem(NoticeKind.command, 'Set model to 模型乙'),
    ]);
    final footer = result.singleWhere((row) => row.footer != null);
    expect(footer.index, 4);
    expect(footer.footer!.answer, '最终回答');
  });

  test('未知占位及轮尾工具仍阻断答案，隐藏行保留唯一统计', () {
    for (final tail in <List<Object?>>[
      [
        {'t': 'future'},
        const NoticeItem(NoticeKind.command, 'Set model to 模型甲'),
      ],
      [
        const ToolCallItem(
          kind: ToolKind.read,
          target: '甲',
          status: ToolStatus.succeeded,
        ),
        const ToolCallItem(
          kind: ToolKind.read,
          target: '乙',
          status: ToolStatus.succeeded,
        ),
      ],
    ]) {
      for (final open in [false, true]) {
        final result = rows([
          const UserMessageItem(text: '问题', worked: Duration(seconds: 3)),
          const AssistantTextItem('回答'),
          ...tail,
        ], open: open);
        // One tail per turn: statistics and the last words together.
        final footer = result.singleWhere((row) => row.footer != null);
        expect(footer.index, 3);
        expect(footer.footer!.worked, const Duration(seconds: 3));
        expect(footer.footer!.answer, '回答');
        if (tail.first is ToolCallItem && !open) {
          expect(footer.showItem, isFalse);
        }
      }
    }
  });

  test('工具前正文不属于最终答案，折叠开合不重复统计', () {
    final items = [
      const UserMessageItem(text: '检查', worked: Duration(seconds: 3)),
      const AssistantTextItem('我先读取'),
      const ToolCallItem(
        kind: ToolKind.read,
        target: 'a',
        status: ToolStatus.succeeded,
      ),
      const ToolCallItem(
        kind: ToolKind.read,
        target: 'b',
        status: ToolStatus.succeeded,
      ),
      const AssistantTextItem('检查完成'),
    ];
    for (final open in [false, true]) {
      final footers = rows(
        items,
        open: open,
      ).where((row) => row.footer != null);
      expect(footers, hasLength(1));
      expect(footers.single.footer!.answer, '检查完成');
    }
  });

  test('隐藏live状态仍有实时统计，没有完成费用', () {
    final result = rows([
      const UserMessageItem(text: '运行中'),
      {'t': 'future', 'value': 'unknown'},
      {
        't': 'live',
        'label': '处理中',
        'visible': false,
        'tokens': 7,
        'speed': 2.5,
        'startedAt': 1000,
      },
    ], live: true);
    final footer = result.last.footer!;
    expect(result.last.index, 2);
    expect(footer.live!.tokens, 7);
    expect(footer.live!.tokensPerSecond, 2.5);
    expect(footer.usage, isNull);
    expect(footer.answer, isNull);
  });

  test('无output但有开始时间仍计时，停下不伪造统计', () {
    final items = [
      const UserMessageItem(text: '执行'),
      {'t': 'live', 'label': '', 'visible': false, 'startedAt': 1000},
    ];
    expect(rows(items, live: true).last.footer!.live!.tokens, 0);
    expect(rows(items).where((row) => row.footer != null), isEmpty);
  });

  test('未知wire占位和编辑后截断不会把旧轮统计挂给新答案', () {
    final before = <Object?>[
      {'t': 'future'},
      {
        't': 'user',
        'text': '第一轮',
        'worked': 9000,
        'usage': {'in': 10, 'out': 2, 'cost': .03},
      },
      {'t': 'text', 'text': '旧答案'},
    ];
    expect(rows(before).last.index, 2);
    expect(rows(before).last.footer!.worked, const Duration(seconds: 9));
    final after = <Object?>[
      before.first,
      {'t': 'user', 'text': '替换问题'},
      {'t': 'text', 'text': '新答案'},
    ];
    // No stale statistics reach the new answer; it only gets copy/quote.
    final footers = rows(after).where((row) => row.footer != null).toList();
    expect(footers.single.footer!.worked, isNull);
    expect(footers.single.footer!.usage, isNull);
    expect(footers.single.footer!.answer, '新答案');
  });
}
