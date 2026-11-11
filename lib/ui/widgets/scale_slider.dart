import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 一格一格的取值用一个滑块来选：每格一颗小圆点，滑过一格轻震一次。
///
/// 刻度点由 [SliderThemeData.tickMarkShape] 画，已走过的段由 Material 上色；
/// 震动挂在 [Slider.onChanged] 上，值按 [divisions] 对齐，所以只有真的换了
/// 一格才震，手指停在两格之间不会连震。
class ScaleSlider extends StatefulWidget {
  const ScaleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.onTick,
    this.marks = const [],
    this.enabled = true,
  });

  final double value, min, max;
  final int divisions;

  /// 单独标出来的取值（比如默认值），点画得大一些。
  final List<double> marks;

  final ValueChanged<double> onChanged;

  /// 手松开、值定下来时；拖的那一路只走 [onChanged]。
  final ValueChanged<double>? onChangeEnd;

  /// 滑过一格时；没给就用系统的轻震。
  final VoidCallback? onTick;

  final bool enabled;

  @override
  State<ScaleSlider> createState() => _ScaleSliderState();
}

class _ScaleSliderState extends State<ScaleSlider> {
  late double _last = widget.value;

  @override
  void didUpdateWidget(ScaleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _last = widget.value;
  }

  void _changed(double value) {
    if (value != _last) {
      _last = value;
      if (widget.onTick case final tick?) {
        tick();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marks = [
      for (final mark in widget.marks)
        if (mark >= widget.min && mark <= widget.max)
          (mark - widget.min) / (widget.max - widget.min),
    ];
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurfaceVariant.withValues(alpha: .2),
        thumbColor: scheme.primary,
        thumbShape: const _DotThumbShape(),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        tickMarkShape: _DotTickShape(marks),
        activeTickMarkColor: scheme.onPrimary,
        inactiveTickMarkColor: scheme.onSurfaceVariant.withValues(alpha: .35),
        disabledActiveTickMarkColor: scheme.onPrimary.withValues(alpha: .6),
        disabledInactiveTickMarkColor: scheme.onSurfaceVariant.withValues(
          alpha: .2,
        ),
      ),
      child: Slider(
        value: widget.value.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: widget.enabled ? _changed : null,
        onChangeEnd: widget.onChangeEnd,
      ),
    );
  }
}

/// 指尖下一颗实心圆点，按下时略微放大。
class _DotThumbShape extends SliderComponentShape {
  const _DotThumbShape();

  static const _radius = 11.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final enabled = enableAnimation.value;
    final radius = _radius * (1 + activationAnimation.value * .12);
    final circle = Rect.fromCircle(center: center, radius: radius);
    if (activationAnimation.value > 0) {
      context.canvas.drawShadow(
        Path()..addOval(circle),
        Colors.black,
        4 * activationAnimation.value,
        false,
      );
    }
    context.canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Color.lerp(
          sliderTheme.disabledThumbColor,
          sliderTheme.thumbColor,
          enabled,
        )!,
    );
  }
}

/// 每一格一颗小圆点；[marks] 里的（默认值）半径大一些。
class _DotTickShape extends SliderTickMarkShape {
  const _DotTickShape(this.marks);

  /// 要放大的刻度，按整条轨道的比例给。
  final List<double> marks;

  static const _radius = 2.5;
  static const _markRadius = 4.0;

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size.fromRadius(_markRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    required bool isEnabled,
  }) {
    // 在滑块哪一侧，决定这颗点是已走过还是还没走到。
    final passed = textDirection == TextDirection.ltr
        ? center.dx <= thumbCenter.dx
        : center.dx >= thumbCenter.dx;
    final paint = Paint()
      ..color = ColorTween(
        begin: passed
            ? sliderTheme.disabledActiveTickMarkColor
            : sliderTheme.disabledInactiveTickMarkColor,
        end: passed
            ? sliderTheme.activeTickMarkColor
            : sliderTheme.inactiveTickMarkColor,
      ).evaluate(enableAnimation)!;
    // 轨道宽度换成比例，用来认出默认值那几格。
    final fraction = parentBox.size.width <= 0
        ? 0.0
        : (center.dx / parentBox.size.width).clamp(0.0, 1.0);
    final big = marks.any((mark) => (mark - fraction).abs() < .01);
    context.canvas.drawCircle(center, big ? _markRadius : _radius, paint);
  }
}
