import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../markdown/finite_selection_edges.dart';
import '../../theme/app_theme.dart';
import 'agent_step.dart' show AgentStep, AgentStrings;
import 'edge_fade_mask.dart';
import 'live_selectable_text.dart';
import 'step_header.dart';
import 'strings.dart';

/// A thought's strings, both languages inline (see [ToolStrings]).
class ThinkingStrings {
  const ThinkingStrings._(this.zh);

  factory ThinkingStrings(bool zh) => zh ? zhCN : en;

  factory ThinkingStrings.standard() => ThinkingStrings(localeIsZh);

  static const zhCN = ThinkingStrings._(true);
  static const en = ThinkingStrings._(false);

  final bool zh;

  String get thinking => zh ? '正在思考' : 'Thinking';
  String get thought => zh ? '已思考' : 'Thought';
  String get briefly => zh ? '片刻' : 'briefly';
}

/// Header of a thought: while it streams, how long so far ([elapsed], at
/// least "Thinking 1s"); then how long it took, "Thought 2s" or, under a
/// second, "Thought briefly".
String thinkingTitle({
  required int? seconds,
  Duration? elapsed,
  ThinkingStrings? strings,
}) => switch (thinkingParts(seconds, elapsed: elapsed, strings: strings)) {
  (final verb, final object) => StepHeader.text(verb, object),
};

(String, String) thinkingParts(
  int? seconds, {
  Duration? elapsed,
  ThinkingStrings? strings,
}) {
  final s = strings ?? ThinkingStrings.standard();
  String took(int seconds) => AgentStep.formatDuration(
    Duration(seconds: seconds),
    strings: AgentStrings(s.zh),
  );
  return switch ((seconds, elapsed)) {
    (null, final elapsed?) => (
      s.thinking,
      took(math.max(1, elapsed.inSeconds)),
    ),
    (null, null) => (s.thinking, ''),
    (final int seconds, _) when seconds < 1 => (s.thought, s.briefly),
    (final int seconds, _) => (s.thought, took(seconds)),
  };
}

/// A summarized thought (OpenAI's, say) in its parts: its first line, all
/// bold (`**Planning the fix**`), is its title, the rest its body. While it
/// streams the title may lack its closing stars. Null for a thought whose
/// first line is not a bold one.
///
/// A thought of many parts, each titled, is headed by its latest part's
/// title, as far as it has got; the titles all read as lines of its body.
({String title, String body})? thoughtSummary(String text) {
  final trimmed = text.trimLeft();
  final match = _summaryTitle.firstMatch(trimmed);
  if (match == null) return null;
  final title = match[1]!.trim();
  if (title.isEmpty) return null;
  final body = match[2]?.trim() ?? '';
  final later = _partTitle.allMatches(body).lastOrNull;
  if (later == null) return (title: title, body: body);
  return (
    title: later[1]!.trim(),
    body: trimmed.trim().replaceAllMapped(_partTitle, (m) => m[1]!),
  );
}

final _summaryTitle = RegExp(
  r'^\*\*([^*\n]*)(?:\*{0,2}[ \t]*$|\*\*[ \t]*\n([\s\S]*))',
);
final _partTitle = RegExp(r'^\*\*([^*\n]+)\*\*[ \t]*$', multiLine: true);

/// Collapsible thought. While it streams ([seconds] is null) its text sits
/// in a box of limited height that follows the newest lines, fading out at
/// the top over earlier ones; once done it shows in full. Mobile
/// adaptation: no wheel latch or smooth scroll (touch scrolling needs
/// neither); the follow keeps while the view sits at the bottom.
class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    super.key,
    required this.text,
    required this.seconds,
    required this.expanded,
    required this.onToggle,
    this.startedAt,
  });

  final String text;
  final int? seconds;

  /// When it began: while it streams, its time so far counts up.
  final DateTime? startedAt;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection> {
  /// 官方思考正文 13，比消息正文小一号；同样跟随“消息阅读”倍率。
  TextStyle _textStyle(BuildContext context) =>
      MobileTheme.messageStyleOf(context).copyWith(
        fontSize: MobileType.secondary * MobileTheme.messageScaleOf(context),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  final _scrollController = ScrollController();
  bool _contentAbove = false;

  bool get _streaming => widget.seconds == null;

  /// Ticks the time shown while it streams.
  Timer? _clock;

  void _syncClock() {
    final ticking = _streaming && widget.startedAt != null;
    if (ticking == (_clock != null)) return;
    _clock?.cancel();
    _clock = ticking
        ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}))
        : null;
  }

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  /// A summarized thought's title and body, or null for a thought in full.
  ({String title, String body})? get _summary => thoughtSummary(widget.text);

  /// What it shows open: a summarized thought's body, else its text, without
  /// the blank lines thoughts end with.
  String get _text => _summary?.body ?? widget.text.trimRight();

  @override
  void didUpdateWidget(ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
    if (widget.text == oldWidget.text || !_scrollController.hasClients) return;
    // Follow new lines, unless scrolled up to read earlier ones.
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Content scrolled (or grown and followed) past the top shows the mask.
  bool _handleScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics) => metrics,
      ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };
    if (metrics == null) return false;
    final above = metrics.pixels > 0.5;
    if (above != _contentAbove) setState(() => _contentAbove = above);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Full width: the history centers each item in its column, and the text
    // alone would not fill it.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            // Nothing to show until its first words (a summarized thought
            // may bring them only at its end).
            child: widget.expanded && _text.isNotEmpty
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6, bottom: 2),
                    child: _streaming
                        ? _buildLiveText(context)
                        : Text(_text, style: _textStyle(context)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // A summarized thought is headed by its title alone, as a command by its
    // description.
    if (_summary case (:final title, body: _)) {
      return StepHeader(
        verb: '',
        object: title,
        bold: true,
        running: _streaming,
        expanded: widget.expanded,
        onToggle: _text.isEmpty ? null : widget.onToggle,
      );
    }
    final (verb, object) = thinkingParts(
      widget.seconds,
      elapsed: switch (widget.startedAt) {
        final start? when _streaming => DateTime.now().difference(start),
        _ => null,
      },
    );
    return StepHeader(
      verb: verb,
      object: object,
      running: _streaming,
      expanded: widget.expanded,
      // Nothing to open until its first words.
      onToggle: _text.isEmpty ? null : widget.onToggle,
    );
  }

  Widget _buildLiveText(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.textScalerOf(context)
                .scale(_textStyle(context).fontSize!) *
            1.6 *
            7,
      ),
      child: NotificationListener<Notification>(
        onNotification: _handleScroll,
        child: EdgeFadeMask(
          top: _contentAbove,
          bottom: false,
          fadeLength: 24,
          fadeOffset: 2,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _scrollController,
              // Selectable text that keeps its selection as it grows.
              child: FiniteSelectionEdges(
                child: SizedBox(
                  width: double.infinity,
                  child: LiveSelectableText(_text, style: _textStyle(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
