import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/press_menu.dart';

/// 对话首页与文件页共用项目置顶、移除和确认逻辑。
class ProjectActionRow extends StatefulWidget {
  const ProjectActionRow({
    super.key,
    required this.state,
    required this.project,
    required this.child,
  });
  final AppState state;
  final ProjectRef project;
  final Widget child;

  @override
  State<ProjectActionRow> createState() => _ProjectActionRowState();
}

class _ProjectActionRowState extends State<ProjectActionRow> {
  bool _busy = false;
  bool get _enabled =>
      !_busy && widget.state.isOnline(widget.project.desktopId);

  Future<void> _apply(String action) async {
    if (!_enabled) return;
    final state = widget.state;
    final ref = widget.project;
    setState(() => _busy = true);
    try {
      await runUi(context, () async {
        if (action == 'hide') {
          final confirmed = await confirmAction(
            context,
            state,
            state.tr('从列表移除项目？', 'Remove project from the list?'),
            state.tr(
              '将“${ref.project.name}”从电脑和手机的项目列表移除，不删除文件或对话。',
              'Remove “${ref.project.name}” from the desktop and phone lists without deleting files or conversations.',
            ),
            action: state.tr('移除', 'Remove'),
          );
          if (!confirmed || !mounted || !state.isOnline(ref.desktopId)) return;
          await state.request(ref.desktopId, LinkMethods.hideProject, {
            'project': ref.project.id,
          });
        } else if (action == 'pin' && ref.project.pinned != null) {
          await state.request(ref.desktopId, LinkMethods.pinProject, {
            'project': ref.project.id,
            'pinned': ref.project.pinned != true,
          });
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pinned = widget.project.project.pinned;
    return PressMenuRow(
      enabled: _enabled,
      items: [
        if (pinned != null)
          PressMenuItem(
            pinned ? state.tr('取消置顶', 'Unpin') : state.tr('置顶', 'Pin'),
            () => _apply('pin'),
          ),
        PressMenuItem(
          // 只是把项目从列表移除，不删电脑上的文件夹：用警示黄而非删除红。
          state.tr('移除', 'Remove'),
          () => _apply('hide'),
          color: MobileTheme.statusColorsOf(context).warning,
        ),
      ],
      child: widget.child,
    );
  }
}
