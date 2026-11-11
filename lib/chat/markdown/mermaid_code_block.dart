import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../theme/app_theme.dart';
import '../../ui/widgets/copy_feedback.dart';
import '../chat_models.dart' show ImageAttachment;
import 'code_citation.dart';

/// Native, offline Mermaid rendering, with the ordinary code block as fallback.
/// Shown whole, a right click's menu and its copy are a picture's.
class MermaidCodeBlock extends StatefulWidget {
  const MermaidCodeBlock({super.key, required this.code, this.writing = false});

  final String code;

  /// Whether its fence is still being written (a reply streaming in): a
  /// picture's placeholder shows, not its source half written, until it
  /// is closed or [quietFor] goes by without more.
  final bool writing;

  /// How long a fence left open is still taken to be being written.
  static const quietFor = Duration(seconds: 3);

  @override
  State<MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<MermaidCodeBlock> with CopyFeedback {
  Timer? _pending;
  mermaid.MermaidTheme? _theme;
  mermaid.RenderScene? _scene;

  /// A tall top-down flowchart drawn left to right too, for a column it
  /// fits less tall (see [_shown]).
  mermaid.RenderScene? _across;
  bool _showSource = false;
  bool _hovered = false;

  /// Whether [MermaidCodeBlock.writing] has gone quiet (see [_quiet]).
  bool _stale = false;
  Timer? _quiet;

  /// The picture of the scene shown, once asked for (see [_picture]).
  (mermaid.RenderScene, Future<ImageAttachment>)? _pictured;

  bool get _writing => widget.writing && !_stale;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Takes the fence as no longer being written once it goes quiet.
  void _listen() {
    _quiet?.cancel();
    _stale = false;
    if (!widget.writing) return;
    _quiet = Timer(MermaidCodeBlock.quietFor, () {
      if (mounted) setState(() => _stale = true);
    });
  }

  @override
  void didUpdateWidget(MermaidCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.writing != widget.writing) {
      _listen();
      // Closed: drawn at once, not its source shown a moment first.
      _theme = null;
    }
    if (oldWidget.code == widget.code) return;
    if (widget.writing) _listen();
    _pending?.cancel();
    // Never label the previous diagram as the current, partially written source.
    _scene = null;
    _across = null;
    _pending = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        if (_theme case final theme?) _render(theme);
      });
    });
  }

  void _render(mermaid.MermaidTheme theme) {
    _theme = theme;
    _scene = _layout(widget.code, theme);
    _across = null;
    final size = _scene?.size;
    if (size == null || size.height <= size.width || size.height < 240) return;
    if (mermaidAcross(widget.code) case final across?) {
      _across = _layout(across, theme);
    }
  }

  /// [code] laid out, a flowchart's labelled links read as mermaid.js reads
  /// them (see [mermaidLinksSpaced]) and its lines square where it is small
  /// enough (see [mermaidSquare]), and its text as it reads (see
  /// [mermaidUnescaped]); null for none.
  mermaid.RenderScene? _layout(String code, mermaid.MermaidTheme theme) {
    // Layout is synchronous: bound input before asking the native engine.
    if (code.length > 16000 || '\n'.allMatches(code).length > 200) {
      return null;
    }
    try {
      final type = mermaid.detectDiagramType(code);
      if (type == mermaid.DiagramType.flowchart) {
        // The parser expands grouped endpoints before returning its edge list.
        // Conservatively cap grouping tokens even inside labels/comments.
        if ('&'.allMatches(code).length > 20) return null;
        code = mermaidLinksSpaced(code);
        final graph = mermaid.parseFlowchart(code);
        if (graph.nodes.length > 100 || graph.edges.length > 200) return null;
        // ELK takes a few milliseconds up to here, far more past it.
        if (graph.nodes.length <= 30 && graph.edges.length <= 60) {
          code = mermaidSquare(code);
        }
      } else if (type == mermaid.DiagramType.packet) {
        final packet = mermaid.parsePacket(code);
        final config = mermaid.PacketConfig.fromSource(code);
        if (config.bitsPerRow < 1 || packet.fields.last.end > 2047) {
          return null;
        }
      }
      final scene = mermaid.Mermaid(
        measurer: const FlutterTextMeasurer(),
        theme: theme,
      ).render(code);
      if (scene.size.width.isFinite &&
          scene.size.height.isFinite &&
          scene.size.width > 0 &&
          scene.size.height > 0) {
        // Drawn straight on the conversation: its fills already match it.
        return mermaid.RenderScene(
          size: scene.size,
          nodes: [for (final node in scene.nodes) mermaidUnescaped(node)],
        );
      }
    } catch (_) {
      // Incomplete streamed fences and unsupported syntax stay readable.
    }
    return null;
  }

  /// [scene], or [_across] where, [width] wide, that shows far less tall
  /// and its text not much smaller: the conversation's height is dear.
  mermaid.RenderScene _shown(mermaid.RenderScene scene, double width) {
    final across = _across;
    if (across == null || !width.isFinite) return scene;
    double scale(mermaid.RenderScene of) => math.min(1, width / of.size.width);
    double height(mermaid.RenderScene of) => of.size.height * scale(of);
    return scale(across) >= 0.8 && height(across) < height(scene) * 0.8
        ? across
        : scene;
  }

  void _copy() => copyText(widget.code);

  /// [scene] as a picture, made once for it (see [mermaidPicture]).
  Future<ImageAttachment> _picture(mermaid.RenderScene scene) {
    if (_pictured case (final made, final picture) when made == scene) {
      return picture;
    }
    final picture = mermaidPicture(
      scene,
      background: Theme.of(context).colorScheme.surface,
    );
    _pictured = (scene, picture);
    return picture;
  }

  /// [scene] shown whole, as a picture is.
  Future<void> _preview(mermaid.RenderScene scene) async {
    final picture = await _picture(scene);
    if (!mounted) return;
    // Else closing hands focus back to the composer and the keyboard rises.
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Mermaid'),
            leading: IconButton(
              tooltip: _label(context, '关闭', 'Close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 8,
              constrained: false,
              child: Image.memory(picture.bytes),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    mermaid.Color color(Color value) => mermaid.Color(value.toARGB32());
    // The conversation's, which shapes filled "with the background" match.
    final background = colors.surface;
    final foreground = colors.onSurface;
    final fill = Color.alphaBlend(colors.surfaceContainerHighest, background);
    final theme =
        (Theme.of(context).brightness == Brightness.dark
                ? mermaid.MermaidTheme.darkTheme
                : mermaid.MermaidTheme.defaultTheme)
            .copyWith(
              background: color(background),
              primaryColor: color(fill),
              mainBkg: color(fill),
              primaryTextColor: color(foreground),
              textColor: color(foreground),
              titleColor: color(foreground),
              primaryBorderColor: color(colors.primary),
              nodeBorder: color(colors.primary),
              lineColor: color(foreground),
              arrowheadColor: color(foreground),
              clusterBkg: color(background),
              clusterBorder: color(colors.outlineVariant),
              edgeLabelBackground: color(background),
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              fontSize: MobileTheme.codeFontSizeOf(context),
            )
            // A sequence's actors, boxes and notes as a flowchart's nodes.
            .withSequenceColors(
              actorBkg: color(fill),
              actorBorder: color(colors.primary),
              actorTextColor: color(foreground),
              actorLineColor: color(colors.onSurfaceVariant),
              signalColor: color(foreground),
              signalTextColor: color(foreground),
              labelBoxBkgColor: color(fill),
              labelBoxBorderColor: color(colors.primary),
              labelTextColor: color(foreground),
              loopTextColor: color(foreground),
              noteBkgColor: color(colors.surfaceContainerLow),
              noteBorderColor: color(colors.outlineVariant),
              noteTextColor: color(foreground),
              activationBkgColor: color(fill),
              activationBorderColor: color(colors.primary),
            );
    if (_writing) {
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: Semantics(
          liveRegion: true,
          label: _label(context, '图表生成中', 'Diagram in progress'),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: MobileTheme.codeSurfaceOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(_label(context, '图表生成中…', 'Diagram in progress…')),
              ),
            ),
          ),
        ),
      );
    }
    if (_theme != theme) _render(theme);
    final scene = _scene;
    if (scene == null || _showSource) {
      return MarkdownCodeBlock(
        code: widget.code,
        language: 'mermaid',
        onPreview: scene == null
            ? null
            : () => setState(() => _showSource = false),
      );
    }
    return SelectionContainer.disabled(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: [
            // Its own size, or narrowed to the column's; never scrolled.
            LayoutBuilder(
              builder: (context, constraints) {
                final shown = _shown(scene, constraints.maxWidth);
                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.zoomIn,
                    child: GestureDetector(
                      onTap: () => unawaited(_preview(shown)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _Scene(scene: shown, source: widget.code),
                      ),
                    ),
                  ),
                );
              },
            ),
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Visibility.maintain(
                visible:
                    _hovered ||
                    copied ||
                    Theme.of(context).platform == TargetPlatform.android ||
                    Theme.of(context).platform == TargetPlatform.iOS,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: MobileTheme.codeSurfaceOf(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CodeBlockIconButton(
                        icon: Icons.code,
                        tooltip: _label(context, '源代码', 'Source'),
                        onTap: () => setState(() => _showSource = true),
                      ),
                      CodeBlockIconButton(
                        icon: Icons.fullscreen,
                        tooltip: _label(context, '放大', 'Expand'),
                        onTap: () => unawaited(
                          _preview(
                            _shown(
                              scene,
                              context.size?.width ?? double.infinity,
                            ),
                          ),
                        ),
                      ),
                      CodeBlockIconButton(
                        icon: copied ? Icons.check : Icons.content_copy,
                        tooltip: _label(context, '复制', 'Copy'),
                        onTap: _copy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _quiet?.cancel();
    _pending?.cancel();
    super.dispose();
  }
}

class _Scene extends StatelessWidget {
  const _Scene({required this.scene, required this.source});

  final mermaid.RenderScene scene;
  final String source;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Mermaid\n$source',
    child: CustomPaint(
      painter: ScenePainter(scene),
      size: Size(scene.size.width, scene.size.height),
    ),
  );
}

