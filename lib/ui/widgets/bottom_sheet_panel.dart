import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'lucide_icon.dart';

/// 底部浮层共用固定标题、关闭按钮与安全区，长内容由调用方滚动。
Future<T?> showBottomSheetPanel<T>(
  BuildContext context, {
  required String title,
  required String closeLabel,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .32),
  elevation: 0,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (constraints.maxHeight -
                        MediaQuery.viewInsetsOf(context).bottom -
                        MediaQuery.paddingOf(context).bottom -
                        8)
                    .clamp(0, double.infinity) *
                .9,
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
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
          ),
        ),
      ),
    ),
  ),
);
