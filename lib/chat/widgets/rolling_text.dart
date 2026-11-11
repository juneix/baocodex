import 'package:flutter/material.dart';

/// Digits roll upward as a live statistic changes; text between digits stays put.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;
  static const duration = Duration(milliseconds: 220);

  static List<String> runsOf(String text) {
    final runs = <String>[];
    final other = StringBuffer();
    for (final char in text.characters) {
      if (char.length == 1 &&
          char.codeUnitAt(0) >= 48 &&
          char.codeUnitAt(0) <= 57) {
        if (other.isNotEmpty) runs.add(other.toString());
        other.clear();
        runs.add(char);
      } else {
        other.write(char);
      }
    }
    if (other.isNotEmpty) runs.add(other.toString());
    return runs;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(text, style: style);
    }
    final runs = runsOf(text);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, run) in runs.indexed)
            KeyedSubtree(
              key: ValueKey(runs.length - index),
              child:
                  run.length == 1 &&
                      run.codeUnitAt(0) >= 48 &&
                      run.codeUnitAt(0) <= 57
                  ? _Digit(run, style: style)
                  : Text(run, style: style),
            ),
        ],
      ),
    );
  }
}

class _Digit extends StatefulWidget {
  const _Digit(this.digit, {required this.style});
  final String digit;
  final TextStyle style;

  @override
  State<_Digit> createState() => _DigitState();
}

class _DigitState extends State<_Digit> {
  int _change = 0;

  @override
  void didUpdateWidget(_Digit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.digit != oldWidget.digit) _change++;
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(_change);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: RollingText.duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final incoming = child.key == key;
          final offset = Tween<Offset>(
            begin: Offset(0, incoming ? 0.8 : -0.8),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Text(widget.digit, key: key, style: widget.style),
      ),
    );
  }
}
