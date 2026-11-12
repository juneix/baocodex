// YCode — GPL-3.0-only.
import 'dart:io' show Platform;

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../devices/device_menu.dart' show linkStatusLabel;

/// 侧栏会话左侧的状态圆点：颜色区分状态，只做很轻的动效。
///
/// - 运行中：蓝色呼吸（透明度 0.4 ↔ 1，1.5 秒一轮）
/// - 等待回应：红色微放大（1 ↔ 1.15，2.4 秒一轮，比呼吸更慢）
/// - 已完成未读：绿色呼吸
/// - 空闲已读：浅灰，不动
///
/// 系统关掉动画时一律静止，停在最清楚的那一帧。
class SessionStatusDot extends StatefulWidget {
  const SessionStatusDot({
    super.key,
    required this.state,
    required this.ref,
    this.selected = false,
  });

  final AppState state;
  final SessionRef ref;

  /// 选中的行圆点略大一点。
  final bool selected;

  static const _size = 7.0;

  /// 测试进程里不跑循环动画：常驻动画会让 pumpAndSettle 永远等不到静止。
  /// `flutter test` 会设置 FLUTTER_TEST；真机上这个变量不存在。
  static bool get _animationsOff =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  @override
  State<SessionStatusDot> createState() => _SessionStatusDotState();
}

enum _DotMotion { still, breathe, pulse }

class _SessionStatusDotState extends State<SessionStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  _DotMotion _motion = _DotMotion.still;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SessionStatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final motion = _motionFor();
    final still = _animationsOff || MediaQuery.disableAnimationsOf(context);
    if (motion != _motion) {
      _motion = motion;
      _controller.duration = switch (motion) {
        _DotMotion.pulse => const Duration(milliseconds: 2400),
        _ => const Duration(milliseconds: 1500),
      };
    }
    if (motion == _DotMotion.still || still) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  _DotMotion _motionFor() {
    final state = widget.state;
    final ref = widget.ref;
    if (!state.isOnline(ref.desktopId)) return _DotMotion.still;
    switch (ref.session.status) {
      case LinkSessionStatus.running:
        return _DotMotion.breathe;
      case LinkSessionStatus.needsInput:
        return _DotMotion.pulse;
      case LinkSessionStatus.idle:
        return state.sessionUnread(ref) ? _DotMotion.breathe : _DotMotion.still;
    }
  }

  Color _color(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = MobileTheme.statusColorsOf(context);
    if (!widget.state.isOnline(widget.ref.desktopId)) {
      return colors.onSurfaceVariant.withValues(alpha: .45);
    }
    switch (widget.ref.session.status) {
      case LinkSessionStatus.running:
        return status.info;
      case LinkSessionStatus.needsInput:
        return colors.error;
      case LinkSessionStatus.idle:
        return widget.state.sessionUnread(widget.ref)
            ? status.success
            : colors.onSurfaceVariant.withValues(alpha: .45);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final size = widget.selected ? 9.0 : SessionStatusDot._size;
    return Tooltip(
      message: _label(context),
      child: SizedBox.square(
        dimension: 14,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Opacity(
                // 呼吸：0.4 ↔ 1。
                opacity: _motion == _DotMotion.breathe
                    ? 0.4 + 0.6 * t
                    : 1,
                child: Transform.scale(
                  // 脉冲：1 ↔ 1.15。
                  scale: _motion == _DotMotion.pulse ? 1 + 0.15 * t : 1,
                  child: child,
                ),
              );
            },
            child: Container(
              key: const ValueKey('session-status-dot'),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label(BuildContext context) {
    final state = widget.state;
    final ref = widget.ref;
    if (!state.isOnline(ref.desktopId)) {
      return linkStatusLabel(state, state.linkStatus(ref.desktopId));
    }
    return switch (ref.session.status) {
      LinkSessionStatus.running => state.tr('运行中', 'Running'),
      LinkSessionStatus.needsInput => state.tr('等待回应', 'Needs input'),
      LinkSessionStatus.idle =>
        state.sessionUnread(ref) ? state.tr('已完成，未读', 'Done, unread') : state.tr('空闲', 'Idle'),
    };
  }
}
