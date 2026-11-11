import 'dart:convert';

import 'package:bao_link/bao_link.dart';

import '../link/phone_link.dart';
import '../models/session_buffer.dart';

/// Explicit opt-in fixtures. No machine, model, or repository is accessed.
class DemoWorkspace {
  DemoWorkspace() {
    states['demo-desktop'] = {
      'device': {'name': '开发电脑', 'kind': 'windows', 'system': 'Windows 11'},
      'projects': [
        for (final name in ['baocode', 'workspace', 'demo-project'])
          {
            'id': name,
            'name': name,
            'path': 'D:/projects/$name',
            'branch': 'main',
            'pinned': false,
            // Exercise the image-icon path of the demo file list; the id is
            // served by [call] below. The rest keep their folder icon.
            if (name == 'baocode') 'icon': {'type': 'image', 'id': 'demo-icon'},
          },
      ],
      'sessions': [
        for (final name in ['baocode', 'workspace', 'demo-project'])
          {
            'id': 'session-$name',
            'project': name,
            'title': '查看 $name 项目',
            'updated': DateTime.now().millisecondsSinceEpoch,
            'status': 'idle',
          },
      ],
      'bots': [
        {
          'id': 'assistant',
          'name': '小宝',
          'signature': '你的电脑助理',
          'identity': '帮助你照看电脑上的项目。',
          'assistant': true,
          'session': 'bot-assistant',
          'abilities': ['agents', 'browser', 'proactive'],
        },
      ],
    };
    states['demo-laptop'] = {
      'device': {'name': '笔记本', 'kind': 'mac', 'system': 'macOS'},
      'projects': <Object?>[],
      'sessions': <Object?>[],
      'bots': <Object?>[],
    };
    for (final name in ['baocode', 'workspace', 'demo-project', 'assistant']) {
      final id = name == 'assistant' ? 'bot-assistant' : 'session-$name';
      _history[id] = [
        {'t': 'notice', 'kind': 'info', 'text': '演示数据：未连接电脑，不会执行任何命令。'},
        {
          't': 'user',
          'text': '帮我看看这个项目。',
          'at': DateTime.now().millisecondsSinceEpoch,
        },
        {'t': 'thinking', 'text': '先查看文件结构，再整理建议。', 'tokens': 128},
        {
          't': 'tool',
          'kind': 'read',
          'target': 'README.md',
          'status': 'succeeded',
          'output': '# Example project\nThis is a local fixture.',
        },
        {
          't': 'text',
          'text': '这里是**演示会话**，用来检查消息、代码和工具展示。\n\n```dart\nvoid main() {\n  print("Hello, BaoCode");\n}\n```\n\n连接自己的电脑后，这里才会显示真实执行结果。',
        },
      ];
    }
  }

  final desktops = const [
    KeptDesktop(id: 'demo-desktop', name: '开发电脑', publicKey: '', addresses: []),
    KeptDesktop(id: 'demo-laptop', name: '笔记本', publicKey: '', addresses: []),
  ];
  final states = <String, Map<String, Object?>>{};
  final _history = <String, List<Object?>>{};
  final _memory = <String, String>{};
  int _next = 0;

  Map<String, Object?> _state(String desktop) =>
      states[desktop] ?? (throw StateError('Unknown demo desktop'));
  List<Object?> _list(String desktop, String key) =>
      _state(desktop)[key] as List<Object?>;

