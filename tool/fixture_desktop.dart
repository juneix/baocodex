// 仅合成数据的兼容性宿主，不读取真实项目、不执行命令、不使用中继。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_link/bao_link_io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart tool/fixture_desktop.dart <new-offer-json-path>',
    );
    exitCode = 64;
    return;
  }
  final output = File(arguments.single);
  if (output.existsSync()) {
    throw StateError('Refusing to replace an existing offer');
  }
  final identity = LinkIdentity.generate();
  final node = await IrohLinkNode.bind(
    identity: identity,
    relays: [],
    accept: true,
  );
  final fixture = await FixtureDesktop.start(identity: identity, node: node);
  try {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'uri': fixture.offer.uri,
        'port': (await node.info()).port,
        'desktop': identity.id,
        'note': 'Synthetic UDP fixture without relays; no real projects or commands. The native endpoint binds local network interfaces.',
      }),
    );
    stdout.writeln('FIXTURE_READY ${output.path}');
    await ProcessSignal.sigint.watch().first;
  } finally {
    await fixture.close();
  }
}

/// 与运行时使用相同 v2 RPC，测试可注入内存端点以避免网络副作用。
class FixtureDesktop {
  FixtureDesktop._(this.node, this.offer, this._workspace);

  static Future<FixtureDesktop> start({
    required LinkIdentity identity,
    required LinkNode node,
  }) async {
    final info = await node.info();
    final workspace = _Workspace();
    workspace.device['name'] = '兼容性测试电脑 · ${identity.id.substring(0, 8)}';
    final addrs = [
      if (info.port case final port?) ...['127.0.0.1:$port', '10.0.2.2:$port'],
    ];
    workspace.device['addrs'] = addrs;
    workspace.device['relays'] = <String>[];
    final fixture = FixtureDesktop._(
      node,
      PairingOffer(
        name: workspace.device['name'] as String,
        key: identity.publicKey,
        token: randomBytes(16),
        expires: DateTime.now().add(const Duration(hours: 1)),
        addrs: addrs,
      ),
      workspace,
    );
    fixture._incoming = node.incoming.listen((connection) {
      unawaited(fixture._serve(connection));
    });
    return fixture;
  }

  final LinkNode node;
  final PairingOffer offer;
  final _Workspace _workspace;
  final peers = <LinkPeer>[];
  final calls = <String>[];
  final _trusted = <String>{};
  late final StreamSubscription<LinkConnection> _incoming;

  Future<void> _serve(LinkConnection connection) async {
    final workspace = _workspace;
    LinkPeer? peer;
    void Function()? changed;
    try {
      final client = await LinkPeer.accept(connection);
      peer = client;
      peers.add(client);
      final phone = connection.remote;
      final followed = <String>{};
      final windows = <String, int>{};
      var pairedThisConnection = false;
      var introduced = false;
      changed = () {
        if (!introduced || !_trusted.contains(phone)) return;
        client.emit(LinkEvents.state, workspace.state);
        for (final session in followed) {
          client.emit(
            LinkEvents.session,
            workspace.update(session, windows[session] ?? 0),
          );
        }
      };
      workspace.listeners.add(changed);
      client.onRequest = (method, params) async {
        calls.add(method);
        if (method == LinkMethods.hello) {
          introduced = true;
          if (_trusted.contains(phone)) return {'device': workspace.device};
          if (offer.expiredAt(DateTime.now()) ||
              params['token'] != encodeKey(offer.token)) {
            throw const LinkRemoteException(
              'badToken',
              'Use this fixture run\'s pairing link',
            );
          }
          pairedThisConnection = true;
          return {'device': workspace.device, 'pairing': true};
        }
        if (method == LinkMethods.confirm && pairedThisConnection) {
          _trusted.add(phone);
          return null;
        }
        if (!introduced || !_trusted.contains(phone)) {
          throw const LinkRemoteException('unpaired', 'Confirm pairing first');
        }
        if (method == LinkMethods.unpair) {
          _trusted.remove(phone);
          return null;
        }
        if (method == LinkMethods.open) {
          final session = params['session'] as String;
          workspace.requireSession(session);
          followed.add(session);
          final count = (params['window'] as num?)?.toInt() ?? 0;
          final length = workspace.history[session]!.length;
          windows[session] = count > 0 && length > count ? length - count : 0;
          return workspace.update(session, windows[session]!);
        }
        if (method == LinkMethods.close) {
          followed.remove(params['session']);
          return null;
        }
        if (method == LinkMethods.earlier) {
          final session = params['session'] as String;
          final from = windows[session] ?? 0;
          final count = (params['count'] as num?)?.toInt() ?? 50;
          final start = (from - count).clamp(0, from);
          windows[session] = start;
          return {
            'items': workspace.history[session]!.sublist(start, from),
            'earlier': start > 0,
          };
        }
        final callParams = method == LinkMethods.edit
            ? <String, Object?>{
                ...params,
                // wire 索引相对当前订阅窗口，而不是完整历史。
                'index':
                    (windows[params['session']] ?? 0) +
                    ((params['index'] as num?)?.toInt() ?? -1),
              }
            : params;
        final result = workspace.call(method, callParams);
        if (_Workspace.writes.contains(method)) changed!();
        return result;
      };
      await client.done;
    } on LinkClosedException {
      // 合成宿主关闭或测试主动断线。
    } finally {
      if (changed != null) workspace.listeners.remove(changed);
      if (peer != null) {
        peers.remove(peer);
        await peer.close();
      }
      connection.close();
    }
  }

