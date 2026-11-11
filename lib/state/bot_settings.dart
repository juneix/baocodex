import 'package:bao_link/bao_link.dart';

import 'session_subscriptions.dart' show SessionRequest;
import 'app_state.dart';
import '../models/user_facing_error.dart';

String botSaveFailureMessage(Object error, String Function(String, String) tr) {
  if (error is UserFacingError) return error.message;
  if (error is LinkRemoteException) {
    return switch (error.code) {
      LinkErrors.unknown || LinkErrors.unsupported => tr(
        '电脑不支持该保存操作，请更新或在电脑端处理。',
        'The desktop does not support this save operation. Update it or edit on the desktop.',
      ),
      LinkErrors.busy => tr(
        '电脑正忙，已拒绝本次保存。',
        'The desktop is busy and rejected this save.',
      ),
      LinkErrors.notFound => tr(
        '电脑找不到该 Bot，已拒绝本次保存。',
        'The desktop could not find this bot and rejected the save.',
      ),
      'bad' => tr(
        '电脑拒绝保存：资料格式无效。',
        'The desktop rejected the save: invalid profile data.',
      ),
      _ => tr(
        '电脑明确返回保存失败，请在电脑端查看原因。',
        'The desktop returned a save failure. Check its details on the desktop.',
      ),
    };
  }
  return tr(
    '保存结果未确认，请核对连接和已保存内容；不会自动重试。',
    'Save result unconfirmed. Check the connection and saved content. No automatic retry.',
  );
}

class BotModeUnconfirmed implements Exception {
  const BotModeUnconfirmed();

  @override
  String toString() => AppState.phrase(
    '电脑未确认该执行模式，请核对已保存的 Bot',
    'The desktop did not confirm the execution mode. Check the saved bot.',
  );
}

/// 创建结果不确定时保留状态，不能把第二次保存误当作另一次创建。
class BotProfileSaver {
  BotProfileSaver({
    required this.request,
    required this.desktopId,
    LinkBot? bot,
  }) : saved = bot;

  final SessionRequest request;
  final String desktopId;
  LinkBot? saved;
  bool creationUnconfirmed = false;
  bool _busy = false;

  String? get botId => saved?.id;
  bool get busy => _busy;

  void useExisting(LinkBot bot) {
    if (_busy || bot.id.isEmpty) throw StateError('无法绑定该 Bot');
    saved = bot;
    creationUnconfirmed = false;
  }

  Future<LinkBot> save(
    Map<String, Object?> fields, {
    required bool chatOnly,
  }) async {
    if (_busy || creationUnconfirmed) {
      throw StateError(
        AppState.phrase('请先核对上次创建结果', 'Check the previous creation first'),
      );
    }
    _busy = true;
    final creating = botId == null;
    final params = {...fields}..remove('bot');
    params.remove('chatOnly');
    if (!creating) params['bot'] = botId;
    if (creating || saved!.chatOnly != chatOnly) params['chatOnly'] = chatOnly;
    try {
      final response = await request(desktopId, LinkMethods.saveBot, params);
      if (response is! Map || response['bot'] is! Map) {
        throw const FormatException('电脑未返回已保存的 Bot');
      }
      final json = Map<String, Object?>.from(response['bot'] as Map);
      if (json['id'] is! String ||
          (json['id'] as String).isEmpty ||
          json['name'] is! String) {
        throw const FormatException('电脑返回的 Bot 身份无效');
      }
      final actual = LinkBot.fromJson(json);
      if (!creating && actual.id != botId) {
        throw const FormatException('电脑返回了其他 Bot');
      }
      saved = actual;
      creationUnconfirmed = false;
      if (params.containsKey('chatOnly') && actual.chatOnly != chatOnly) {
        throw const BotModeUnconfirmed();
      }
      return actual;
    } on LinkRemoteException {
      // 服务器明确拒绝，不把它伪装成成功或接口能力检测结果。
      rethrow;
    } on Object {
      if (creating && saved == null) creationUnconfirmed = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }
}

class BotMemorySaveResult {
  const BotMemorySaveResult({required this.saved, required this.failed});
  final List<String> saved;
  final Map<String, Object> failed;
  bool get complete => failed.isEmpty;
}

/// 两个公开接口是独立写入，分别记录已确认基线，不伪装成原子事务。
class BotMemorySaver {
  BotMemorySaver({
    required this.request,
    required this.desktopId,
    required this.botId,
    required this.memory,
    required this.self,
  });

  final SessionRequest request;
  final String desktopId, botId;
  String memory, self;
  bool _busy = false;

  Future<BotMemorySaveResult> save({
    required String memory,
    required String self,
  }) async {
    if (_busy) throw StateError('正在保存记忆');
    _busy = true;
    final saved = <String>[];
    final failed = <String, Object>{};
    try {
      for (final entry in [
        if (memory != this.memory) (LinkMethods.setBotMemory, memory),
        if (self != this.self) (LinkMethods.setBotSelf, self),
      ]) {
        try {
          await request(desktopId, entry.$1, {'bot': botId, 'text': entry.$2});
          if (entry.$1 == LinkMethods.setBotMemory) {
            this.memory = entry.$2;
          } else {
            this.self = entry.$2;
          }
          saved.add(entry.$1);
        } on Object catch (error) {
          failed[entry.$1] = error;
        }
      }
      return BotMemorySaveResult(saved: saved, failed: failed);
    } finally {
      _busy = false;
    }
  }
}
