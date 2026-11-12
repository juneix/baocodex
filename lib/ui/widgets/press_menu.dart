import 'package:flutter/material.dart';

import 'dropdown_panel.dart';

class PressMenuItem {
  const PressMenuItem(this.label, this.onSelected, {this.color});

  final String label;
  final VoidCallback onSelected;

  /// 危险或需谨慎的操作用不同颜色，如删除的红、移除的黄。
  final Color? color;
}

/// 长按 [child] 时高亮这一行，并在手指处弹出菜单；下方放不下时翻到上方。
class PressMenuRow extends StatefulWidget {
  const PressMenuRow({
    super.key,
    required this.items,
    required this.child,
    this.enabled = true,
  });

  final List<PressMenuItem> items;
  final Widget child;
  final bool enabled;

  @override
  State<PressMenuRow> createState() => _PressMenuRowState();
}

class _PressMenuRowState extends State<PressMenuRow> {
  bool _open = false;

  Future<void> _show(LongPressStartDetails details) async {
    Feedback.forLongPress(context);
    setState(() => _open = true);
    final picked = await showMenuPanelAt<PressMenuItem>(
      context,
      details.globalPosition,
      [
        for (final item in widget.items)
          MenuPanelItem(item, item.label, color: item.color),
      ],
    );
    if (mounted) setState(() => _open = false);
    picked?.onSelected();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // 始终接住长按，禁用时也不能松手变成点击打开这一行。
    onLongPressStart: (details) {
      if (widget.enabled && widget.items.isNotEmpty) _show(details);
    },
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        color: _open ? Theme.of(context).highlightColor : null,
      ),
      child: widget.child,
    ),
  );
}