String _label(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// [scene] as a PNG, on [background] (a picture see-through would be lost
/// on a dark viewer, or a light one), with a margin round it; at three
/// times its size, for its text to stay sharp enlarged, or as large as a
/// picture sensibly is.
Future<ImageAttachment> mermaidPicture(
  mermaid.RenderScene scene, {
  required Color background,
}) async {
  const margin = 24.0;
  final size = Size(
    scene.size.width + 2 * margin,
    scene.size.height + 2 * margin,
  );
  final ratio = math.min(3.0, 8192 / math.max(size.width, size.height));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(ratio)
    ..drawRect(Offset.zero & size, Paint()..color = background)
    ..translate(margin, margin);
  ScenePainter(scene).paint(canvas, Size(scene.size.width, scene.size.height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width * ratio).ceil(),
    (size.height * ratio).ceil(),
  );
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImageAttachment(
      bytes: data!.buffer.asUint8List(),
      mediaType: 'image/png',
      name: 'mermaid.png',
    );
  } finally {
    image.dispose();
  }
}

/// [code], a flowchart drawn top down (`flowchart TD`, `graph TB`, or no
/// direction), drawn across instead: left to right, or right to left for
/// bottom up; null for any other.
String? mermaidAcross(String code) {
  final header = _topDown.firstMatch(code);
  if (header == null) return null;
  final across = header[2] == 'BT' ? 'RL' : 'LR';
  return code.replaceRange(
    header.start,
    header.end,
    '${header[1]} $across${header[3]}',
  );
}

