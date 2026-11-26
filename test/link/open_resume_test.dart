import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _encode(Map<String, Object?> message) =>
    Uint8List.fromList(utf8.encode(jsonEncode(message)));

/// 电脑端带 `have` 续传时，open 的应答可能从中间开始（start > 0）。
/// peer 必须把它还原成完整快照再交给 App，否则 App 按快照校验会抛
/// FormatException，界面上就是「电脑返回的内容无法识别」的误报。
void main() {
  test('open 应答从中间开始时，还原成 start=0 的完整快照', () async {
    final (client, server) = MemoryLinkConnection.pair();
    final mirror = LinkSessionMirror();
    // 先放一份上次的基线，让 have 有内容可发。
    mirror.keep('会话', [
      {'t': 'user', 'text': '第一句'},
      {'t': 'text', 'text': '第二句'},
    ]);
    final phone = await LinkPeer.connect(client, mirror: mirror);
    final control = await server.incoming.first;
    addTearDown(phone.close);

    final opening = phone.call(LinkMethods.open, {'session': '会话'});
    // 电脑只回第二句之后的部分：start = 1。
    await control.send(
      _encode({
        'id': 1,
        'r': {
          'session': '会话',
          'start': 1,
          'count': 2,
          'items': [
            {'t': 'text', 'text': '第二句'},
          ],
        },
      }),
    );

    final answer = await opening;
    expect(answer, isA<Map>(), reason: '必须给出可用的快照，不能是 null');
    final snapshot = answer as Map;
    expect(snapshot['start'], 0, reason: '交给 App 的一律从 0 开始');
    expect(
      [for (final item in snapshot['items'] as List) (item as Map)['text']],
      ['第一句', '第二句'],
      reason: '手机已有的前缀补回来，App 才认得出这是完整快照',
    );
  });

  test('摘要对不上基线时给出 null 并推 resync，不把半截数据当成快照', () async {
    final (client, server) = MemoryLinkConnection.pair();
    final mirror = LinkSessionMirror();
    mirror.keep('会话', [
      {'t': 'user', 'text': '手机里有的一句'},
    ]);
    final phone = await LinkPeer.connect(client, mirror: mirror);
    final control = await server.incoming.first;
    addTearDown(phone.close);
    final events = <LinkEvent>[];
    final subscription = phone.events.listen(events.add);
    addTearDown(subscription.cancel);

    final opening = phone.call(LinkMethods.open, {'session': '会话'});
    // start 越过了手机有的条目：基线对不上。
    await control.send(
      _encode({
        'id': 1,
        'r': {
          'session': '会话',
          'start': 5,
          'count': 6,
          'items': [
            {'t': 'text', 'text': '别的'},
          ],
        },
      }),
    );

    expect(await opening, isNull, reason: '半截数据不能交给 App 当快照');
    expect(
      events.map((event) => event.name),
      contains(LinkEvents.resync),
      reason: '要让 App 重新打开一次，而不是报「无法识别」',
    );
  });
}
