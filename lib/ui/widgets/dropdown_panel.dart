import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'lucide_icon.dart';

enum DropdownAlign { start, center, end }

const _popupMargin = 8.0;

/// 弹层可用的上下边界：避开状态栏、导航条和键盘。
({double top, double bottom}) popupArea(MediaQueryData media) => (
  top: media.padding.top + _popupMargin,
  bottom:
      media.size.height -
      math.max(media.padding.bottom, media.viewInsets.bottom) -
      _popupMargin,
);

/// 想去的一边放得下就去；否则去放得下的另一边；都放不下去空间大的一边。
bool popupGoesAbove({
  required Rect anchor,
  required double height,
  required MediaQueryData media,
  required double gap,
  bool preferAbove = false,
}) {
  final area = popupArea(media);
  final above = anchor.top - gap - area.top;
  final below = area.bottom - anchor.bottom - gap;
  final fitsAbove = height <= above, fitsBelow = height <= below;
  if (fitsAbove != fitsBelow) return fitsAbove;
  return fitsAbove ? preferAbove : above > below;
}

double popupLeft({
  required Rect anchor,
  required double width,
  required double screenWidth,
  required DropdownAlign align,
}) =>
    switch (align) {
          DropdownAlign.start => anchor.left,
          DropdownAlign.center => anchor.center.dx - width / 2,
          DropdownAlign.end => anchor.right - width,
        }
        .clamp(
          _popupMargin,
          math.max(_popupMargin, screenWidth - width - _popupMargin),
        )
        .toDouble();

/// 所有贴着某处弹出的层共用的路由；[anchor] 每次重建都重新量，收键盘时才跟得上。
Future<T?> showAnchoredPopup<T>(
  BuildContext context, {
  required Rect Function(RenderBox overlay) anchor,
  required Widget Function(BuildContext context, Rect anchor) builder,
  double? width,
  DropdownAlign align = DropdownAlign.center,
  bool preferAbove = false,
  double gap = 4,
  bool requestFocus = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _AnchoredRoute<T>(
      measure: () =>
          anchor(navigator.overlay!.context.findRenderObject()! as RenderBox),
      builder: builder,
      width: width,
      align: align,
      preferAbove: preferAbove,
      gap: gap,
      requestFocus: requestFocus,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// [anchor] 这个 context 占的矩形；它已经销毁时给 null。
Rect? contextRect(BuildContext anchor, RenderBox overlay) {
  final box = anchor.mounted ? anchor.findRenderObject() : null;
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(
    box.getTransformTo(overlay),
    Offset.zero & box.size,
  );
}

Rect Function(RenderBox) followContext(BuildContext anchor) {
  var last = Rect.zero;
  return (overlay) => last = contextRect(anchor, overlay) ?? last;
}

Widget _surface(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final menu = theme.popupMenuTheme;
  return Material(
    key: const ValueKey('dropdown-panel'),
    color: menu.color ?? theme.colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: menu.elevation ?? 6,
    shape:
        menu.shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
        ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// 贴着 [anchor] 弹出的面板，下方放不下时翻到上方；点外面或 [Navigator.pop] 关闭。
/// [anchor] 要是触发按钮自己的 context，不是整页的。
Future<T?> showDropdownPanel<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 300,
  DropdownAlign align = DropdownAlign.center,
  bool requestFocus = false,
}) => showAnchoredPopup<T>(
  anchor,
  anchor: followContext(anchor),
  width: width,
  align: align,
  requestFocus: requestFocus,
  builder: (context, _) => _surface(context, builder(context)),
);

class MenuPanelItem<T> {
  const MenuPanelItem(
    this.value,
    this.label, {
    this.key,
    this.leading,
    this.trailing,
    this.color,
    this.selected = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Key? key;
  final Widget? leading, trailing;
  final Color? color;
  final bool selected, enabled;
}

Widget _menuRows<T>(List<MenuPanelItem<T>> items) => SingleChildScrollView(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final item in items) _MenuPanelRow(item)],
  ),
);

/// 一组操作或单选，贴着 [anchor]：图标在前，选中项末尾打勾。
Future<T?> showMenuPanel<T>(
  BuildContext anchor,
  List<MenuPanelItem<T>> items, {
  double width = 220,
  DropdownAlign align = DropdownAlign.end,
}) => showDropdownPanel<T>(
  anchor,
  width: width,
  align: align,
  builder: (_) => _menuRows(items),
);

/// 同一组操作，从手指处 [point]（全局坐标）展开，宽度随内容。
Future<T?> showMenuPanelAt<T>(
  BuildContext context,
  Offset point,
  List<MenuPanelItem<T>> items,
) => showAnchoredPopup<T>(
  context,
  anchor: (overlay) {
    final local = overlay.globalToLocal(point);
    return Rect.fromPoints(local, local);
  },
  align: DropdownAlign.start,
  gap: 0,
  builder: (context, _) => _surface(
    context,
    IntrinsicWidth(
      stepWidth: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 148),
        child: _menuRows(items),
      ),
    ),
  ),
);

