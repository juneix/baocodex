// YCode — conversation UI. GPL-3.0-only.

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_facing_error.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../ui/files/files_tab.dart';
import '../ui/user_message.dart';
import '../ui/widgets/bottom_sheet_panel.dart';
import 'chat_markdown.dart';

/// Shows [path] of the chat's project or bot; where every file open in the
/// chat goes (a link's, a step row's, a diff's). A project's opens in the
/// Files tab's viewer (preview, wrap, search, download); a bare name not at
/// the root is looked up by name, as the desktop does. A bot is in no
/// project: its file is read off the desktop and shown whole.
Future<void> showLinkedFile(
  BuildContext context,
  AppState state,
  String desktopId,
  String? projectId,
  String path, {
  String? botId,
}) async {
  if (projectId == null && botId == null) return;
  final project = projectId == null
      ? null
      : state.projects
            .where(
              (ref) =>
                  ref.desktopId == desktopId && ref.project.id == projectId,
            )
            .firstOrNull;
  if (project != null) {
    final found = await _findInProject(context, state, project, path);
    if (found == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FileViewerPage(state: state, project: project, path: found),
      ),
    );
    return;
  }
  try {
    // Bot 不属于任何项目，它的文件按 Bot 找。
    final result = await state.request(desktopId, LinkMethods.read, {
      if (projectId != null) 'project': projectId else 'bot': botId,
      'path': path,
    });
    if (result is! Map) throw const FormatException('Invalid file response');
    if (!context.mounted) return;
    await showBottomSheetPanel<void>(
      context,
      title: path,
      closeLabel: state.tr('关闭', 'Close'),
      size: SheetSize.large,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (result['text'] is String)
            CodePanel(code: result['text'] as String)
          else
            Text(
              result['tooLarge'] == true
                  ? state.tr('文件超过读取限制。', 'File exceeds the read limit.')
                  : state.tr('此文件没有文本预览。', 'This file has no text preview.'),
            ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessage(state, error))));
    }
  }
}

/// Where [path] is in [project]: as given when it has a folder or is at the
/// root; else the file of that name, the user picking among several. Null
/// when it is nowhere (said so) or no pick was made.
Future<String?> _findInProject(
  BuildContext context,
  AppState state,
  ProjectRef project,
  String path,
) async {
  if (path.contains('/') || path.contains('\\')) return path;
  final List<String> paths;
  try {
    final listing = objectMap(
      await state.request(project.desktopId, LinkMethods.files, {
        'project': project.project.id,
      }),
    );
    paths = [
      for (final entry in (listing['paths'] as List?) ?? const [])
        if (entry is String) entry,
    ];
  } catch (_) {
    // 列不出文件就照原样打开，让查看器说清楚。
    return path;
  }
  if (paths.contains(path)) return path;
  final named = [
    for (final candidate in paths)
      if (candidate.endsWith('/$path')) candidate,
  ];
  if (named.length == 1) return named.single;
  if (!context.mounted) return null;
  if (named.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.tr('项目里没有找到 $path。', 'No $path in the project.')),
      ),
    );
    return null;
  }
  return showBottomSheetPanel<String>(
    context,
    title: state.tr('有几个 $path，打开哪个？', 'Several $path. Open which?'),
    closeLabel: state.tr('关闭', 'Close'),
    size: SheetSize.small,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        for (final candidate in named)
          ListTile(
            title: Text(candidate),
            onTap: () => Navigator.pop(context, candidate),
          ),
      ],
    ),
  );
}

Future<void> confirmExternalLink(
  BuildContext context,
  AppState state,
  String href,
) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
  final allowed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(state.tr('在浏览器打开？', 'Open in browser?')),
      content: Text(
        '${state.tr('此链接将连接外部网站。', 'This link connects to an external website.')}\n\n$href',
      ),
      actions: dialogButtons([
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(state.tr('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(state.tr('确认', 'Confirm')),
        ),
      ]),
    ),
  );
  if (allowed != true) return;
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw UserFacingError(state.tr('无法打开链接', 'Could not open link'));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessage(state, error))));
    }
  }
}
