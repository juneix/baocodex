import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../chat_models.dart';
import '../markdown/markdown_view.dart';
import 'step_header.dart';
import 'thinking_spark.dart';

/// The activity row's strings, both languages inline: the desktop reads
/// them from `AppLocalizations`; the mobile has no l10n class, and the
/// widget sits below where an `AppState` would reach.
class ActivityStrings {
  const ActivityStrings._(this.zh);

  /// From [zh]: the app's language setting decides.
  factory ActivityStrings(bool zh) => zh ? zhCN : en;

  static const zhCN = ActivityStrings._(true);
  static const en = ActivityStrings._(false);

  final bool zh;

  List<String> get musings =>
      (zh
              ? '冥思苦想\n琢磨一下\n慢慢酝酿\n深思熟虑\n文火慢炖\n修修补补\n融会贯通\n反复掂量\n连点成线\n追一个直觉\n酝酿计划\n孵化方案\n权衡利弊\n理清头绪\n赶着一群 token\n召唤上下文\n请教小黄鸭\n在餐巾纸上打草稿\n眯眼看 diff\n数括号\n和编译器交朋友\n与类型系统谈判\n驯服边界情况\n追踪调用栈\n翻阅文档\n探索代码库\n摇一摇魔法 8 号球\n绑定 Monad\n求问神谕\n打磨计划\n打个腹稿\n掐指一算\n抽丝剥茧\n顺藤摸瓜\n在脑子里跑一遍\n把思路捋直\n拆解问题'
              : 'Pondering\nNoodling\nPercolating\nCogitating\nSimmering\nMarinating\nTinkering\nGrokking\nMulling it over\nConnecting the dots\nChasing a hunch\nBrewing a plan\nHatching a plan\nWeighing the options\nUntangling threads\nHerding tokens\nSummoning context\nAsking the rubber duck\nReading the tea leaves\nSketching on a napkin\nDoodling in the margins\nSquinting at the diff\nCounting parentheses\nBefriending the compiler\nNegotiating with types\nWrangling edge cases\nTracing the stack\nFlipping through the docs\nSpelunking the codebase\nLining up the ducks\nShaking the magic 8-ball\nWarming up the neurons\nFolding thoughts\nBinding the monad\nAsking the oracle\nStirring the pot\nPolishing the plan')
          .split('\n');

