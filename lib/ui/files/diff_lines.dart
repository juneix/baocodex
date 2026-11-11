import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../files/line_diff.dart';

/// 差异里每一行的高、宽口径：单号一列、符号一列、正文。两个看差异的
/// 地方（文件预览和改动页）共用这一套，行才长得一样。
typedef DiffLineMetrics = ({
  double gutter,
  double marker,
  TextStyle style,
  TextStyle numberStyle,
});

DiffLineMetrics diffLineMetrics(BuildContext context, int lastNumber) {
  final style = MobileTheme.codeStyleOf(context);
  return (
    gutter: lineNumberWidth(context, style, lastNumber),
    marker: MediaQuery.textScalerOf(context).scale(style.fontSize!),
    style: style,
    numberStyle: style.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// 号码列的宽度：最长行号按现在的字号排出来，再多留一点。
double lineNumberWidth(BuildContext context, TextStyle style, int count) {
  final painter = TextPainter(
    text: TextSpan(text: '9' * count.toString().length, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width + 12;
  painter.dispose();
  return width;
}

/// 差异的一行：底色、行号、加减号、正文。删除的行显示改动前的号，
/// 其他行显示现在的号。
class DiffLineRow extends StatelessWidget {
  const DiffLineRow(
    this.line, {
    super.key,
    required this.metrics,
    this.strutStyle,
    this.softWrap = true,
  });

  final ChangedLine line;
  final DiffLineMetrics metrics;
  final StrutStyle? strutStyle;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final colors = MobileTheme.statusColorsOf(context);
    final background = switch (line.kind) {
      LineChange.added => colors.addedBackground,
      LineChange.removed => colors.removedBackground,
      LineChange.context => Colors.transparent,
    };
    final (sign, signColor) = switch (line.kind) {
      LineChange.added => ('+', colors.added),
      LineChange.removed => ('−', colors.removed),
      LineChange.context => (' ', null),
    };
    final number = line.kind == LineChange.removed ? line.before : line.after;
    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: metrics.gutter,
            child: Text(
              '${number ?? ''}',
              textAlign: TextAlign.right,
              style: metrics.numberStyle,
              strutStyle: strutStyle,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: metrics.marker,
            child: Text(
              sign,
              style: metrics.style.copyWith(color: signColor),
              strutStyle: strutStyle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: metrics.style,
              strutStyle: strutStyle,
              softWrap: softWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// 差异里的浮动「第几处 / 共几处」条，上下两个按钮跳到别处改动。
///
/// [at] 为 -1 表示还在第一处之前；[exact] 为假表示视口停在某处之后、
/// 下一处之前，往回走先去那一处。
class ChangeNavigationBar extends StatelessWidget {
  const ChangeNavigationBar({
    super.key,
    required this.at,
    required this.total,
    required this.onStep,
    required this.tr,
    required this.keyPrefix,
  });

  final ({int at, bool exact}) at;
  final int total;
  final void Function(int delta) onStep;
  final String Function(String zh, String en) tr;

  /// 给两个按钮和计数一个前缀，两处差异页各自认自己的控件。
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoBack = at.exact ? at.at > 0 : at.at >= 0;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 2,
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('$keyPrefix-previous-change'),
            tooltip: tr('上一处改动', 'Previous change'),
            onPressed: canGoBack ? () => onStep(-1) : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          Text(
            '${at.at < 0 ? '–' : at.at + 1} / $total',
            key: ValueKey('$keyPrefix-change-count'),
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            key: ValueKey('$keyPrefix-next-change'),
            tooltip: tr('下一处改动', 'Next change'),
            onPressed: at.at + 1 < total ? () => onStep(1) : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }
}
