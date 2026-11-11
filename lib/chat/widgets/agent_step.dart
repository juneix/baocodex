import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'chat_item_view.dart' show chatItemPlainText;
import 'flip_switcher.dart';
import 'pixel_loader.dart';
import 'shimmer_text.dart';
import 'strings.dart';
import 'tool_call_row.dart';
import '../../theme/app_theme.dart';

/// A subagent's strings, both languages inline (see [ToolStrings]).
class AgentStrings {
  const AgentStrings._(this.zh);

  /// Per the platform locale; a call site with an `AppState` passes
  /// `AgentStrings(state.tr('中', 'en') == '中')`.
  factory AgentStrings.standard() => AgentStrings(localeIsZh);

  factory AgentStrings(bool zh) => zh ? zhCN : en;

  static const zhCN = AgentStrings._(true);
  static const en = AgentStrings._(false);

  final bool zh;

  String tokens(String formatted) =>
      zh ? '$formatted token' : '$formatted tokens';
  String toolCount(int count) => zh ? '$count 个工具' : '$count tools';
  String durationSeconds(int seconds) => zh ? '$seconds秒' : '${seconds}s';
  String durationMinutesSeconds(int minutes, int seconds) =>
      zh ? '$minutes分$seconds秒' : '${minutes}m ${seconds}s';
  String durationHoursMinutes(int hours, int minutes) =>
      zh ? '$hours小时$minutes分' : '${hours}h ${minutes}m';
  String get running => zh ? '运行中' : 'running';
  String get runningInBackground => zh ? '在后台运行' : 'running in the background';
  String get done => zh ? '已完成' : 'done';
  String get failed => zh ? '失败' : 'failed';
  String get opensItsConversation => zh ? '打开其对话' : 'Opens its conversation';
}

/// A subagent as a card, a line: what it was given to do, then what it did
/// last, flipping up to the next as it goes on, and once done to how it
/// went ("Explore · 55s · 5 tools · 8.2k tokens"). A tap opens its own
/// conversation ([onOpen]), where the rest is.
///
/// Mobile adaptation of the desktop card: no hover or keyboard focus (the
/// tap arbitrates with selection by duration, as [StepHeader] does), and
/// the desktop's `IdeHover` tooltips become nothing.
class AgentStep extends StatefulWidget {
  const AgentStep({super.key, required this.item, this.onOpen, this.strings});

  final AgentItem item;
  final VoidCallback? onOpen;

  final AgentStrings? strings;

  /// Its kind and progress, e.g. "Explore · 69s · 12 tools · 8.2k tokens".
  static String meta(AgentItem item, {DateTime? now, AgentStrings? strings}) {
    final s = strings ?? AgentStrings.standard();
    return [
      ?item.agentType,
      if (elapsed(item, now: now) case final time?)
        formatDuration(time, strings: s),
      ?tools(item, strings: s),
      if (item.tokens case final tokens? when tokens > 0)
        s.tokens(formatTokens(tokens)),
    ].join(' · ');
  }

  /// How long it ran, or has been running.
  static Duration? elapsed(AgentItem item, {DateTime? now}) =>
      item.duration ??
      switch ((item.status, item.startedAt)) {
        (CommandStatus.running, final start?) =>
          (now ?? DateTime.now()).difference(start),
        _ => null,
      };

  /// "46s", "2m 14s", "1h 5m".
  static String formatDuration(Duration time, {AgentStrings? strings}) {
    final s = strings ?? AgentStrings.standard();
    final seconds = time.inSeconds;
    if (seconds < 60) return s.durationSeconds(seconds);
    if (seconds < 3600) {
      return s.durationMinutesSeconds(seconds ~/ 60, seconds % 60);
    }
    return s.durationHoursMinutes(seconds ~/ 3600, seconds % 3600 ~/ 60);
  }

  /// "950", "8.2k", "202k", "3.6M": one line on a phone, one rounding
  /// everywhere. Four digits keep a decimal, five get whole thousands.
  static String formatTokens(int tokens) => switch (tokens) {
    < 1000 => '$tokens',
    < 10000 => '${(tokens / 1000).toStringAsFixed(1)}k',
    < 1000000 => '${(tokens / 1000).round()}k',
    _ => '${(tokens / 1000000).toStringAsFixed(1)}M',
  };

  /// The tools it has used, e.g. "12 tools"; null before the first.
  static String? tools(AgentItem item, {AgentStrings? strings}) =>
      switch (item.toolUses) {
        final uses? when uses > 0 =>
          (strings ?? AgentStrings.standard()).toolCount(uses),
        _ => null,
      };

  /// What it did last, in a line, e.g. "Ran Find reusable helpers"; what
  /// it was asked before it does anything. Null with nothing to say.
  static String? latest(AgentItem item, {ToolStrings? toolStrings}) {
    for (final child in item.children.reversed) {
      if (_firstLine(chatItemPlainText(child, strings: toolStrings))
          case final line?) {
        return line;
      }
    }
    return _firstLine(item.activity) ?? _firstLine(item.prompt);
  }