  List<String> cuedMusings(MusingCue cue) {
    final name = cue.name;
    return switch (cue.topic) {
      MusingTopic.command =>
        (zh
                ? '对着 $name 的输出点点头\n品一品 $name 的输出\n给 $name 的输出划重点\n看 $name 跑出了什么名堂\n把 $name 的结果过一遍'
                : 'Squinting at $name\'s output\nDigesting what $name said\nPicking through $name\'s output\nNodding along to $name')
            .split('\n'),
      MusingTopic.commandFailed =>
        (zh
                ? '和 $name 的报错大眼瞪小眼\n盯着 $name 的报错挠头\n给 $name 的报错号号脉\n琢磨 $name 为什么不高兴\n顺着 $name 的报错往回找'
                : 'Staring down $name\'s error\nAsking $name what went wrong\nUntangling $name\'s complaint\nConsoling $name')
            .split('\n'),
      MusingTopic.read =>
        (zh
                ? '把 $name 翻来覆去地看\n在 $name 里找线头\n跟 $name 混个脸熟\n在 $name 的字里行间找答案\n把 $name 记在心里'
                : 'Leafing through $name\nGetting to know $name\nPulling threads in $name\nReading between the lines of $name')
            .split('\n'),
      MusingTopic.edit =>
        (zh
                ? '欣赏刚改好的 $name\n替 $name 捏把汗\n回头再瞄一眼 $name\n想想 $name 还缺点啥\n给 $name 收个尾'
                : 'Admiring the new $name\nDouble-checking $name\nHoping $name still compiles\nGiving $name a once-over')
            .split('\n'),
      MusingTopic.search =>
        (zh
                ? '在 $name 处结果里淘金\n从 $name 处结果里挑出真身\n顺着 $name 条线索摸过去'
                : 'Panning $name results for gold\nSifting through $name matches\nFollowing $name leads')
            .split('\n'),
      MusingTopic.folder =>
        (zh
                ? '在 $name 里东张西望\n给 $name 点个名\n摸清 $name 的家底'
                : 'Poking around $name\nTaking roll call in $name\nSizing up $name')
            .split('\n'),
      MusingTopic.web =>
        (zh
                ? '从 $name 抄点笔记\n消化 $name 上看来的东西'
                : 'Taking notes from $name\nDigesting $name')
            .split('\n'),
      MusingTopic.agent =>
        (zh
                ? '听 $name 汇报\n批改 $name 交上来的作业\n消化 $name 带回来的情报'
                : 'Debriefing $name\nGrading $name\'s homework\nGoing over $name\'s findings')
            .split('\n'),
      MusingTopic.mcp =>
        (zh
                ? '拆 $name 寄回来的包裹\n看 $name 回了些什么'
                : 'Unwrapping $name\'s reply\nSeeing what $name sent back')
            .split('\n'),
      MusingTopic.browser =>
        (zh
                ? '端详页面截图\n看看浏览器里发生了什么'
                : 'Peering at the page\nSquinting at the screenshot')
            .split('\n'),
      MusingTopic.image =>
        (zh
                ? '端详刚画好的图\n给新图挑挑刺'
                : 'Admiring the fresh picture\nNitpicking the new image')
            .split('\n'),
      MusingTopic.denied =>
        (zh ? '收到，换条路走\n另想办法' : 'Finding another way\nTaking the scenic route')
            .split('\n'),
    };
  }

  /// A session's activity label (the desktop names them in English) in this
  /// language; others as given.
  String label(String label) => switch (label) {
    'Compacting conversation' => zh ? '正在压缩对话' : label,
    'Planning next move' => zh ? '正在规划下一步' : label,
    _ => label,
  };
}

