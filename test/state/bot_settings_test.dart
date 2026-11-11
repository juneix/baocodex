import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/bot_settings.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _CreationState extends AppState {
  _CreationState() : super(store: MemoryLinkStore());
  int writes = 0;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    writes++;
    throw TimeoutException('合成超时');
  }
}

void main() {
  test('创建未确认状态按电脑由 AppState 持有，不随编辑页面退出丢失', () async {
    final state = _CreationState();
    addTearDown(state.dispose);
    final firstPage = state.botProfileSaver('a');
    await expectLater(
      firstPage.save({'name': '助手'}, chatOnly: true),
      throwsA(isA<TimeoutException>()),
    );
    final reopenedPage = state.botProfileSaver('a');
    expect(reopenedPage, same(firstPage));
    expect(reopenedPage.creationUnconfirmed, isTrue);
    await expectLater(
      reopenedPage.save({'name': '助手'}, chatOnly: true),
      throwsStateError,
    );
    expect(state.writes, 1);
    expect(state.botProfileSaver('b'), isNot(same(firstPage)));
  });
  test('新建明确提交执行模式，返回的实际模式不符合时只更新已创建对象', () async {
    final calls = <Map<String, Object?>>[];
    final saver = BotProfileSaver(
      request: (_, method, params) async {
        calls.add(params);
        return {
          'bot': {'id': 'created', 'name': '助手'},
        };
      },
      desktopId: 'a',
    );
    await expectLater(
      saver.save({'name': '助手'}, chatOnly: true),
      throwsA(isA<BotModeUnconfirmed>()),
    );
    expect(saver.botId, 'created');
    expect(saver.saved!.chatOnly, isFalse);
    await expectLater(
      saver.save({'name': '助手'}, chatOnly: true),
      throwsA(isA<BotModeUnconfirmed>()),
    );
    expect(calls.first['chatOnly'], isTrue);
    expect(calls.last['bot'], 'created');
  });

  test('普通资料修改不重写已有模式，false 缺字段遵循官方序列化', () async {
    Map<String, Object?>? sent;
    final saver = BotProfileSaver(
      request: (_, _, params) async {
        sent = params;
        return {
          'bot': {'id': 'b', 'name': '改名'},
        };
      },
      desktopId: 'a',
      bot: const LinkBot(id: 'b', name: '原名'),
    );
    final saved = await saver.save({'name': '改名'}, chatOnly: false);
    expect(saved.chatOnly, isFalse);
    expect(sent!.containsKey('chatOnly'), isFalse);
    expect(sent!['bot'], 'b');
  });

  test('创建超时不自动再次 create，必须由用户核对已有身份', () async {
    var writes = 0;
    final saver = BotProfileSaver(
      request: (_, _, _) async {
        writes++;
        throw TimeoutException('合成超时');
      },
      desktopId: 'a',
    );
    await expectLater(
      saver.save({'name': '助手'}, chatOnly: false),
      throwsA(isA<TimeoutException>()),
    );
    expect(saver.creationUnconfirmed, isTrue);
    await expectLater(
      saver.save({'name': '助手'}, chatOnly: false),
      throwsStateError,
    );
    expect(writes, 1);
    saver.useExisting(const LinkBot(id: 'chosen', name: '助手', chatOnly: true));
    expect(saver.creationUnconfirmed, isFalse);
    expect(saver.botId, 'chosen');
  });

  test('明确不支持的创建不误报成功或吞掉远程错误', () async {
    final saver = BotProfileSaver(
      request: (_, _, _) async =>
          throw const LinkRemoteException(LinkErrors.unsupported, '旧端'),
      desktopId: 'a',
    );
    await expectLater(
      saver.save({'name': '助手'}, chatOnly: true),
      throwsA(isA<LinkRemoteException>()),
    );
    expect(saver.saved, isNull);
    expect(saver.creationUnconfirmed, isFalse);
  });

  test('明确拒绝和网络未确认分开说明，不回显不可信服务端消息', () {
    String zh(String zh, String _) => zh;
    final rejected = botSaveFailureMessage(
      const LinkRemoteException(
        LinkErrors.unsupported,
        'synthetic-private-error',
      ),
      zh,
    );
    expect(rejected, contains('不支持'));
    expect(rejected, isNot(contains('未确认')));
    expect(rejected, isNot(contains('synthetic-private-error')));
    expect(
      botSaveFailureMessage(TimeoutException('合成超时'), zh),
      contains('未确认'),
    );
  });

  test('记忆只保存变化项，部分成功后下次不重复已确认项', () async {
    final methods = <String>[];
    var failSelf = true;
    final saver = BotMemorySaver(
      request: (_, method, _) async {
        methods.add(method);
        if (method == LinkMethods.setBotSelf && failSelf) {
          throw StateError('合成失败');
        }
        return null;
      },
      desktopId: 'a',
      botId: 'b',
      memory: '旧记忆',
      self: '旧备注',
    );
    final first = await saver.save(memory: '新记忆', self: '新备注');
    expect(first.saved, [LinkMethods.setBotMemory]);
    expect(first.failed.keys, [LinkMethods.setBotSelf]);
    expect(saver.memory, '新记忆');
    expect(saver.self, '旧备注');
    failSelf = false;
    final next = await saver.save(memory: '新记忆', self: '新备注');
    expect(next.complete, isTrue);
    expect(methods, [
      LinkMethods.setBotMemory,
      LinkMethods.setBotSelf,
      LinkMethods.setBotSelf,
    ]);
    methods.clear();
    await saver.save(memory: '新记忆', self: '新备注');
    expect(methods, isEmpty);
  });
}