  Future<Object?> call(
    String desktop,
    String method,
    Map<String, Object?> params,
  ) async {
    final id = params['session'] as String? ?? '';
    switch (method) {
      case LinkMethods.state:
        return _state(desktop);
      case LinkMethods.open:
        final items = _history.putIfAbsent(id, () => []);
        return {
          'session': id,
          'start': 0,
          'count': items.length,
          'items': List<Object?>.of(items),
          'live': false,
          'earlier': false,
          'choices': [
            {
              'kind': 'model',
              'selected': 'demo',
              'options': [
                {'id': 'demo', 'label': '演示 · 不调用模型'},
              ],
            },
            {
              'kind': 'mode',
              'selected': 'default',
              'options': [
                {'id': 'default', 'label': '默认'},
              ],
            },
          ],
          'tasks': [],
          'changes': [],
        };
      case LinkMethods.close:
        return null;
      case LinkMethods.earlier:
        return {'items': [], 'earlier': false};
      case LinkMethods.draft:
        final next = 'draft-${_next++}';
        _history[next] = [];
        _list(desktop, 'sessions').add({
          'id': next,
          'project': params['project'],
          'title': '新对话',
          'updated': DateTime.now().millisecondsSinceEpoch,
          'status': 'idle',
        });
        return {'session': next};
      case LinkMethods.send:
        var session = id;
        if (params['bot'] case final String bot) {
          final bots = _list(desktop, 'bots');
          final value = bots.map(objectMap).firstWhere((b) => b['id'] == bot);
          session = value['session'] as String? ?? 'bot-$bot';
        }
        final items = _history.putIfAbsent(session, () => []);
        items.add({
          't': 'user',
          'text': params['text'],
          'images': params['images'] ?? [],
          'at': DateTime.now().millisecondsSinceEpoch,
        });
        items.add({
          't': 'notice',
          'kind': 'info',
          'text': '演示消息已保留。没有调用模型或执行代码。',
        });
        return {'session': session};
      case LinkMethods.edit:
        final items = _history[id] ?? [];
        final index = params['index'] as int? ?? -1;
        if (index < 0 || index >= items.length) {
          throw const FormatException('Invalid message index');
        }
        items.replaceRange(index, items.length, [
          {'t': 'user', 'text': params['text']},
          {'t': 'notice', 'kind': 'info', 'text': '演示编辑，未执行。'},
        ]);
        return null;
      case LinkMethods.rename:
      case LinkMethods.pin:
        final sessions = _list(desktop, 'sessions');
        final index = sessions.indexWhere((s) => objectMap(s)['id'] == id);
        if (index >= 0) {
          sessions[index] = {
            ...objectMap(sessions[index]),
            if (method == LinkMethods.rename) 'title': params['title'],
            if (method == LinkMethods.pin) 'pinned': params['pinned'],
          };
        }
        return null;
      case LinkMethods.archive:
      case LinkMethods.delete:
        _list(desktop, 'sessions').removeWhere((s) => objectMap(s)['id'] == id);
        if (method == LinkMethods.delete) _history.remove(id);
        return null;
      case LinkMethods.pinProject:
        final projects = _list(desktop, 'projects');
        final index = projects.indexWhere(
          (p) => objectMap(p)['id'] == params['project'],
        );
        if (index >= 0) {
          projects[index] = {
            ...objectMap(projects[index]),
            'pinned': params['pinned'] == true,
          };
        }
        return null;
      case LinkMethods.hideProject:
        _list(
          desktop,
          'projects',
        ).removeWhere((p) => objectMap(p)['id'] == params['project']);
        return null;
      case LinkMethods.files:
        return {
          'paths': [
            'README.md',
            'lib/main.dart',
            'lib/app.dart',
            'test/app_test.dart',
          ],
          'changes': {'lib/main.dart': 'modified'},
        };
      case LinkMethods.folder:
        return {'folders': <String>[], 'files': <String>[]};
      case LinkMethods.read:
        return {
          'text': params['path'] == 'README.md'
              ? '# Demo workspace\n\nLocal fixture only.'
              : 'void main() {\n  print("Hello");\n}\n',
          if (params['path'] == 'lib/main.dart') 'original': 'void main() {}\n',
        };
      case LinkMethods.download:
        return {'data': base64Encode(utf8.encode('Local demo file only.\n'))};
      case LinkMethods.extensions:
        return {
          'items': [
            {
              'name': '示例技能',
              'kind': 'skill',
              'scope': 'user',
              'description': '仅用于演示扩展列表',
            },
          ],
        };
      case LinkMethods.saveBot:
        final bots = _list(desktop, 'bots');
        final botId = params['bot'] as String? ?? 'bot-${_next++}';
        final existing = bots.indexWhere((b) => objectMap(b)['id'] == botId);
        final bot = {
          if (existing >= 0) ...objectMap(bots[existing]),
          ...params,
          'id': botId,
          'session': 'bot-$botId',
        };
        bot.remove('bot');
        if (existing >= 0) {
          bots[existing] = bot;
        } else {
          bots.add(bot);
        }
        return {'bot': bot};
      case LinkMethods.deleteBot:
        if (params['bot'] == 'assistant') {
          throw StateError('The assistant cannot be deleted');
        }
        _list(
          desktop,
          'bots',
        ).removeWhere((b) => objectMap(b)['id'] == params['bot']);
        return null;
      case LinkMethods.clearBotChat:
        _history['bot-${params['bot']}'] = [];
        return null;
      case LinkMethods.botMemory:
        return {
          'text': _memory['${params['bot']}:memory'] ?? '',
          'self': _memory['${params['bot']}:self'] ?? '',
        };
      case LinkMethods.setBotMemory:
      case LinkMethods.setBotSelf:
        _memory['${params['bot']}:${method == LinkMethods.setBotMemory ? 'memory' : 'self'}'] =
            params['text'] as String? ?? '';
        return null;
      case LinkMethods.output:
        return {'text': '演示任务输出，没有执行真实命令。\n'};
      case LinkMethods.watchOutput:
        const text = '演示任务输出，没有执行真实命令。\n';
        return {'text': text, 'offset': text.length};
      case LinkMethods.unwatchOutput:
        return null;
      case LinkMethods.stop:
      case LinkMethods.stopTask:
      case LinkMethods.choose:
      case LinkMethods.answer:
      case LinkMethods.startPlan:
      case LinkMethods.keep:
      case LinkMethods.undo:
      case LinkMethods.setMe:
        return null;
      case LinkMethods.image:
      case LinkMethods.botAvatar:
        throw StateError('This demo fixture contains no image bytes');
      case LinkMethods.icon:
        // One project advertises an image icon; serve a 1x1 PNG so the file
        // list exercises the real fetch-and-cache path in demo mode.
        if (params['id'] == 'demo-icon') {
          return {'data': demoIconPng, 'type': 'image/png'};
        }
        throw StateError('This demo fixture contains no image bytes');
      default:
        throw UnsupportedError('Demo method: $method');
    }
  }
}

/// An 8x8 PNG in the avatars' blue, base64-encoded.
const String demoIconPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGPwrz+IFTEMLQkA3YJjwfl3DNcAAAAASUVORK5CYII=';
