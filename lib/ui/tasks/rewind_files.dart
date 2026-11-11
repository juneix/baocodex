import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../files/files_tab.dart' show shortPath;
import '../widgets/mobile_widgets.dart';

/// 电脑对 `rewindPlan` 的回答：重新发送时，Agent 在这条消息之后改过的文件
/// 会怎样撤回，以及电脑端「修改历史消息」的设置。
class RewindPlan {
  const RewindPlan(this.files, {this.setting = RewindSetting.ask});

  static const none = RewindPlan([]);

  /// 文件在项目里的路径和结果：`restore` 原样撤回，`merge` 别处后来也改过、
  /// 那些改动保留，`conflict` 撤不回、保持不变。
  final List<(String, String)> files;
  final RewindSetting setting;

  static RewindPlan parse(Object? result) {
    final json = objectMap(result);
    return RewindPlan(
      [
        if (json['files'] case final List files)
          for (final file in files)
            if (objectMap(file) case {
              'name': final String name,
              'outcome': final String outcome,
            })
              (name, outcome),
      ],
      setting:
          RewindSetting.values
              .where((value) => value.name == json['setting'])
              .firstOrNull ??
          RewindSetting.ask,
    );
  }
}

/// 电脑端的 `chat.rewindFiles`：每次询问、直接撤回或直接保留。
enum RewindSetting { ask, revert, keep }

/// 问电脑这条消息之后的文件改动；旧电脑端不认识这个方法时不问，文件保持
/// 不变，和以前一样。
Future<RewindPlan> loadRewindPlan(
  AppState state,
  String desktopId, {
  required String session,
  required int index,
}) async {
  try {
    return RewindPlan.parse(
      await state.request(desktopId, LinkMethods.rewindPlan, {
        'session': session,
        'index': index,
      }),
    );
  } on LinkRemoteException catch (error) {
    if (error.code == LinkErrors.unknown ||
        error.code == LinkErrors.unsupported) {
      return RewindPlan.none;
    }
    rethrow;
  }
}

/// 列出的文件最多这么多个，其余只说个数。
const _named = 8;

/// 撤回哪些、哪些在别处也改过、哪些撤不回，和电脑端的提示一致。
String rewindFilesDetail(AppState state, List<(String, String)> files) {
  final undone = [
    for (final file in files)
      if (file.$2 != 'conflict') file.$1,
  ];
  final conflicts = [
    for (final file in files)
      if (file.$2 == 'conflict') file.$1,
  ];
  final merged = files.where((file) => file.$2 == 'merge').length;
  List<String> named(List<String> names) => [
    for (final name in names.take(_named)) '  $name',
    if (names.length > _named)
      '  ${state.tr('……还有 ${names.length - _named} 个', '…and ${names.length - _named} more')}',
  ];
  return [
    if (undone.isNotEmpty) ...[
      state.tr(
        '这条消息之后，Agent 改了 ${undone.length} 个文件：',
        'The agent changed ${undone.length == 1 ? '1 file' : '${undone.length} files'} after this message:',
      ),
      ...named(undone),
      if (merged > 0)
        state.tr(
          '其中 $merged 个后来在别处也改过，那些改动会保留。',
          '${merged == 1 ? '1 of them was' : '$merged of them were'} also changed elsewhere since: those changes are kept.',
        ),
      '',
    ],
    if (conflicts.isNotEmpty) ...[
      state.tr(
        '${conflicts.length} 个文件无法自动撤回，会保持不变：',
        conflicts.length == 1
            ? "1 file can't be undone cleanly and will stay as it is:"
            : "${conflicts.length} files can't be undone cleanly and will stay as they are:",
      ),
      ...named(conflicts),
      '',
    ],
    state.tr(
      '命令（Bash）做的改动没有记录，不会撤回。',
      "What commands changed (Bash) isn't tracked and stays.",
    ),
  ].join('\n');
}

/// 重新发送前确认：之后的对话会丢弃；Agent 之后改过文件时，按电脑端的设置
/// 撤回、保留，或者问用户。返回是否撤回文件；null 是取消，继续编辑。
Future<bool?> askResend(
  BuildContext context,
  AppState state, {
  required bool live,
  required RewindPlan plan,
}) async {
  final discard = live
      ? state.tr(
          '之后的对话将被丢弃，当前这一轮也会停止。',
          'What follows is discarded and the running turn stops.',
        )
      : state.tr('之后的对话将被丢弃。', 'What follows is discarded.');
  final files = plan.files;
  if (files.isEmpty || plan.setting != RewindSetting.ask) {
    final revert = files.isNotEmpty && plan.setting == RewindSetting.revert;
    final note = files.isEmpty
        ? null
        : revert
        ? state.tr(
            'Agent 在这条消息之后改过的文件会撤回（电脑端设置）。',
            'Files the agent changed after this message are undone (desktop setting).',
          )
        : state.tr(
            'Agent 在这条消息之后改过的文件会保留（电脑端设置）。',
            'Files the agent changed after this message are kept (desktop setting).',
          );
    final confirmed = await confirmAction(
      context,
      state,
      state.tr('重新发送？', 'Resend?'),
      note == null ? discard : '$discard\n\n$note',
      action: state.tr('丢弃并发送', 'Discard and send'),
      destructive: true,
    );
    return confirmed ? revert : null;
  }
  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        state.tr(
          '撤回这条消息之后的文件改动？',
          'Undo the file changes made after this message?',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line
                in '${rewindFilesDetail(state, files)}\n\n$discard'.split('\n'))
              if (line.isEmpty)
                const SizedBox(height: MobileSpace.sm)
              // 缩进两格的是文件（「……还有」除外）。
              else if (line.startsWith('  ') && !line.startsWith('  …'))
                _RewindFileLine(line.substring(2))
              else
                Text(line),
          ],
        ),
      ),
      actions: dialogButtons([
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(state.tr('取消', 'Cancel')),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(state.tr('保留', 'Keep')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(state.tr('撤回', 'Undo')),
        ),
      ]),
    ),
  );
}

/// 一个文件：文件名一行，所在目录小一号的灰字另起一行（项目外的文件是
/// 完整路径，整行折起来很难认）。
class _RewindFileLine extends StatelessWidget {
  const _RewindFileLine(this.path);
  final String path;

  @override
  Widget build(BuildContext context) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = path.substring(slash + 1);
    final folder = slash <= 0 ? '' : shortPath(path.substring(0, slash));
    final hint = MobileTheme.hintStyleOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: MobileSpace.sm, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontFamily: 'monospace')),
                if (folder.isNotEmpty)
                  Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hint.copyWith(fontSize: MobileType.caption),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
