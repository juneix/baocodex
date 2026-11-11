import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../widgets/mobile_widgets.dart';

final _deleting = Expando<Set<(String, String)>>();

Future<bool> deleteConversation(
  BuildContext context,
  AppState state, {
  required String desktopId,
  required String sessionId,
  required String title,
}) async {
  final active = _deleting[state] ??= {};
  final key = (desktopId, sessionId);
  if (!state.isOnline(desktopId) || !active.add(key)) return false;
  try {
    final confirmed = await confirmAction(
      context,
      state,
      state.tr('删除对话？', 'Delete conversation?'),
      state.tr(
        '将从电脑删除“$title”及其对话记录，无法撤销。项目文件不会因此删除。',
        'Delete “$title” and its conversation from the desktop. This cannot be undone. Project files are not deleted.',
      ),
      action: state.tr('删除', 'Delete'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    await state.request(desktopId, LinkMethods.delete, {'session': sessionId});
    return true;
  } finally {
    active.remove(key);
  }
}