  Future<void> close() async {
    await _incoming.cancel();
    for (final peer in peers.toList()) {
      await peer.close();
    }
    await node.close();
  }
}

class _Workspace {
  _Workspace() {
    history['fixture-session'] = <Object?>[
      {'t': 'notice', 'kind': 'info', 'text': '本地兼容性测试数据，不会访问真实仓库或调用模型。'},
      {
        // Near the top on purpose: the fixture's history grows across runs
        // (every round appends), and the driver must reach this card without
        // chasing it down an ever-longer list.
        't': 'agent',
        'description': '梳理测试覆盖',
        'id': 'fixture-agent-1',
        'agentType': 'explore',
        'prompt': '检查哪些路径还没有合成测试覆盖。',
        'status': 'succeeded',
        'tokens': 1200,
        'toolUses': 2,
        'model': 'fixture',
        'activity': 'Reading tool/fixture_desktop.dart',
        'duration': 90000,
        'children': [
          {
            't': 'tool',
            'kind': 'read',
            'target': 'tool/fixture_desktop.dart',
            'status': 'succeeded',
          },
        ],
        'result': '合成数据覆盖聊天、任务、文件与审批；子代理详情页由本轮新增。',
      },
      {'t': 'user', 'text': '检查这个示例项目。'},
      {'t': 'thinking', 'text': '这是可折叠的模拟思考块。', 'tokens': 42},
      {
        't': 'tool',
        'kind': 'read',
        'target': 'lib/main.dart',
        'status': 'succeeded',
        'output': 'void main() { print("fixture"); }',
      },
      {
        't': 'tool',
        'kind': 'grep',
        'target': 'print(',
        'status': 'succeeded',
        'results': ['lib/main.dart:1'],
      },
      {'t': 'tool', 'kind': 'listDir', 'target': 'lib', 'status': 'succeeded'},
      {
        't': 'text',
        'text': '**加密连接已建立。**\n\n```dart\nvoid main() {\n  print("fixture");\n}\n```\n\n这是模拟结果，不是智能体实际执行。',
      },
      {
        't': 'terminal',
        'command': 'fixture-only',
        'status': 'succeeded',
        'output': '\u001b[32mPASS\u001b[0m — no command was executed',
      },
      {
        't': 'plan',
        'path': 'fixture://synthetic-project/plan.md',
        'round': 1,
        'title': '测试覆盖计划',
        'text': '## 目标\n\n- 聊天、任务、文件、审批各一条合成链路\n- 子代理与贴纸各一张卡\n\n## 步骤\n\n1. 补齐渲染分支\n2. 跑通端到端',
        'status': 'awaiting',
        'writes': 2,
      },
    ];
    history['fixture-question'] = [
      {'t': 'text', 'text': '这是审批交互测试，不会执行命令。'},
    ];
    history['fixture-long'] = [
      for (var i = 0; i < 120; i++)
        {'t': i.isEven ? 'user' : 'text', 'text': '分页测试消息 ${i + 1}'},
    ];
    history['fixture-bot'] = [
      {'t': 'text', 'text': '<bot_say>你好，我是本地测试助理。</bot_say>'},
    ];
  }
  final history = <String, List<Object?>>{};
  final listeners = <void Function()>[];
  final _names = <String, String>{};
  final _pinned = <String>{};
  final _archived = <String>{};
  final _running = <String>{};
  final _stoppedGoals = <String>{};
  final _memory = <String, String>{};
  final _bots = <Map<String, Object?>>[
    {
      'id': 'fixture-bot',
      'name': '测试助理',
      'assistant': true,
      'session': 'fixture-bot',
      'identity': '用于验证界面的本地 fixture',
      'abilities': ['agents'],
      'signature': '不会执行真实任务',
    },
  ];
  bool waiting = true;
  int next = 0;
  final device = <String, Object?>{
    'name': '兼容性测试电脑',
    'kind': 'windows',
    'system': 'Local test fixture',
    'laptop': true,
  };
  static const writes = {
    LinkMethods.send,
    LinkMethods.edit,
    LinkMethods.rename,
    LinkMethods.pin,
    LinkMethods.archive,
    LinkMethods.answer,
    LinkMethods.choose,
    LinkMethods.stop,
    LinkMethods.stopTask,
    LinkMethods.saveBot,
    LinkMethods.deleteBot,
    LinkMethods.clearBotChat,
    LinkMethods.setBotMemory,
    LinkMethods.setBotSelf,
    LinkMethods.keep,
    LinkMethods.undo,
  };
  Map<String, Object?> get state => {
    'device': device,
    'projects': [
      {
        'id': 'fixture-project',
        'name': '示例项目',
        'path': 'fixture://synthetic-project',
      },
    ],
    'sessions': [
      for (final id in [
        'fixture-session',
        'fixture-question',
        'fixture-long',
        ..._names.keys,
      ])
        if (!_archived.contains(id))
          {
            'id': id,
            'project': 'fixture-project',
            'title':
                _names[id] ??
                (id == 'fixture-question'
                    ? '审批与提问'
                    : id == 'fixture-long'
                    ? '长会话分页'
                    : '聊天与文件预览'),
            'updated': DateTime.now().millisecondsSinceEpoch,
            'status': id == 'fixture-question' && waiting
                ? 'needsInput'
                : _running.contains(id)
                ? 'running'
                : 'idle',
            'pinned': _pinned.contains(id),
          },
    ],
    'bots': _bots,
  };
  void requireSession(String id) {
    if (!history.containsKey(id)) {
      throw const LinkRemoteException('notFound', 'Unknown fixture session');
    }
  }

