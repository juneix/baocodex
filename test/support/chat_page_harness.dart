// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/link/phone_link.dart' show DesktopLinkStatus;
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';

import 'chat_test_state.dart';

import 'package:baocode_mobile/models/user_facing_error.dart';

/// 聊天页测试的状态：记下发出的请求，发送、停止可以挂起或失败。
class ChatPageState extends ChatTestState {
  ChatPageState() : super(zh: false, demo: true);
  final calls = <(String, Map<String, Object?>)>[];
  final opened = <String>[], closed = <String>[];
  String savedDraft = '';
  bool failSend = false;
  Completer<void>? sending;
  bool failStop = false;
  Completer<void>? stopping;
  Completer<void>? opening;
  int outputReads = 0;
  DesktopLinkStatus status = DesktopLinkStatus.offline;
  int retried = 0;
  @override
  DesktopLinkStatus linkStatus(String desktopId) =>
      online ? DesktopLinkStatus.online : status;
  @override
  void retryConnection(String desktopId) => retried++;
  @override
  String draft(String desktopId, String sessionId) => savedDraft;
  @override
  Future<void> setDraft(String desktopId, String sessionId, String text) async {
    savedDraft = text;
  }

  @override
  Future<void> openSession(String desktopId, String sessionId) async {
    opened.add(sessionId);
    await opening?.future;
  }

  @override
  Future<void> closeSession(String desktopId, String sessionId) async {
    closed.add(sessionId);
  }

  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    if (method == LinkMethods.stop) {
      await stopping?.future;
      if (failStop) throw const UserFacingError('stop rejected');
    }
    if (method == LinkMethods.watchOutput) {
      throw const LinkRemoteException(LinkErrors.unknown, '旧端使用轮询');
    }
    if (method == LinkMethods.output) {
      outputReads++;
      return {'text': 'output $outputReads'};
    }
    return null;
  }

  @override
  Future<String?> sendMessage(
    String desktopId, {
    String? session,
    String? project,
    String? bot,
    required String text,
    List<Map<String, Object?>> images = const [],
    List<String> mentions = const [],
    bool now = false,
    String? id,
  }) async {
    calls.add((
      LinkMethods.send,
      {
        'session': session,
        if (now) 'now': true,
        'id': ?id,
        'bot': bot,
        'text': text,
        'images': images,
        'mentions': mentions,
      },
    ));
    await sending?.future;
    if (failSend) throw StateError('offline');
    return bot == null ? session : 'real-bot-session';
  }

  void tail(LinkSessionUpdate update) {
    history.apply(update);
    notifyListeners();
  }
}

class ChineseChatPageState extends ChatPageState {
  @override
  String tr(String zh, String en) => zh;
}

Widget messageHost(ChatPageState state, Object? item) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: MessageView(
        state: state,
        desktopId: 'desktop',
        item: item,
        index: 7,
        projectId: 'project',
      ),
    ),
  ),
);
Widget chatHost(
  ChatPageState state, {
  String session = 'session',
  String? bot,
}) => MaterialApp(
  home: ChatPage(
    state: state,
    desktopId: 'desktop',
    sessionId: session,
    title: 'Conversation',
    projectId: 'project',
    botId: bot,
  ),
);
