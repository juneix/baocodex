import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'dropdown_panel.dart';
import 'lucide_icon.dart';

class BubbleMenuAction {
  const BubbleMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon, label;
  final VoidCallback onTap;
}

const _color = Color(0xFF3A3A3C);
const _itemWidth = 64.0;
const _itemHeight = 60.0;
const _inset = 4.0;
const _arrowHeight = 6.0;
const _arrowWidth = 12.0;
const _gap = 4.0;
const _radius = 10.0;

/// 长按消息时贴着 [anchor] 弹出的深色操作条：优先放上方，箭头指回消息。
Future<void> showBubbleMenu(
  BuildContext anchor,
  List<BubbleMenuAction> actions,
) async {
  Feedback.forLongPress(anchor);
  final width = actions.length * _itemWidth + _inset * 2;
  const height = _itemHeight + _inset * 2 + _arrowHeight;
  final picked = await showAnchoredPopup<BubbleMenuAction>(
    anchor,
    anchor: followContext(anchor),
    width: width,
    preferAbove: true,
    gap: _gap,
    builder: (context, rect) {
      final media = MediaQuery.of(context);
      final above = popupGoesAbove(
        anchor: rect,
        height: height,
        media: media,
        gap: _gap,
        preferAbove: true,
      );
      final left = popupLeft(
        anchor: rect,
        width: width,
        screenWidth: media.size.width,
        align: DropdownAlign.center,
      );
      final arrowCenter = (rect.center.dx - left)
          .clamp(_radius + _arrowWidth / 2, width - _radius - _arrowWidth / 2)
          .toDouble();
      final arrow = Padding(
        padding: EdgeInsets.only(left: arrowCenter - _arrowWidth / 2),
        child: CustomPaint(
          size: const Size(_arrowWidth, _arrowHeight),
          painter: _ArrowPainter(up: !above),
        ),
      );
      // 高度参与上下方的判断，不能随系统字号变化。
      return MediaQuery.withNoTextScaling(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!above) arrow,
            Material(
              color: _color,
              borderRadius: BorderRadius.circular(_radius),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final action in actions) _Item(action)],
                ),
              ),
            ),
            if (above) arrow,
          ],
        ),
      );
    },
  );
  picked?.onTap();
}

class _Item extends StatelessWidget {
  const _Item(this.action);

  final BubbleMenuAction action;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(_radius - _inset),
    highlightColor: Colors.white.withValues(alpha: .12),
    splashColor: Colors.transparent,
    onTap: () => Navigator.pop(context, action),
    child: SizedBox(
      width: _itemWidth,
      height: _itemHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LucideIcon(action.icon, size: 20, color: Colors.white),
          const SizedBox(height: MobileSpace.xs),
          Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: MobileType.caption,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up});

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    // 底边多伸 1 像素压进面板，避免缩放时露出接缝。
    final tip = up ? 0.0 : size.height;
    final base = up ? size.height + 1 : -1.0;
    canvas.drawPath(
      Path()
        ..moveTo(0, base)
        ..lineTo(size.width / 2, tip)
        ..lineTo(size.width, base)
        ..close(),
      Paint()..color = _color,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}
