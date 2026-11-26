import 'dart:typed_data';

import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/link/chat_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('整理历史消息不提前解码折叠或屏幕外的图片', () {
    final item = ChatCodec.decode({
      't': 'user',
      'text': '含图片的合成历史',
      'images': [
        {'data': '不是有效的 base64', 'type': 'image/png'},
      ],
    }) as UserMessageItem;
    expect(item.images.single.mediaType, 'image/png');
    // 只有实际取图片时才解码；解码失败仍如实抛出，不吞错误。
    expect(() => item.images.single.bytes, throwsFormatException);
  });

  test('重新同步送来相同图片时用同一份字节，内容不同才换', () {
    Map<String, Object?> message(String data) => {
      't': 'user',
      'text': '图',
      'images': [
        {'data': data, 'type': 'image/png'},
      ],
    };
    Uint8List bytes(String data) => (ChatCodec.decode(
      message(data),
    ) as UserMessageItem).images.single.bytes;
    final first = bytes('AQIDBA==');
    expect(identical(bytes('AQIDBA=='), first), isTrue);
    expect(bytes('BQYHCA=='), [5, 6, 7, 8]);
  });

  test('回合速度保留 wire 数值，缺失时不使用总耗时估算', () {
    for (final speed in <double?>[37.16, null]) {
      final item = ChatCodec.decode({
        't': 'user',
        'text': '问题',
        'worked': 32000,
        'usage': {'in': 200000, 'out': 2070, 'cost': .15, 'speed': ?speed},
      }) as UserMessageItem;
      expect(item.usage!.tokensPerSecond, speed);
      expect(item.usage!.totalTokens, 202070);
      expect((ChatCodec.encode(item)['usage'] as Map)['speed'], speed);
    }
  });

  test('UserMessageItem 编解码保留 stopped、agent、agentSession', () {
    final original = const UserMessageItem(
      text: '子代理指令',
      stopped: true,
      fromAgent: 'agent-123',
      fromSession: 'sess-456',
    );
    final wire = ChatCodec.encode(original);
    expect(wire['stopped'], isTrue);
    expect(wire['agent'], 'agent-123');
    expect(wire['agentSession'], 'sess-456');

    final decoded = ChatCodec.decode(wire) as UserMessageItem;
    expect(decoded.stopped, isTrue);
    expect(decoded.fromAgent, 'agent-123');
    expect(decoded.fromSession, 'sess-456');
  });

  test('AssistantTextItem 解析并分离 reply_suggestion 胶囊', () {
    const raw = '回复内容<reply_suggestion>方案 A</reply_suggestion><reply_suggestion>方案 B</reply_suggestion>';
    final item = AssistantTextItem(raw);
    expect(item.text, '回复内容');
    expect(item.suggestions, ['方案 A', '方案 B']);

    final wire = ChatCodec.encode(item);
    expect(wire['suggest'], ['方案 A', '方案 B']);
    final decoded = ChatCodec.decode(wire) as AssistantTextItem;
    expect(decoded.text, '回复内容');
    expect(decoded.suggestions, ['方案 A', '方案 B']);
  });

  test('AgentItem 编解码保留 ranBefore 耗时', () {
    final agent = const AgentItem(
      description: '子任务',
      duration: Duration(seconds: 12),
      ranBefore: Duration(seconds: 8),
    );
    final wire = ChatCodec.encode(agent);
    expect(wire['ranBefore'], 8000);

    final decoded = ChatCodec.decode(wire) as AgentItem;
    expect(decoded.ranBefore, const Duration(seconds: 8));
  });

  test('NoticeItem 编解码保留 compaction 信息', () {
    const note = CompactionNote(auto: true, before: 1000, after: 200);
    final notice = const NoticeItem(
      NoticeKind.info,
      '已压缩',
      compaction: note,
    );
    final wire = ChatCodec.encode(notice);
    expect(wire['compaction'], isA<Map>());

    final decoded = ChatCodec.decode(wire) as NoticeItem;
    expect(decoded.compaction?.auto, isTrue);
    expect(decoded.compaction?.before, 1000);
    expect(decoded.compaction?.after, 200);
  });

  test('ToolCallItem 编解码保留 sessions 与 handed', () {
    final tool = const ToolCallItem(
      kind: ToolKind.other,
      tool: 'delegate',
      target: 'sub',
      input: {
        'sessionIds': ['s1', 's2'],
        'text': '交接内容',
      },
      status: ToolStatus.succeeded,
    );
    final wire = ChatCodec.encode(tool);
    expect(wire['sessions'], ['s1', 's2']);
    expect(wire['handed'], '交接内容');

    final decoded = ChatCodec.decode(wire) as ToolCallItem;
    expect(decoded.input['sessionIds'], ['s1', 's2']);
    expect(decoded.input['text'], '交接内容');
  });

  test('ChatCodec 提取 bot_suggest 标签候选', () {
    const text = '机器人回答<bot_suggest>好的一起去</bot_suggest><bot_suggest>稍后再说</bot_suggest>';
    final suggestions = ChatCodec.botSuggestions(text);
    expect(suggestions, ['好的一起去', '稍后再说']);
  });
}
