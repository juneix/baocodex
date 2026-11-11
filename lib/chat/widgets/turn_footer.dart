import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/widgets/copy_feedback.dart';
import '../chat_models.dart';
import 'agent_step.dart';
import 'rolling_text.dart';
import '../../theme/app_theme.dart';

const _copyIcon = 'assets/icons/lucide-copy.svg';
const _checkIcon = 'assets/icons/lucide-check.svg';
const _zapIcon = 'assets/icons/lucide-zap.svg';
const _clockIcon = 'assets/icons/lucide-clock.svg';
const _arrowDownIcon = 'assets/icons/lucide-arrow-down.svg';

/// Small localized strings for a self-contained mobile widget.
class TurnStrings {
  const TurnStrings(this.zh);
  final bool zh;

  String get copy => zh ? '复制回答' : 'Copy answer';
  String get copied => zh ? '已复制' : 'Copied';
  String get durationHint => zh ? '耗时' : 'Duration';
  String get speedHint => zh ? '生成速度' : 'Generation speed';
  String get liveSpeedHint => zh ? '当前生成速度' : 'Current generation speed';
  String get costHint => zh ? '费用' : 'Cost';
  String get liveTokensHint => zh ? '已生成 token 数' : 'Output tokens';
  String get speedUnit => ' tok/s';
  String tokens(int value) => '${compactTokens(value)} tok';

  /// Short enough for one line on a phone (see [AgentStep.formatTokens]).
  static String compactTokens(int tokens) => AgentStep.formatTokens(tokens);

  String speed(double value) => '${value.round()}$speedUnit';
  String duration(Duration value) =>
      AgentStep.formatDuration(value, strings: AgentStrings(zh));

  String tokenBreakdown(String input, String output) =>
      zh ? '输入 $input · 输出 $output' : 'Input $input · Output $output';
}

class TurnFooter extends StatelessWidget {
  const TurnFooter({
    super.key,
    this.answer,
    this.worked,
    this.usage,
    this.live,
    this.since,
    this.zh,
    this.strings,
    this.action,
  });

  final String? answer;
  final Duration? worked;
  final TurnUsage? usage;
  final TurnOutput? live;
  final DateTime? since;
  final bool? zh;
  final TurnStrings? strings;
  final Widget? action;

  static String formatCost(double usd) {
    if (usd >= 1 || usd == 0) return '\$${usd.toStringAsFixed(2)}';
    var digits = 2;
    while (digits < 6 && usd < math.pow(10, 1 - digits)) {
      digits++;
    }
    return '\$${usd.toStringAsFixed(digits)}';
  }

  TurnStrings _strings(BuildContext context) =>
      strings ??
      TurnStrings(zh ?? Localizations.localeOf(context).languageCode == 'zh');

  @override
  Widget build(BuildContext context) {
    final s = _strings(context);
    if (live case final output?) {
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _LiveStats(output: output, since: since, strings: s),
        ),
      );
    }
    final stats = <Widget>[
      if (worked case final value?)
        _Stat(icon: _clockIcon, text: s.duration(value), hint: s.durationHint),
      if (usage?.tokensPerSecond case final speed?)
        _Stat(icon: _zapIcon, text: s.speed(speed), hint: s.speedHint),
      if (usage?.costUsd case final cost?)
        _Stat(text: formatCost(cost), hint: s.costHint),
      if (usage?.totalTokens case final tokens? when tokens > 0)
        _Stat(
          text: s.tokens(tokens),
          hint: s.tokenBreakdown(
            AgentStep.formatTokens(usage?.inputTokens ?? 0),
            AgentStep.formatTokens(usage?.outputTokens ?? 0),
          ),
        ),
    ];
    final hasActions = answer != null || action != null;
    final statsView = Padding(
      padding: EdgeInsets.symmetric(vertical: hasActions ? 0 : 4),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: _statGap,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: stats,
      ),
    );
    if (answer != null && action == null) {
      // 复制图标与正文左对齐，统计紧随其后（间距大于统计项之间）；
      // 复制的点击区仍是完整的 40×40，叠在统计开头之上。
      return SelectionContainer.disabled(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: FooterIconButton.iconSize + _copyGap,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: FooterIconButton.hitSize,
                ),
                child: Row(children: [Expanded(child: statsView)]),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CopyButton(text: answer!, strings: s),
              ),
            ),
          ],
        ),
      );
    }
    return SelectionContainer.disabled(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (answer != null)
            _CopyButton(
              text: answer!,
              strings: s,
              // Tight when a button follows, so the icons sit ~12dp apart.
              width: 28,
            ),
          ?action,
          Expanded(child: statsView),
        ],
      ),
    );
  }
}

