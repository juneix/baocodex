import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chat/widgets/agent_step.dart' show AgentStep;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/bottom_sheet_panel.dart';

/// 会话更新里电脑告诉的上下文占用（`context`），单位都是 token。
class ContextUsage {
  const ContextUsage({
    required this.window,
    required this.used,
    this.parts = const [],
    this.compactAt,
  });

  final int window, used;

  /// 按电脑端的分类（`system`、`tools`、`messages`…）或内核自己的名字。
  final List<(String, int)> parts;

  /// 到这里自动压缩。
  final int? compactAt;

  /// 用量超过这个比例时圆环变成警示色，和电脑端一致。
  static const warnAt = .8;

  static const _order = [
    'system',
    'memory',
    'skills',
    'tools',
    'mcp',
    'messages',
  ];

  double get fraction => (used / window).clamp(0.0, 1.0);
  int get percent => (fraction * 100).round();

  static ContextUsage? parse(Map<String, Object?>? json) {
    if (json == null) return null;
    final window = json['window'], used = json['used'];
    if (window is! num || window <= 0 || used is! num || used < 0) return null;
    final parts = <(String, int)>[
      if (json['parts'] case final List list)
        for (final part in list)
          if (objectMap(part)
              case {'part': final String name, 'tokens': final num tokens}
              when tokens > 0)
            (name, tokens.toInt()),
    ];
    int rank((String, int) part) {
      final index = _order.indexOf(part.$1);
      return index < 0 ? _order.length : index;
    }

    return ContextUsage(
      window: window.toInt(),
      used: used.toInt(),
      parts: parts..sort((a, b) => rank(a).compareTo(rank(b))),
      compactAt: switch (json['compactAt']) {
        final num at when at > 0 => at.toInt(),
        _ => null,
      },
    );
  }
}

String contextPartLabel(AppState state, String part) => switch (part) {
  'system' => state.tr('系统提示词', 'System prompt'),
  'memory' => state.tr('CLAUDE.md 与规则', 'CLAUDE.md & rules'),
  'skills' => state.tr('技能', 'Skills'),
  'tools' => state.tr('工具定义', 'Tool definitions'),
  'mcp' => 'MCP',
  'messages' => state.tr('对话消息', 'Conversation'),
  _ => part,
};

/// 输入栏里的上下文圆环，点开看占用明细。
class ContextRing extends StatelessWidget {
  const ContextRing({
    super.key,
    required this.state,
    required this.usage,
    required this.onPressed,
  });

  final AppState state;
  final ContextUsage usage;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warn = usage.fraction >= ContextUsage.warnAt;
    return IconButton(
      tooltip: state.tr(
        '上下文已用 ${usage.percent}%',
        'Context ${usage.percent}% used',
      ),
      onPressed: onPressed,
      icon: SizedBox.square(
        dimension: 18,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: usage.fraction),
          duration: const Duration(milliseconds: 400),
          builder: (context, value, _) => CustomPaint(
            painter: _RingPainter(
              value,
              track: colors.outlineVariant,
              arc: warn
                  ? MobileTheme.statusColorsOf(context).warning
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction, {required this.track, required this.arc});

  final double fraction;
  final Color track, arc;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.4;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.arc != arc;
}

Future<void> showContextUsage(
  BuildContext context,
  AppState state,
  ContextUsage usage,
) => showBottomSheetPanel<void>(
  context,
  title: state.tr('上下文窗口', 'Context window'),
  closeLabel: state.tr('关闭', 'Close'),
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      MobileSpace.lg,
      0,
      MobileSpace.lg,
      MobileSpace.lg,
    ),
    child: ContextUsageView(state: state, usage: usage),
  ),
);

/// 总量、距自动压缩还有多少，以及各部分占用：一条分段条加明细。
class ContextUsageView extends StatelessWidget {
  const ContextUsageView({super.key, required this.state, required this.usage});

  final AppState state;
  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final format = AgentStep.formatTokens;
    final palette = [
      colors.primary,
      colors.tertiary,
      colors.secondary,
      colors.primary.withValues(alpha: .5),
      colors.tertiary.withValues(alpha: .5),
      colors.secondary.withValues(alpha: .5),
    ];
    var next = 0;
    final parts = [
      for (final (name, tokens)
          in usage.parts.isEmpty ? [('used', usage.used)] : usage.parts)
        (
          label: name == 'used'
              ? state.tr('已用', 'Used')
              : contextPartLabel(state, name),
          tokens: tokens,
          color: name == 'messages' || name == 'used'
              ? colors.onSurfaceVariant
              : palette[next++ % palette.length],
        ),
    ];
    final free = math.max(0, usage.window - usage.used);
    final untilCompact = switch (usage.compactAt) {
      final at? => math.max(0, at - usage.used),
      null => null,
    };
    final faint = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final plain = theme.textTheme.bodySmall?.copyWith(color: colors.onSurface);
    Widget row(Color? color, String label, int tokens) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              border: color == null
                  ? Border.all(color: colors.outlineVariant)
                  : null,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: MobileSpace.sm),
          Expanded(child: Text(label, style: plain)),
          Text(format(tokens), style: plain),
          SizedBox(
            width: 44,
            child: Text(
              '${(tokens / usage.window * 100).toStringAsFixed(tokens * 1000 < usage.window ? 1 : 0)}%',
              textAlign: TextAlign.end,
              style: faint,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.tr(
            '${format(usage.used)} / ${format(usage.window)} token · ${usage.percent}%',
            '${format(usage.used)} / ${format(usage.window)} tokens · ${usage.percent}%',
          ),
          style: theme.textTheme.titleSmall,
        ),
        if (untilCompact != null)
          Padding(
            padding: const EdgeInsets.only(top: MobileSpace.xs),
            child: Text(
              state.tr(
                '距自动压缩 ${format(untilCompact)}',
                '${format(untilCompact)} to auto-compact',
              ),
              style: faint,
            ),
          ),
        const SizedBox(height: MobileSpace.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: ColoredBox(
              color: colors.surfaceContainerHighest,
              child: Row(
                // 色块没有内容，要撑满高度才画得出来。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in parts)
                    Expanded(
                      flex: math.max(
                        1,
                        (part.tokens / usage.window * 1000).round(),
                      ),
                      child: ColoredBox(color: part.color),
                    ),
                  if (free > 0)
                    Expanded(
                      flex: math.max(1, (free / usage.window * 1000).round()),
                      child: const SizedBox.expand(),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: MobileSpace.sm),
        for (final part in parts) row(part.color, part.label, part.tokens),
        row(null, state.tr('剩余', 'Free'), free),
      ],
    );
  }
}
