import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 复制按钮的「按一下变勾、1.5 秒后变回来」：代码卡、图表、引用、
/// 消息底栏都用这一份，别各写一个 timer。
mixin CopyFeedback<T extends StatefulWidget> on State<T> {
  static const _hold = Duration(milliseconds: 1500);

  bool _copied = false;
  Timer? _copiedTimer;

  bool get copied => _copied;

  void copyText(String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(_hold, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }
}