/// 统计项之间的间距；复制图标到统计的间距 [_copyGap] 要比它大。
const _statGap = 12.0;
const _copyGap = 20.0;

/// A footer icon button: a 16px icon whose visual left edge is the box's
/// left edge (so it lines up with the text above), inside a transparent hit
/// area of at least 40 high and [width] wide.
class FooterIconButton extends StatelessWidget {
  const FooterIconButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.width = hitSize,
  });

  static const hitSize = 40.0;
  static const iconSize = 16.0;

  final Widget child;
  final VoidCallback onPressed;
  final String? tooltip;
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: hitSize,
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

class _LiveStats extends StatefulWidget {
  const _LiveStats({required this.output, required this.strings, this.since});
  final TurnOutput output;
  final DateTime? since;
  final TurnStrings strings;
  @override
  State<_LiveStats> createState() => _LiveStatsState();
}

class _LiveStatsState extends State<_LiveStats> {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_LiveStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.since != oldWidget.since) _follow();
  }

  void _follow() {
    _ticker?.cancel();
    final since = widget.since;
    if (since == null) return;
    final past = DateTime.now().difference(since).inMilliseconds % 1000;
    _ticker = Timer(Duration(milliseconds: 1000 - past), () {
      if (!mounted) return;
      setState(() {});
      _follow();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final output = widget.output;
    final since = widget.since;
    return Wrap(
      spacing: _statGap,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (since != null)
          _Stat(
            icon: _clockIcon,
            text: AgentStep.formatDuration(
              _nonNegative(DateTime.now().difference(since)),
              strings: AgentStrings(s.zh),
            ),
            hint: s.durationHint,
            live: true,
          ),
        if (output.tokensPerSecond case final speed?)
          _Stat(
            icon: _zapIcon,
            text: s.speed(speed),
            hint: s.liveSpeedHint,
            live: true,
          ),
        if (output.tokens > 0)
          _Stat(
            icon: _arrowDownIcon,
            text: s.tokens(output.tokens),
            hint: s.liveTokensHint,
            live: true,
          ),
      ],
    );
  }

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}

class _Stat extends StatelessWidget {
  const _Stat({
    this.icon,
    required this.text,
    required this.hint,
    this.live = false,
  });
  final String? icon;
  final String text;
  final String hint;
  final bool live;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: MobileTheme.asideAlpha);
    return Tooltip(
      message: hint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final path?) ...[
            SvgPicture.asset(
              path,
              width: MobileType.aside,
              height: MobileType.aside,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(width: 3),
          ],
          if (live)
            Flexible(
              child: RollingText(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: MobileType.aside,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          else
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: MobileType.aside),
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.text,
    required this.strings,
    this.width = FooterIconButton.hitSize,
  });
  final String text;
  final double width;
  final TurnStrings strings;
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> with CopyFeedback {
  void _copy() => copyText(widget.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = copied ? widget.strings.copied : widget.strings.copy;
    return FooterIconButton(
      tooltip: label,
      onPressed: _copy,
      width: widget.width,
      child: SvgPicture.asset(
        copied ? _checkIcon : _copyIcon,
        width: FooterIconButton.iconSize,
        height: FooterIconButton.iconSize,
        colorFilter: ColorFilter.mode(
          copied ? scheme.primary : scheme.onSurfaceVariant,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
