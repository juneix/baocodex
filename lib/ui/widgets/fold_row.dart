import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'lucide_icon.dart';

/// 可展开的标题行：左边是标题，右边一个和 Lucide 同粗细的箭头，展开时转过来。
/// 没有 Material 的默认分割线、主题色高亮和大内边距，和周围的列表一样。
class FoldRow extends StatefulWidget {
  const FoldRow({
    super.key,
    required this.title,
    required this.children,
    this.leading,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 0),
  });
  final Widget title;
  final Widget? leading;
  final Widget? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  State<FoldRow> createState() => _FoldRowState();
}

class _FoldRowState extends State<FoldRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: widget.padding.add(
              const EdgeInsets.symmetric(vertical: MobileSpace.sm),
            ),
            child: Row(
              children: [
                if (widget.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: MobileSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: text.bodyMedium ?? const TextStyle(),
                        child: widget.title,
                      ),
                      if (widget.subtitle case final subtitle?) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle(
                          style: text.bodySmall ?? const TextStyle(),
                          child: subtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing case final trailing?) ...[
                  trailing,
                  const SizedBox(width: MobileSpace.xs),
                ],
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: LucideIcon('chevron-down', size: 18, color: muted),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: MobileSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// 加载条：一律 2 像素细线，不再用 Material 默认的 4 像素粗条。
class ThinProgress extends StatelessWidget {
  const ThinProgress({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    minHeight: 2,
    color: color,
    backgroundColor: Colors.transparent,
  );
}
