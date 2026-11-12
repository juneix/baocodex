import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get nativePermissionMenus => Platform.isAndroid;

/// 原生下拉只负责展示，选择结果仍交给会话的 choose 流程。
Future<String?> showNativePermissionMenu(
  BuildContext anchor, {
  required List<({String id, String label})> options,
  required String? selected,
}) async {
  final box = anchor.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !anchor.mounted) return null;
  final origin = box.localToGlobal(Offset.zero);
  final ratio = MediaQuery.devicePixelRatioOf(anchor);
  return const MethodChannel('local.baocode.mobile/platform')
      .invokeMethod<String>('permissionMenu', {
        'x': origin.dx * ratio,
        'y': origin.dy * ratio,
        'width': box.size.width * ratio,
        'height': box.size.height * ratio,
        'dark': Theme.of(anchor).brightness == Brightness.dark,
        'selected': selected,
        'options': [
          for (final option in options)
            {'id': option.id, 'label': option.label},
        ],
      });
}
