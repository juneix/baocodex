import 'package:flutter/material.dart';

/// 包着会回收行的列表的选中区：一拖动就收起复制工具条。选中的行滚走被回收后，
/// Flutter 重建工具条会因选区端点为空而崩溃（flutter/flutter#124078）。
class ScrollingSelectionArea extends StatelessWidget {
  const ScrollingSelectionArea({super.key, this.areaKey, required this.child});

  /// 要从外面清掉选区时用，见 [SelectionAreaState.selectableRegion]。
  final GlobalKey<SelectionAreaState>? areaKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(
    key: areaKey,
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) ContextMenuController.removeAny();
        return false;
      },
      child: child,
    ),
  );
}