  /// What follows its description: while it runs, what it did last; once
  /// done, how it went. Null with nothing to say.
  static String? trailing(AgentItem item, {ToolStrings? toolStrings}) =>
      switch (item.status) {
        CommandStatus.running => latest(item, toolStrings: toolStrings),
        _ => switch (meta(item)) {
          '' => null,
          final meta => meta,
        },
      };

  /// The first line of [text] with anything in it, out of its markdown's
  /// heading and emphasis marks.
  static String? _firstLine(String? text) {
    if (text == null) return null;
    for (final line in text.split('\n')) {
      final plain = line
          .replaceFirst(RegExp(r'^\s*(#+|[-*•]|>)\s+'), '')
          .replaceAll('**', '')
          .trim();
      if (plain.isNotEmpty) return plain;
    }
    return null;
  }

  /// The card as text, for copying: as it reads.
  static String plainText(AgentItem item, {ToolStrings? toolStrings}) => [
    item.description,
    if (trailing(item, toolStrings: toolStrings) case final trailing?)
      '· $trailing',
  ].join(' ');

  @override
  State<AgentStep> createState() => _AgentStepState();
}

const _titleStyle = TextStyle(
  fontSize: MobileType.secondary,
  fontWeight: FontWeight.w500,
);

/// Its line's height, whatever fonts its text falls back on (CJK's run
/// taller than Latin's): it keeps its height as what follows changes.
const _lineStrut = StrutStyle(
  fontSize: MobileType.secondary,
  height: 1.4,
  forceStrutHeight: true,
);

class _AgentStepState extends State<AgentStep> {
  /// A press that may open it: plain and quick.
  Offset? _down;
  DateTime? _downAt;

  void _open() => widget.onOpen?.call();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final running = item.status == CommandStatus.running;
    final strings = widget.strings ?? AgentStrings.standard();
    final toolStrings = ToolStrings(strings.zh);
    final trailing = AgentStep.trailing(item, toolStrings: toolStrings);
    final open = widget.onOpen;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: Row(
        children: [
          AgentStatusIcon(
            item.status,
            background: item.background,
            strings: strings,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  // Shimmers while it works.
                  Flexible(
                    child: running
                        ? ShimmerText(
                            item.description,
                            ellipsis: false,
                            padding: EdgeInsets.zero,
                            style: _titleStyle,
                            strutStyle: _lineStrut,
                          )
                        : Text(
                            item.description,
                            strutStyle: _lineStrut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                  ),
                  if (trailing != null)
                    // At most half the line, the description having the
                    // rest.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth / 2,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: FlipSwitcher(
                          child: Text(
                            '· $trailing',
                            key: ValueKey(trailing),
                            strutStyle: _lineStrut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: MobileTheme.asideAlpha,
                              ),
                              fontSize: MobileType.aside,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (open != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right_rounded, size: 18),
            ),
        ],
      ),
    );
    final status = switch (item.status) {
      CommandStatus.running when item.background => strings.runningInBackground,
      CommandStatus.running => strings.running,
      CommandStatus.succeeded => strings.done,
      CommandStatus.failed => strings.failed,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Semantics(
        container: true,
        button: open != null,
        label: '${item.description}，$status',
        hint: open == null ? null : strings.opensItsConversation,
        child: Listener(
          // Listens rather than joins the gesture arena, so selecting its
          // text still works: a plain tap opens it, a drag or the
          // selection's long-press does not.
          onPointerDown: (event) {
            _downAt = null;
            _down = open != null && event.buttons == kPrimaryButton
                ? event.position
                : null;
            if (_down != null) _downAt = DateTime.now();
          },
          onPointerMove: (event) {
            final down = _down;
            if (down != null && (event.position - down).distance > 4) {
              _down = null;
            }
          },
          onPointerUp: (_) {
            final down = _down;
            final at = _downAt;
            _down = null;
            _downAt = null;
            if (down == null || at == null) return;
            if (DateTime.now().difference(at) >=
                const Duration(milliseconds: 300)) {
              return;
            }
            _open();
          },
          onPointerCancel: (event) {
            _down = null;
            _downAt = null;
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: open != null
                    ? scheme.primary.withValues(alpha: dark ? 0.6 : 0.45)
                    : scheme.outlineVariant,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Running, done or failed, as a 14 px mark: running as pixels filling up,
/// in the foreground or the background alike.
class AgentStatusIcon extends StatelessWidget {
  const AgentStatusIcon(
    this.status, {
    super.key,
    this.background = false,
    required this.strings,
  });

  final CommandStatus status;
  final bool background;
  final AgentStrings strings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: 14,
      child: switch (status) {
        CommandStatus.running => const PixelLoader.subagent(),
        // As upstream's session status.
        CommandStatus.succeeded => Icon(
          Icons.check_circle_outline_rounded,
          size: 14,
          color: Color(dark ? 0xFF2EA043 : 0xFF1A7F37),
        ),
        CommandStatus.failed => Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: Color(dark ? 0xFFF85149 : 0xFFCF222E),
        ),
      },
    );
  }
}
