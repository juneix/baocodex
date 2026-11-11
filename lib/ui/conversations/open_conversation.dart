import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../tasks/chat_page.dart';
import '../widgets/mobile_widgets.dart';

class ConversationDestination {
  const ConversationDestination({
    required this.sessionId,
    required this.title,
    this.projectId,
    this.projectUnavailable = false,
  });
  final String sessionId, title;
  final String? projectId;
  final bool projectUnavailable;
}

ConversationDestination resolveConversation(
  AppState state, {
  required String desktopId,
  required String sessionId,
}) {
  if (sessionId.isEmpty) throw const FormatException('没有可打开的会话');
  final session = state.sessions
      .where((ref) => ref.desktopId == desktopId && ref.session.id == sessionId)
      .firstOrNull;
  final project = state.projects
      .where(
        (ref) =>
            ref.desktopId == desktopId &&
            ref.project.id == session?.session.project,
      )
      .firstOrNull;
  return ConversationDestination(
    sessionId: sessionId,
    title: session?.session.title ?? sessionId,
    projectId: project?.project.id,
    projectUnavailable: project == null,
  );
}

Future<void> openConversation(
  BuildContext context,
  AppState state, {
  required String desktopId,
  required String sessionId,
}) async {
  if (!state.isOnline(desktopId)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.tr(
            '电脑不在线，暂时无法打开该对话。',
            'The desktop is offline; the chat cannot be opened now.',
          ),
        ),
      ),
    );
    return;
  }
  await runUi(context, () async {
    final target = resolveConversation(
      state,
      desktopId: desktopId,
      sessionId: sessionId,
    );
    // 未列出时仍可用已有 open 只读确认；不修改归档、项目或权限。
    await openPage<void>(
      context,
      ChatPage(
        state: state,
        desktopId: desktopId,
        sessionId: target.sessionId,
        title: target.title,
        projectId: target.projectId,
        projectUnavailable: target.projectUnavailable,
      ),
    );
  });
}