class _MenuPanelRow<T> extends StatelessWidget {
  const _MenuPanelRow(this.item);

  final MenuPanelItem<T> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing =
        item.trailing ??
        (item.selected
            ? LucideIcon('check', size: 20, color: theme.colorScheme.primary)
            : null);
    return Opacity(
      opacity: item.enabled ? 1 : .38,
      child: InkWell(
        key: item.key,
        onTap: item.enabled ? () => Navigator.pop(context, item.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileSpace.lg,
              vertical: MobileSpace.sm,
            ),
            child: Row(
              children: [
                if (item.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: MobileSpace.md),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: item.color,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: MobileSpace.md),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchoredRoute<T> extends PopupRoute<T> {
  _AnchoredRoute({
    required this.measure,
    required this.builder,
    required this.width,
    required this.align,
    required this.preferAbove,
    required this.gap,
    required this.barrierLabel,
    required this.themes,
    super.requestFocus = false,
  });

  final Rect Function() measure;
  final Widget Function(BuildContext context, Rect anchor) builder;
  final double? width;
  final DropdownAlign align;
  final bool preferAbove;
  final double gap;
  final CapturedThemes themes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final anchor = measure();
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final originX = switch (align) {
      DropdownAlign.start => -1.0,
      DropdownAlign.center => 0.0,
      DropdownAlign.end => 1.0,
    };
    final originY = anchor.center.dy < media.size.height / 2 ? -1.0 : 1.0;
    return themes.wrap(
      CustomSingleChildLayout(
        delegate: _AnchoredLayout(
          anchor: anchor,
          width: width,
          align: align,
          preferAbove: preferAbove,
          gap: gap,
          media: media,
        ),
        child: FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: .94, end: 1.0).animate(curve),
            alignment: Alignment(originX, originY),
            child: builder(context, anchor),
          ),
        ),
      ),
    );
  }
}

class _AnchoredLayout extends SingleChildLayoutDelegate {
  const _AnchoredLayout({
    required this.anchor,
    required this.width,
    required this.align,
    required this.preferAbove,
    required this.gap,
    required this.media,
  });

  final Rect anchor;
  final double? width;
  final DropdownAlign align;
  final bool preferAbove;
  final double gap;
  final MediaQueryData media;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final area = popupArea(media);
    final widest = math.max(0.0, constraints.maxWidth - _popupMargin * 2);
    final fixed = width == null ? null : math.min(width!, widest);
    return BoxConstraints(
      minWidth: fixed ?? 0,
      maxWidth: fixed ?? widest,
      maxHeight: math.max(
        0,
        math.max(
          anchor.top - gap - area.top,
          area.bottom - anchor.bottom - gap,
        ),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    popupLeft(
      anchor: anchor,
      width: childSize.width,
      screenWidth: size.width,
      align: align,
    ),
    popupGoesAbove(
          anchor: anchor,
          height: childSize.height,
          media: media,
          gap: gap,
          preferAbove: preferAbove,
        )
        ? anchor.top - gap - childSize.height
        : anchor.bottom + gap,
  );

  @override
  bool shouldRelayout(_AnchoredLayout old) =>
      old.anchor != anchor ||
      old.width != width ||
      old.align != align ||
      old.preferAbove != preferAbove ||
      old.gap != gap ||
      old.media != media;
}
