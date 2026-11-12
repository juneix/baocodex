import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'lucide_icon.dart';

/// 从下呼出的弹层高度只有三档，避免每个弹层各高各的。
enum SheetSize {
  small(.46),
  medium(.66),
  large(.9);

  const SheetSize(this.fraction);

  final double fraction;
}

/// 从下呼出的弹层统一的外框：左右下留安全距离、圆角、按档位限高。
Future<T?> showBottomSheetSurface<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  SheetSize size = SheetSize.medium,
  bool requestFocus = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  requestFocus: requestFocus,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .32),
  elevation: 0,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (context) => LayoutBuilder(
    builder: (context, constraints) {
      final insets = MediaQuery.viewInsetsOf(context).bottom;
      final safe = MediaQuery.paddingOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: ((constraints.maxHeight - insets - safe - 8).clamp(
                        0,
                        double.infinity,
                      ) *
                      size.fraction),
            ),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: builder(context),
            ),
          ),
        ),
      );
    },
  ),
);

/// 底部浮层共用固定标题、关闭按钮与安全区，长内容由调用方滚动。
Future<T?> showBottomSheetPanel<T>(
  BuildContext context, {
  required String title,
  required String closeLabel,
  required WidgetBuilder builder,
  SheetSize size = SheetSize.large,
}) => showBottomSheetSurface<T>(
  context,
  size: size,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.lg,
          MobileSpace.sm,
          MobileSpace.sm,
          MobileSpace.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: closeLabel,
              onPressed: () => Navigator.pop(context),
              icon: const LucideIcon('x', size: 22),
            ),
          ],
        ),
      ),
      Flexible(child: builder(context)),
    ],
  ),
);