  Map<String, Object?> update(String session, int from) {
    requireSession(session);
    final items = history[session]!;
    return {
      'session': session,
      'start': 0,
      'count': items.length - from,
      'items': items.sublist(from),
      'live': _running.contains(session),
      'earlier': from > 0,
      if (session == 'fixture-session')
        'goal': {
          'condition': '把示例项目的测试都跑绿，不引入新的失败。',
          'state': _stoppedGoals.contains(session) ? 'stopped' : 'running',
          'reason': '还有 2 个测试未通过；其余全部绿了。',
          'checks': 3,
          'tokens': 5400,
        },
      'choices': [
        {
          'kind': 'model',
          'selected': 'fixture',
          'options': [
            {'id': 'fixture', 'label': 'Fixture · 不调用模型'},
          ],
        },
      ],
      if (session == 'fixture-question' && waiting)
        'interaction': {
          't': 'approval',
          'id': 'fixture-approval',
          'title': '允许模拟操作？',
          'tool': 'Fixture',
          'preview': {
            't': 'command',
            'command': 'fixture-only',
            'description': 'No command will be executed',
          },
        },
      'changes': session == 'fixture-session'
          ? [
              {'path': 'lib/main.dart', 'added': 1, 'removed': 1},
            ]
          : [],
      'tasks': session == 'fixture-session'
          ? [
              {
                'id': 'fixture-task',
                'kind': 'command',
                'description': '模拟任务输出',
                'status': 'succeeded',
                'startedAt': 0,
                'output': true,
              },
            ]
          : [],
    };
  }