final _topDown = RegExp(
  r'^([ \t]*(?:flowchart|graph))(?:[ \t]+(TD|TB|BT))?([ \t]*;?[ \t]*)$',
  multiLine: true,
);

/// [code] laid out by ELK, whose lines go square, where it says no layout
/// of its own: its directive first (after any front matter), so that one
/// of the code's, coming later, wins.
String mermaidSquare(String code) {
  const directive = '%%{init: {"layout": "elk"}}%%\n';
  final front = _frontMatter.firstMatch(code);
  if (front == null) return '$directive$code';
  return code.replaceRange(front.end, front.end, directive);
}

final _frontMatter = RegExp(r'^\s*---[ \t]*\n[\s\S]*?\n[ \t]*---[ \t]*\n');

/// [code], a flowchart, its links' labels spaced from the links round them
/// (`A-.label.->B` as `A-. label .->B`, `--label-->` and `==label==>`
/// too), as mermaid.js reads them and mermaid_core only spaced; node text,
/// edge `|labels|` and comments as they are.
String mermaidLinksSpaced(String code) {
  final out = StringBuffer();
  // The ends of the brackets, quotes or bars a label is in, innermost last.
  final closes = <String>[];
  var comment = false;
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    if (c == '\n') comment = false;
    if (comment || closes.isNotEmpty) {
      out.write(c);
      if (closes.isEmpty) continue;
      if (c == closes.last) {
        closes.removeLast();
      } else if (c == '"') {
        closes.add('"');
      }
      continue;
    }
    if (_labelCloses[c] case final close?) closes.add(close);
    if (code.startsWith('%%', i)) comment = true;
    if (_linkText(code, i) case (final label, final end)) {
      final opening = code.substring(i, i + 2);
      out.write('$opening ${label.trim()} ');
      i = end - 1;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

const _labelCloses = {'"': '"', '[': ']', '(': ')', '{': '}', '|': '|'};

/// The label of a link whose label runs from [at], and where the link's
/// end begins; null for none there.
(String, int)? _linkText(String code, int at) {
  if (at + 2 >= code.length) return null;
  final end = _linkEnds[code.substring(at, at + 2)];
  if (end == null) return null;
  // The middle of a link, or one with no label (`--->`, `-.->`, `--x`).
  if (at > 0 && (code[at - 1] == '-' || code[at - 1] == '=')) return null;
  final next = code[at + 2];
  if ('-=.>|'.contains(next)) return null;
  // A dotted link's head comes after its dots.
  if (code[at + 1] != '.' && (next == 'x' || next == 'o')) return null;
  var quoted = false;
  for (var k = at + 2; k < code.length && code[k] != '\n'; k++) {
    if (code[k] == '"') quoted = !quoted;
    if (quoted || end.matchAsPrefix(code, k) == null) continue;
    final label = code.substring(at + 2, k);
    return label.trim().isEmpty ? null : (label, k);
  }
  return null;
}

/// A link's end, by its opening, as mermaid_core reads it.
final _linkEnds = {
  '-.': RegExp(r'\.+-[xo>]?'),
  '--': RegExp(r'-{2,}[-xo>]'),
  '==': RegExp(r'={2,}[=xo>]?'),
};

/// [node] with its text's entities read (`&lt;` as `<`, Mermaid's `#lt;`
/// too), as Mermaid's HTML labels show them; laid out as written, it only
/// comes out a little narrower than measured.
mermaid.SceneNode mermaidUnescaped(mermaid.SceneNode node) => switch (node) {
  mermaid.SceneText(:final text) when text.contains(_entity) => node.copyWith(
    text: text.replaceAllMapped(_entity, _character),
  ),
  mermaid.SceneGroup() => mermaid.SceneGroup(
    children: [for (final child in node.children) mermaidUnescaped(child)],
    id: node.id,
    role: node.role,
    semanticLabel: node.semanticLabel,
    link: node.link,
    tooltip: node.tooltip,
    edge: node.edge,
  ),
  _ => node,
};

final _entity = RegExp(r'[&#](#?)(x[0-9a-fA-F]+|\d+|[a-zA-Z]+);');

String _character(Match match) {
  final whole = match[0]!;
  final name = match[2]!;
  if (!_number.hasMatch(name)) return _named[name] ?? whole;
  // `&#60;`, and Mermaid's `#60;`; a bare `&60;` is none.
  if (whole.startsWith('&') && match[1]!.isEmpty) return whole;
  final code = name.startsWith('x')
      ? int.tryParse(name.substring(1), radix: 16)
      : int.tryParse(name);
  if (code == null || code < 0x20 || code > 0x10FFFF) return whole;
  return String.fromCharCode(code);
}

final _number = RegExp(r'^(x[0-9a-fA-F]+|\d+)$');

const _named = {
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

/// What [mermaid.MermaidTheme.copyWith] leaves as it was: a sequence
/// diagram's colors. Every other field is the theme's own; written out from
/// mermaid_core 0.3.0's constructor, all 169 of its fields.
extension MermaidSequenceColors on mermaid.MermaidTheme {
  /// It, its sequence diagrams' colors those given (the rest kept).
  mermaid.MermaidTheme withSequenceColors({
    mermaid.Color? actorBkg,
    mermaid.Color? actorBorder,
    mermaid.Color? actorTextColor,
    mermaid.Color? actorLineColor,
    mermaid.Color? signalColor,
    mermaid.Color? signalTextColor,
    mermaid.Color? labelBoxBkgColor,
    mermaid.Color? labelBoxBorderColor,
    mermaid.Color? labelTextColor,
    mermaid.Color? loopTextColor,
    mermaid.Color? noteBkgColor,
    mermaid.Color? noteBorderColor,
    mermaid.Color? noteTextColor,
    mermaid.Color? activationBkgColor,
    mermaid.Color? activationBorderColor,
  }) => mermaid.MermaidTheme(
    background: background,
    primaryColor: primaryColor,
    primaryTextColor: primaryTextColor,
    primaryBorderColor: primaryBorderColor,
    secondaryColor: secondaryColor,
    lineColor: lineColor,
    arrowheadColor: arrowheadColor,
    textColor: textColor,
    nodeBorder: nodeBorder,
    mainBkg: mainBkg,
    clusterBkg: clusterBkg,
    clusterBorder: clusterBorder,
    titleColor: titleColor,
    edgeLabelBackground: edgeLabelBackground,
    fontFamily: fontFamily,
    fontSize: fontSize,
    cScale0: cScale0,
    cScale1: cScale1,
    cScale2: cScale2,
    cScale3: cScale3,
    cScale4: cScale4,
    cScale5: cScale5,
    cScale6: cScale6,
    cScale7: cScale7,
    cScale8: cScale8,
    cScale9: cScale9,
    cScale10: cScale10,
    cScale11: cScale11,
    cScaleInv0: cScaleInv0,
    cScaleInv1: cScaleInv1,
    cScaleInv2: cScaleInv2,
    cScaleInv3: cScaleInv3,
    cScaleInv4: cScaleInv4,
    cScaleInv5: cScaleInv5,
    cScaleInv6: cScaleInv6,
    cScaleInv7: cScaleInv7,
    cScaleInv8: cScaleInv8,
    cScaleInv9: cScaleInv9,
    cScaleInv10: cScaleInv10,
    cScaleInv11: cScaleInv11,
    cScaleLabel0: cScaleLabel0,
    cScaleLabel1: cScaleLabel1,
    cScaleLabel2: cScaleLabel2,
    cScaleLabel3: cScaleLabel3,
    cScaleLabel4: cScaleLabel4,
    cScaleLabel5: cScaleLabel5,
    cScaleLabel6: cScaleLabel6,
    cScaleLabel7: cScaleLabel7,
    cScaleLabel8: cScaleLabel8,
    cScaleLabel9: cScaleLabel9,
    cScaleLabel10: cScaleLabel10,
    cScaleLabel11: cScaleLabel11,
    cScalePeer0: cScalePeer0,
    cScalePeer1: cScalePeer1,
    cScalePeer2: cScalePeer2,
    cScalePeer3: cScalePeer3,
    cScalePeer4: cScalePeer4,
    cScalePeer5: cScalePeer5,
    cScalePeer6: cScalePeer6,
    cScalePeer7: cScalePeer7,
    cScalePeer8: cScalePeer8,
    cScalePeer9: cScalePeer9,
    cScalePeer10: cScalePeer10,
    cScalePeer11: cScalePeer11,
    pie1: pie1,
    pie2: pie2,
    pie3: pie3,
    pie4: pie4,
    pie5: pie5,
    pie6: pie6,
    pie7: pie7,
    pie8: pie8,
    pie9: pie9,
    pie10: pie10,
    pie11: pie11,
    pie12: pie12,
    pieStrokeColor: pieStrokeColor,
    pieOuterStrokeColor: pieOuterStrokeColor,
    pieSectionTextColor: pieSectionTextColor,
    pieLegendTextColor: pieLegendTextColor,
    pieTitleTextColor: pieTitleTextColor,
    git0: git0,
    git1: git1,
    git2: git2,
    git3: git3,
    git4: git4,
    git5: git5,
    git6: git6,
    git7: git7,
    gitInv0: gitInv0,
    gitInv1: gitInv1,
    gitInv2: gitInv2,
    gitInv3: gitInv3,
    gitInv4: gitInv4,
    gitInv5: gitInv5,
    gitInv6: gitInv6,
    gitInv7: gitInv7,
    gitBranchLabel0: gitBranchLabel0,
    gitBranchLabel1: gitBranchLabel1,
    gitBranchLabel2: gitBranchLabel2,
    gitBranchLabel3: gitBranchLabel3,
    gitBranchLabel4: gitBranchLabel4,
    gitBranchLabel5: gitBranchLabel5,
    gitBranchLabel6: gitBranchLabel6,
    gitBranchLabel7: gitBranchLabel7,
    commitLabelColor: commitLabelColor,
    commitLabelBackground: commitLabelBackground,
    tagLabelColor: tagLabelColor,
    tagLabelBackground: tagLabelBackground,
    tagLabelBorder: tagLabelBorder,
    actorBkg: actorBkg ?? this.actorBkg,
    actorBorder: actorBorder ?? this.actorBorder,
    actorTextColor: actorTextColor ?? this.actorTextColor,
    actorLineColor: actorLineColor ?? this.actorLineColor,
    signalColor: signalColor ?? this.signalColor,
    signalTextColor: signalTextColor ?? this.signalTextColor,
    labelBoxBkgColor: labelBoxBkgColor ?? this.labelBoxBkgColor,
    labelBoxBorderColor: labelBoxBorderColor ?? this.labelBoxBorderColor,
    labelTextColor: labelTextColor ?? this.labelTextColor,
    loopTextColor: loopTextColor ?? this.loopTextColor,
    noteBkgColor: noteBkgColor ?? this.noteBkgColor,
    noteBorderColor: noteBorderColor ?? this.noteBorderColor,
    noteTextColor: noteTextColor ?? this.noteTextColor,
    activationBkgColor: activationBkgColor ?? this.activationBkgColor,
    activationBorderColor: activationBorderColor ?? this.activationBorderColor,
    fillType0: fillType0,
    fillType1: fillType1,
    fillType2: fillType2,
    fillType3: fillType3,
    fillType4: fillType4,
    fillType5: fillType5,
    fillType6: fillType6,
    fillType7: fillType7,
    quadrant1Fill: quadrant1Fill,
    quadrant2Fill: quadrant2Fill,
    quadrant3Fill: quadrant3Fill,
    quadrant4Fill: quadrant4Fill,
    quadrant1TextFill: quadrant1TextFill,
    quadrant2TextFill: quadrant2TextFill,
    quadrant3TextFill: quadrant3TextFill,
    quadrant4TextFill: quadrant4TextFill,
    quadrantPointFill: quadrantPointFill,
    quadrantPointTextFill: quadrantPointTextFill,
    quadrantXAxisTextFill: quadrantXAxisTextFill,
    quadrantYAxisTextFill: quadrantYAxisTextFill,
    quadrantInternalBorderStrokeFill: quadrantInternalBorderStrokeFill,
    quadrantExternalBorderStrokeFill: quadrantExternalBorderStrokeFill,
    quadrantTitleFill: quadrantTitleFill,
    attributeBackgroundColorOdd: attributeBackgroundColorOdd,
    attributeBackgroundColorEven: attributeBackgroundColorEven,
    rowOdd: rowOdd,
    rowEven: rowEven,
    venn1: venn1,
    venn2: venn2,
    venn3: venn3,
    venn4: venn4,
    venn5: venn5,
    venn6: venn6,
    venn7: venn7,
    venn8: venn8,
    vennTitleTextColor: vennTitleTextColor,
    vennSetTextColor: vennSetTextColor,
    requirementBackground: requirementBackground,
    requirementBorderColor: requirementBorderColor,
    requirementTextColor: requirementTextColor,
    relationColor: relationColor,
    relationLabelBackground: relationLabelBackground,
    relationLabelColor: relationLabelColor,
    xyChartPlotColorPalette: xyChartPlotColorPalette,
  );
}
