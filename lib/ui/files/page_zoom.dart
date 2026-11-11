import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 双指缩放整页：内容按 1/倍率 排版再整体绘制，缩小时看得到更多行，
/// 虚拟列表和横向滚动照常工作。手势走 Listener，不和内层滚动抢手势。
class PageZoom extends StatefulWidget {
  const PageZoom({
    super.key,
    required this.vertical,
    required this.horizontal,
    required this.builder,
  });

  final ScrollController vertical, horizontal;

  /// [physics] 在双指按下期间锁住滚动；内层滚动视图都要用它。
  final Widget Function(
    BuildContext context,
    ScrollPhysics? physics,
    double scale,
  )
  builder;

  @override
  State<PageZoom> createState() => _PageZoomState();
}

class _PageZoomState extends State<PageZoom> {
  static const _minScale = .5, _maxScale = 3.0;

  final _pointers = <int, Offset>{};
  var _scale = 1.0;
  var _size = Size.zero;
  // content 是两指中点下的内容坐标，缩放时让它一直跟着手指。
  ({double distance, double scale, Offset content})? _pinch;

  Offset get _focal => (_pointers.values.first + _pointers.values.last) / 2;
  double get _distance =>
      (_pointers.values.first - _pointers.values.last).distance;

  double _offset(ScrollController controller) =>
      controller.hasClients ? controller.offset : 0;

  void _beginPinch() => setState(
    () => _pinch = (
      distance: math.max(_distance, 1),
      scale: _scale,
      content:
          Offset(_offset(widget.horizontal), _offset(widget.vertical)) +
          _focal / _scale,
    ),
  );

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _beginPinch();
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final pinch = _pinch;
    if (pinch == null || _pointers.length != 2) return;
    final scale = (pinch.scale * _distance / pinch.distance).clamp(
      _minScale,
      _maxScale,
    );
    final origin = pinch.content - _focal / scale;
    _scrollTo(widget.horizontal, origin.dx, _size.width / scale);
    _scrollTo(widget.vertical, origin.dy, _size.height / scale);
    setState(() => _scale = scale);
  }

  // 新视口的上限要自己算：此时列表还没按新倍率排版。
  void _scrollTo(ScrollController controller, double offset, double viewport) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final content = position.maxScrollExtent + position.viewportDimension;
    controller.jumpTo(offset.clamp(0.0, math.max(0.0, content - viewport)));
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length == 2) {
      _beginPinch();
    } else if (_pinch != null && _pointers.length < 2) {
      setState(() {
        _pinch = null;
        // 接近原大时吸附，缩回去不用捏得分毫不差。
        if ((_scale - 1).abs() < .06) _scale = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: SizedBox.fromSize(
          size: _size,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              key: const ValueKey('page-zoom-content'),
              width: _size.width / _scale,
              height: _size.height / _scale,
              child: widget.builder(
                context,
                _pinch == null ? null : const NeverScrollableScrollPhysics(),
                _scale,
              ),
            ),
          ),
        ),
      );
    },
  );
}