  Object? call(String method, Map<String, Object?> p) {
    final session = p['session'] as String?;
    switch (method) {
      case LinkMethods.state:
        return state;
      case LinkMethods.files:
        return {
          'paths': ['README.md', 'lib/main.dart'],
          'changes': {'lib/main.dart': 'modified'},
        };
      case LinkMethods.read:
        if (p['path'] == 'README.md') {
          return {'text': '# Fixture workspace\n\nSynthetic content only.'};
        }
        if (p['path'] == 'lib/main.dart') {
          return {
            'text': 'void main() {\n  print("fixture");\n}\n',
            'original': 'void main() {}\n',
          };
        }
        throw const LinkRemoteException('notFound', 'Unknown fixture file');
      case LinkMethods.extensions:
        return {
          'items': [
            {
              'kind': 'skill',
              'scope': 'user',
              'name': 'fixture-only',
              'description': '本地模拟技能',
            },
          ],
        };
      case LinkMethods.draft:
        final id = 'fixture-draft-${next++}';
        history[id] = [];
        _names[id] = '新建测试会话';
        return {'session': id};
      case LinkMethods.send:
        final id = p['bot'] as String? ?? session ?? 'fixture-session';
        requireSession(id);
        final incoming = p['text'] as String? ?? '';
        history[id]!.add({
          't': 'user',
          'text': incoming,
          'images': p['images'] ?? [],
        });
        if (incoming == 'notify probe') {
          _running.add(id);
          Timer(const Duration(seconds: 2), () {
            _running.remove(id);
            history[id]!.add({
              't': 'text',
              'text': '已收到本地测试消息：$incoming。没有调用模型或执行代码。',
            });
            for (final listener in List.of(listeners)) {
              listener();
            }
          });
          return {'session': id};
        }
        // A sticker message gets a sticker back, so the bot-render path is
        // exercised end to end; everything else keeps the plain receipt.
        // The sticker id is a TOP-LEVEL key on the tool item: that is where
        // ChatCodec's decoder reads it (not inside input).
        if (RegExp(r'^\[Sticker: ([\w-]+)\]$').firstMatch(incoming)
            case final match?) {
          history[id]!.add({
            't': 'tool',
            'kind': 'other',
            'target': '贴纸',
            'status': 'succeeded',
            'sticker': match.group(1),
          });
        } else {
          history[id]!.add({
            't': 'text',
            'text': '已收到本地测试消息：$incoming。没有调用模型或执行代码。',
          });
        }
        return {'session': id};
      case LinkMethods.edit:
        requireSession(session!);
        final index = (p['index'] as num).toInt();
        final items = history[session]!;
        if (index < 0 ||
            index >= items.length ||
            (items[index] as Map)['t'] != 'user') {
          throw const LinkRemoteException('notFound', 'Not a user message');
        }
        items.replaceRange(index, items.length, [
          {
            't': 'user',
            'text': p['text'],
            'images': p['images'] ?? [],
            'mentions': p['mentions'] ?? [],
          },
          {'t': 'text', 'text': '已模拟编辑，未执行代码。'},
        ]);
        return null;
      case LinkMethods.answer:
        if (p['request'] != 'fixture-approval') {
          throw const LinkRemoteException('notFound', 'No such request');
        }
        waiting = false;
        history['fixture-question']!.add({
          't': 'notice',
          'kind': 'info',
          'text': '已收到审批答复，未执行操作。',
        });
        return null;
      case LinkMethods.rename:
        _names[session!] = p['title'] as String;
        return null;
      case LinkMethods.pin:
        if (p['pinned'] == true) {
          _pinned.add(session!);
        } else {
          _pinned.remove(session);
        }
        return null;
      case LinkMethods.archive:
        _archived.add(session!);
        return null;
      case LinkMethods.output:
        return {
          'text': '\u001b[32mPASS\u001b[0m\nLocal fixture output. No command was executed.\n',
        };
      case LinkMethods.botMemory:
        return {
          'text': _memory['${p['bot']}:memory'] ?? '',
          'self': _memory['${p['bot']}:self'] ?? '',
        };
      case LinkMethods.setBotMemory:
      case LinkMethods.setBotSelf:
        _memory['${p['bot']}:${method == LinkMethods.setBotMemory ? 'memory' : 'self'}'] =
            p['text'] as String;
        return null;
      case LinkMethods.saveBot:
        final id = p['bot'] as String? ?? 'fixture-created-${next++}';
        final previous = _bots.indexWhere((bot) => bot['id'] == id);
        final bot = <String, Object?>{
          if (previous >= 0) ..._bots[previous],
          ...p,
          'id': id,
          'session': id,
        }..remove('bot');
        if (previous >= 0) {
          _bots[previous] = bot;
        } else {
          _bots.add(bot);
        }
        history.putIfAbsent(id, () => []);
        return {'bot': bot};
      case LinkMethods.deleteBot:
        if (p['bot'] == 'fixture-bot') {
          throw const LinkRemoteException('unsupported', 'The assistant stays');
        }
        _bots.removeWhere((bot) => bot['id'] == p['bot']);
        return null;
      case LinkMethods.clearBotChat:
        history[p['bot'] as String] = [];
        return null;
      case LinkMethods.stop:
        if (session == null) {
          throw const LinkRemoteException('notFound', 'A session is required');
        }
        requireSession(session);
        _stoppedGoals.add(session);
        _running.remove(session);
        return null;
      case LinkMethods.setMe:
      case LinkMethods.choose:
      case LinkMethods.stopTask:
      case LinkMethods.keep:
      case LinkMethods.undo:
        return null;
      default:
        throw const LinkRemoteException(
          'unknown',
          'This fixture does not implement that method',
        );
    }
  }
}