/// What the agent is busy with out of sight, after Claude's spark: typed
/// out, then dots counting up behind it ("Compacting conversation..").
/// [whimsical] (a wait with nothing to name, the model yet to answer), it
/// muses instead, a passing phrase at a time: mostly on the step just done,
/// if [cue] says what that was, else on anything.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.strings,
    required this.label,
    this.whimsical = false,
    this.visible = true,
    this.cue,
    this.random,
  });

  /// Both languages' phrases, per the app's language.
  final ActivityStrings strings;
  final String label;
  final bool whimsical;

  /// Whether it shows: it opens and fades in, or folds and fades out.
  final bool visible;

  /// The step just done, to muse on.
  final MusingCue? cue;

  /// Picks the phrases; tests seed it.
  final math.Random? random;

  @override
  Widget build(BuildContext context) {
    return _Reveal(visible: visible, child: _row());
  }

  Widget _row() {
    return Align(
      alignment: Alignment.centerLeft,
      // Lined up with the steps around it.
      child: Padding(
        padding: const EdgeInsets.only(top: 9, bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SelectionContainer.disabled(child: ThinkingSpark(size: 15)),
            const SizedBox(width: 6),
            Flexible(
              child: _Musing(
                whimsical ? strings.musings : [strings.label(label)],
                cued: switch (cue) {
                  final cue? when whimsical => strings.cuedMusings(cue),
                  _ => const [],
                },
                // Folding away, it goes on as it was.
                frozen: !visible,
                random: random,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] opening and fading in while [visible], folding and fading out
/// while not; not built at all once folded, so it begins anew each time it
/// shows. At once where motion is turned down.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_Reveal old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _follow();
  }

  void _follow() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => _controller.isDismissed
          ? const SizedBox(width: double.infinity)
          : SizeTransition(
              sizeFactor: _eased,
              alignment: Alignment.topLeft,
              child: FadeTransition(opacity: _eased, child: child),
            ),
      child: widget.child,
    );
  }
}

/// [phrases], one at a time from any (or from [cued], [cuedShare] of the
/// time, when there are any): a caret types each out from the
/// start, a letter fading in at a time, unevenly, as a hand would; then dots
/// fade in behind it, up to three, twice; then it fades for the next. One
/// phrase is typed once, then only counts its dots. Still, and whole, where
/// motion is turned down.
///
/// The phrase and its dots are laid out whole from the start, what is yet to
/// show see-through: the line keeps its width, and the caret its places.
class _Musing extends StatefulWidget {
  const _Musing(
    this.phrases, {
    this.cued = const [],
    this.frozen = false,
    this.random,
  });

  final List<String> phrases;

  /// Phrases on the step just done.
  final List<String> cued;

  /// Whether it keeps to the phrases it has, whatever it is given.
  final bool frozen;

  final math.Random? random;

  /// How often it picks from [cued].
  static const cuedShare = 0.7;

  @override
  State<_Musing> createState() => _MusingState();
}

class _MusingState extends State<_Musing> with SingleTickerProviderStateMixin {
  // Times in milliseconds.

  /// The caret alone at the start, before the first letter.
  static const _lead = 60;

  /// A letter's time to fade in, and the caret's to glide past it.
  static const _fadeIn = 70;
  static const _glide = 40;

  /// The caret at the end of the phrase: it blinks twice, and is gone.
  static const _blink = 500;
  static const _rest = _blink * 3 ~/ 2;

  /// A dot every step, three to a round, faded out at its end.
  static const _dotStep = 400;
  static const _dotFade = 140;
  static const _round = _dotStep * 4;
  static const _rounds = 2;

  /// The phrase fading for the next.
  static const _clear = 240;

  static const _dots = '...';

  /// The agent's prose's color, at the size of the steps (e.g. Thinking).
  static TextStyle get _style => TextStyle(
    color: MarkdownView.baseStyle.color,
    fontSize: StepHeader.fontSize,
  );

  late final math.Random _random = widget.random ?? math.Random();
  late List<String> _phrases = widget.phrases;
  late List<String> _cued = widget.cued;
  late String _phrase;

  /// When each letter of the phrase is typed; empty once it has been, for a
  /// phrase that stays.
  List<int> _typed = const [];
  bool _still = false;
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_advance);

  bool get _rolls => _phrases.length + _cued.length > 1;
  bool get _typing => _typed.isNotEmpty;

  /// When the caret is gone and the dots begin.
  int get _dotsAt => _typing ? _typed.last + _glide + _rest : 0;
  int get _clearAt => _dotsAt + _round * _rounds;
  int get _cycle => _clearAt + (_rolls ? _clear : 0);

  @override
  void initState() {
    super.initState();
    _pick(_draw());
  }

  @override
  void didUpdateWidget(_Musing old) {
    super.didUpdateWidget(old);
    if (widget.frozen ||
        (listEquals(widget.phrases, _phrases) &&
            listEquals(widget.cued, _cued))) {
      return;
    }
    _phrases = widget.phrases;
    _cued = widget.cued;
    // Said on to its end while it still holds.
    if (_phrases.contains(_phrase) || _cued.contains(_phrase)) return;
    _pick(_draw());
    if (_controller.isAnimating) _start();
  }

  /// A phrase to say: from [_Musing.cued] as often as it says, if any; not
  /// [not] where there are others.
  String _draw({String? not}) {
    final from = _cued.isNotEmpty && _random.nextDouble() < _Musing.cuedShare
        ? _cued
        : _phrases;
    final avoid = not == null ? -1 : from.indexOf(not);
    if (avoid < 0 || from.length < 2) return from[_random.nextInt(from.length)];
    final pick = _random.nextInt(from.length - 1);
    return from[pick < avoid ? pick : pick + 1];
  }

  /// Shows [phrase] next, typed out: a letter every 12 to 28ms, a beat
  /// longer after a space.
  void _pick(String phrase) {
    _phrase = phrase;
    final typed = <int>[];
    var at = _lead;
    for (var i = 0; i < _phrase.length; i++) {
      typed.add(at);
      at += 12 + _random.nextInt(16) + (_phrase[i] == ' ' ? 25 : 0);
    }
    _typed = typed;
  }

  void _start() {
    _controller
      ..duration = Duration(milliseconds: _cycle)
      ..forward(from: 0);
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      if (_rolls) {
        _pick(_draw(not: _phrase));
      } else {
        _typed = const [];
      }
    });
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Where the caret goes after each letter, and its line: laid out again
  // only when the phrase, its style or its room change.
  (String, TextStyle, TextScaler, double)? _laidOutFor;
  List<double> _carets = const [];
  double _baseline = 0;
  double _fontSize = 0;

  void _layOut(String text, TextStyle style, TextScaler scaler, double width) {
    final key = (text, style, scaler, width);
    if (key == _laidOutFor) return;
    _laidOutFor = key;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: width);
    _carets = [
      for (var i = 0; i <= _phrase.length; i++)
        painter.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx,
    ];
    _baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    _fontSize = scaler.scale(style.fontSize ?? StepHeader.fontSize);
    painter.dispose();
  }

  static double _unit(num value) => value.clamp(0, 1).toDouble();

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_style);
    if (_still) {
      return Text(
        _phrase,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final color =
        style.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = '$_phrase$_dots';
        _layOut(text, style, scaler, constraints.maxWidth);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * _cycle;
            final fade = _rolls ? 1 - _unit((t - _clearAt) / _clear) : 1.0;
            // The dots in the round under way; none before, and gone after.
            final round = t - _dotsAt;
            final inRound = round < 0 || round >= _round * _rounds
                ? -1.0
                : round % _round;
            double dot(int k) => inRound < 0
                ? 0
                : _unit((inRound - (k + 1) * _dotStep) / _dotFade) *
                      _unit((_round - inRound) / 100);
            final spans = [
              for (var i = 0; i < _phrase.length; i++)
                TextSpan(
                  text: _phrase[i],
                  style: TextStyle(
                    color: color.withValues(
                      alpha:
                          color.a *
                          fade *
                          (_typing ? _unit((t - _typed[i]) / _fadeIn) : 1),
                    ),
                  ),
                ),
              for (var k = 0; k < _dots.length; k++)
                TextSpan(
                  text: _dots[k],
                  style: TextStyle(
                    color: color.withValues(alpha: color.a * fade * dot(k)),
                  ),
                ),
            ];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Text.rich(
                  TextSpan(children: spans),
                  style: style,
                  textScaler: scaler,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_typing && t < _dotsAt) _caret(t),
              ],
            );
          },
        );
      },
    );
  }

  /// The caret after the last letter typed, gliding on from the one before;
  /// fading in at the start, then steady while it types, then blinking at
  /// its rest. As tall as the letters and centered on them, from the
  /// baseline: the line's box has room below them (and more, falling back
  /// on a font for Han).
  Widget _caret(double t) {
    final last = _typed.lastIndexWhere((at) => at <= t);
    final x = last < 0
        ? _carets.first
        : _carets[last] +
              (_carets[last + 1] - _carets[last]) *
                  Curves.easeOutCubic.transform(
                    _unit((t - _typed[last]) / _glide),
                  );
    // On for half of each blink, its edges soft.
    final resting = t - (_dotsAt - _rest);
    final blink = resting % _blink;
    final opacity =
        _unit(t / 80) *
        (resting < 0
            ? 1
            : blink < _blink / 2
            ? _unit((_blink / 2 - blink) / 60)
            : _unit((blink - (_blink - 60)) / 60));
    final height = _fontSize;
    return Positioned(
      key: const ValueKey('cursor'),
      left: x + 3,
      top: _baseline - _fontSize * 0.35 - height / 2,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 2,
          height: height,
          decoration: BoxDecoration(
            color: _style.color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
