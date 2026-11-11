import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_citation.dart';
import 'finite_selection_edges.dart';
import 'hover_scrollbar.dart';
import 'inline_code.dart';
import 'lazy_segment.dart';
import 'markdown_cjk.dart';
import 'markdown_math.dart';
import 'markdown_tags.dart';
import 'mermaid_code_block.dart';
import 'will_change_paint.dart';
import '../../theme/app_theme.dart';

/// GitHub-flavored markdown as plain widgets (so a surrounding
/// `SelectionArea` selects and copies it): headings, paragraphs, lists
/// (and task lists), code blocks, quotes, tables, rules, and inline
/// strong, emphasis, strikethrough, code, links and TeX math.
class MarkdownView extends StatefulWidget {
  const MarkdownView(
    this.data, {
    super.key,
    this.style,
    this.options = const MarkdownOptions(),
  });

  final String data;
  final MarkdownOptions options;

  /// [baseStyle] when null.
  final TextStyle? style;

  static TextStyle get baseStyle =>
      const TextStyle(fontSize: MobileType.body, height: 1.6);

  /// Inline code's, its background painted by [InlineCodeText].
  static TextStyle get codeStyle =>
      const TextStyle(fontFamily: 'monospace', fontSize: MobileType.mono);

  /// The block syntaxes of its own, before GFM's: code citations and TeX.
  static const blockSyntaxes = <md.BlockSyntax>[
    CodeCitationFenceSyntax(),
    MathBlockSyntax(),
  ];
  static List<md.InlineSyntax> get inlineSyntaxes => [
    InlineMathSyntax(),
    CjkEmphasisSyntax(),
  ];

  /// A document parsing as it does; one keeps the link definitions it
  /// read (see the IDE's markdown preview). The chat's has [tags] too: a
  /// block between tags as a section that folds ([TagBlockSyntax]).
  static md.Document document({bool tags = false}) => md.Document(
    extensionSet: _extensions,
    blockSyntaxes: [...blockSyntaxes, if (tags) const TagBlockSyntax()],
    inlineSyntaxes: inlineSyntaxes,
    encodeHtml: false,
  );

  static final _document = document(tags: true);

  /// GitHub's, but struck through only between `~~`: a single `~` is how
  /// a range is written (`10-12~10-16`), and two of them on a line would
  /// strike out what is between.
  static final _extensions = md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    [
      for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
        if (syntax is! md.StrikethroughSyntax) syntax,
      md.DelimiterSyntax(
        '~+',
        requiresDelimiterRun: true,
        allowIntraWord: true,
        startCharacter: 0x7E, // ~
        tags: [md.DelimiterTag('del', 2)],
      ),
    ],
  );

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  /// What it built last, and from what. The history rebuilds the messages
  /// it shows as a reply streams in, the pointer moves in…: parsed again,
  /// its file icons new widgets, each paragraph would be laid out anew.
  Widget? _built;
  Object? _builtFrom;

  /// A long text's segments ([markdownSegments]) as last built: as a reply
  /// streams in, only its last is parsed and built again, not the hundreds
  /// of blocks before it with every few words.
  List<_Segment> _segments = const [];
  Object? _segmentsFrom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
    _segments = const [];
  }

  @override
  Widget build(BuildContext context) {
    final from = (widget.data, widget.style, Theme.of(context), widget.options);
    if (_built case final built? when from == _builtFrom) return built;
    _builtFrom = from;
    return _built = _build(context);
  }

  Widget _build(BuildContext context) {
    final from = (widget.style, Theme.of(context), widget.options);
    if (from != _segmentsFrom) _segments = const [];
    _segmentsFrom = from;
    final old = _segments;
    final texts = markdownSegmentsGrown(widget.data, [
      for (final segment in old) segment.text,
    ]);
    _segments = [
      for (final (i, text) in texts.indexed)
        i < old.length && old[i].text == text
            ? old[i]
            : _Segment(text, _parseDocument(text, keep: old.isEmpty)),
    ];
    final options = widget.options;
    final children = <Widget>[];
    for (final (i, segment) in _segments.indexed) {
      final first = segment.nodes.where(_shows).firstOrNull;
      if (first == null) continue;
      if (children.isNotEmpty) {
        children.add(SizedBox(height: _gapBefore(first, options)));
      }
      final blocks = segment.widget ??= _buildBlocks(context, segment);
      children.add(
        _segments.length == 1
            ? blocks
            : LazySegment(
                key: ValueKey(i),
                text: segment.text,
                keep: i == _segments.length - 1,
                child: blocks,
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlocks(BuildContext context, _Segment segment) {
    return MarkdownBlocks(
      nodes: segment.nodes,
      style: widget.style ?? MarkdownView.baseStyle,
      options: widget.options,
    );
  }
}

/// Segments parsed lately, by their text, the latest last: a message
/// scrolled out of the history and back (the minimap scrubbed through
/// it, back and forth) is not parsed again. Its nodes are only read.
final Map<String, List<md.Node>> _parsed = {};
const _parsedKept = 160;

/// [text] parsed, as lately if it was; kept for later if [keep] (not as a
/// reply streams in: each would be kept a moment, the others pushed out).
List<md.Node> _parseDocument(String text, {bool keep = true}) {
  if (_parsed.remove(text) case final nodes?) return _parsed[text] = nodes;
  final nodes = MarkdownView._document.parse(text);
  if (endsInOpenFence(text)) _markWriting(nodes);
  if (keep) {
    _parsed[text] = nodes;
    if (_parsed.length > _parsedKept) _parsed.remove(_parsed.keys.first);
  }
  return nodes;
}

/// [data]'s blocks cut into segments, parsed, for a lazy list to build only
/// what shows: a long file read in a list, not one Column of it all.
List<List<md.Node>> markdownSegmentNodes(String data) => [
  for (final text in markdownSegments(data)) _parseDocument(text),
];

/// [data] cut into segments to parse each on its own, the same blocks as
/// all of it parsed at once: at a blank line, before a line at its start
/// that begins a block of its own (not a list's item, which may belong to
/// the list before), outside code, math, tag sections and HTML comments,
/// once a segment has [_segmentLength] characters. A line still being
/// written (the last) is never cut before. Footnotes and link definitions,
/// which reach across the whole, leave it whole.
@visibleForTesting
List<String> markdownSegments(String data) =>
    _whole(data) ? [data] : _cut(data, 0);

/// [data]'s segments, as [markdownSegments] cuts it, [before] its segments
/// as last cut: those but the last kept, not cut again, when [data] begins
/// with them (a reply streaming on); only what follows is cut.
@visibleForTesting
List<String> markdownSegmentsGrown(String data, List<String> before) {
  if (before.length > 1 && !_whole(data)) {
    var at = 0;
    var same = true;
    for (var i = 0; same && i < before.length - 1; i++) {
      same = data.startsWith(before[i], at);
      at += before[i].length;
    }
    if (same) {
      return [...before.take(before.length - 1), ..._cut(data, at)];
    }
  }
  return markdownSegments(data);
}

/// Whether [data] is parsed whole: short, or with what reaches across it.
bool _whole(String data) =>
    data.length < 2 * _segmentLength ||
    data.contains('[^') ||
    _linkDefinition.hasMatch(data);

/// The segments of [data] from [from], where one begins (or 0).
List<String> _cut(String data, int from) {
  final segments = <String>[];
  var start = from;
  var at = from;
  var blankBefore = false;
  String? fence;
  String? mathClose;
  var comment = false;
  // The tag sections and HTML blocks open, innermost last: by their tag,
  // and whether it is a section's (closed on a line of its own).
  final tags = <(String, bool)>[];
  while (true) {
    final end = data.indexOf('\n', at);
    if (end == -1) break;
    final line = data.substring(at, end);
    final open = fence == null && mathClose == null && !comment && tags.isEmpty;
    if (open &&
        blankBefore &&
        at - start >= _segmentLength &&
        _startsOwnBlock(line)) {
      segments.add(data.substring(start, at));
      start = at;
    }
    if (fence != null) {
      final closing = _fenceLine.firstMatch(line);
      if (closing != null &&
          closing[2] == null &&
          closing[1]![0] == fence[0] &&
          closing[1]!.length >= fence.length) {
        fence = null;
      }
    } else if (mathClose != null) {
      if (line.trimRight().endsWith(mathClose)) mathClose = null;
    } else if (comment) {
      if (line.contains('-->')) comment = false;
    } else if (_fenceLine.firstMatch(line) case final opening?
        // A backtick fence's info has no backtick: else inline code.
        when opening[1]![0] == '~' || !(opening[2] ?? '').contains('`')) {
      fence = opening[1];
    } else if (_mathOpening.firstMatch(line) case final opening?) {
      final close = opening[1] == r'$$' ? r'$$' : r'\]';
      if (!opening[2]!.trimRight().endsWith(close)) mathClose = close;
    } else if (_tagOpening.firstMatch(line) case final opening?) {
      final name = opening[1]!.toLowerCase();
      if (!_voidTags.contains(name)) tags.add((name, true));
    } else if (_rawHtmlOpening.firstMatch(line) case final opening?) {
      // HTML's blocks that blank lines do not end, unless closed on it.
      final name = opening[1]!.toLowerCase();
      if (!line.toLowerCase().contains('</$name')) tags.add((name, false));
    } else if (tags.isNotEmpty && _closes(line, tags.last)) {
      tags.removeLast();
    } else if (line.lastIndexOf('<!--') > line.lastIndexOf('-->')) {
      comment = true;
    }
    blankBefore = line.trim().isEmpty;
    at = end + 1;
  }
  segments.add(data.substring(start));
  return segments;
}

const _segmentLength = 2000;

/// Whether [text] ends in a fence not closed: a code block still being
/// written, as a reply streams in.
@visibleForTesting
bool endsInOpenFence(String text) {
  String? fence;
  for (final line in text.split('\n')) {
    final match = _fenceLine.firstMatch(line);
    if (match == null) continue;
    if (fence == null) {
      // A backtick fence's info has no backtick: else inline code.
      if (match[1]![0] == '~' || !(match[2] ?? '').contains('`')) {
        fence = match[1];
      }
    } else if (match[2] == null &&
        match[1]![0] == fence[0] &&
        match[1]!.length >= fence.length) {
      fence = null;
    }
  }
  return fence != null;
}

/// Marks the last code block of [nodes], the fence [endsInOpenFence] found
/// open, as still being written.
void _markWriting(List<md.Node> nodes) {
  md.Element? last;
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'pre') last = node;
    node.children?.forEach(visit);
  }

  nodes.forEach(visit);
  last?.attributes[_writingAttribute] = '';
}

const _writingAttribute = 'data-writing';

final _linkDefinition = RegExp(r'^ {0,3}\[[^\]]+\]:', multiLine: true);

/// A fence: its run, and anything after it (none on a closing one).
final _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*(\S.*)?$');
final _mathOpening = RegExp(r'^ {0,3}(\$\$|\\\[)(.*)$');
final _tagOpening = RegExp(r'^ {0,3}<([A-Za-z][\w-]*)(\s[^<>]*)?>\s*$');
final _tagClosing = RegExp(r'^ {0,3}</([A-Za-z][\w-]*)\s*>\s*$');
final _rawHtmlOpening = RegExp(
  r'^ {0,3}<(script|pre|style|textarea)(\s|>|$)',
  caseSensitive: false,
);
const _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', //
  'meta', 'source', 'track', 'wbr',
};

/// Whether [line] closes [open]: a tag section on a line of its own
/// ([TagBlockSyntax]), an HTML block anywhere in it.
bool _closes(String line, (String, bool) open) => switch (open) {
  (final name, true) => _tagClosing.firstMatch(line)?[1]?.toLowerCase() == name,
  (final name, false) => line.toLowerCase().contains('</$name'),
};
final _listItem = RegExp(r'^([-*+]|\d{1,9}[.)])(\s|$)');

bool _startsOwnBlock(String line) =>
    line.isNotEmpty &&
    line[0] != ' ' &&
    line[0] != '\t' &&
    line[0] != '<' &&
    !_listItem.hasMatch(line);

class _Segment {
  _Segment(this.text, this.nodes);

  final String text;
  final List<md.Node> nodes;
  Widget? widget;
}

/// Whether [MarkdownBlocks] shows [node] as a block.
bool _shows(md.Node node) => switch (node) {
  md.Text(:final text) => text.trim().isNotEmpty && !isHtmlComment(text),
  md.Element() => true,
  _ => false,
};

/// The space before [node] after another block.
double _gapBefore(md.Node node, MarkdownOptions options) => switch (node) {
  md.Element(tag: 'h1' || 'h2' || 'h3') => 12,
  _ => options.gap,
};

/// How [MarkdownBlocks] draws and what its links and images do: as the
/// chat's by default.
@immutable
class MarkdownOptions {
  const MarkdownOptions({
    this.headingSizes = const [19, 17, 15, 13.5, 13.5, 13.5],
    this.gap = 8,
    this.colors = const ColorScheme.light(),
    this.inlineCodeStyle,
    this.link,
    this.code,
    this.image,
  });

  /// `h1` to `h6`'s font sizes.
  final List<double> headingSizes;

  /// The space between blocks.
  final double gap;
  final ColorScheme colors;
  final TextStyle? inlineCodeStyle;

  /// What a tap on a link to `href` does; web and mail links open in the
  /// browser when null, others nothing.
  final GestureRecognizer? Function(String? href)? link;

  /// What a tap on inline code does (it names a file, say); nothing when
  /// null, or it gives none.
  final GestureRecognizer? Function(String code)? code;

  /// An image (`![alt](src "title")`, or HTML's with its [width] and
  /// [height] in pixels); its alt text in brackets when null.
  final Widget Function(
    String src,
    String alt,
    String? title, {
    double? width,
    double? height,
  })?
  image;
}

/// Parsed markdown ([MarkdownView.document]) as widgets.
class MarkdownBlocks extends StatelessWidget {
  const MarkdownBlocks({
    super.key,
    required this.nodes,
    required this.style,
    this.options = const MarkdownOptions(),
  });

  final List<md.Node> nodes;
  final TextStyle style;
  final MarkdownOptions options;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final node in nodes) {
      final block = _block(node, style, options);
      if (block == null) continue;
      if (children.isNotEmpty) children.add(SizedBox(height: _gap(node)));
      children.add(block);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  double _gap(md.Node node) => _gapBefore(node, options);
}

Widget? _block(md.Node node, TextStyle style, MarkdownOptions options) {
  if (node is md.Text) {
    if (node.text.trim().isEmpty || isHtmlComment(node.text)) return null;
    return Text.rich(TextSpan(style: style, text: node.text));
  }
  if (node is! md.Element) return null;
  switch (node.tag) {
    case 'math':
      return MathView(node.textContent, display: true);
    case 'p':
      return InlineCodeText(
        _inlines(node.children ?? const [], style, options),
      );
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      final level = int.parse(node.tag.substring(1));
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: InlineCodeText(
          _inlines(
            node.children ?? const [],
            style.copyWith(
              color: options.colors.onSurface,
              fontSize: options.headingSizes[level - 1],
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            options,
          ),
        ),
      );
    case 'ul' || 'ol':
      return _List(node: node, style: style, options: options);
    case 'pre':
      final code = node.children?.firstOrNull;
      final text = code is md.Element ? code.textContent : node.textContent;
      final language = code is md.Element
          ? code.attributes['class']?.replaceFirst('language-', '')
          : null;
      final body = text.endsWith('\n')
          ? text.substring(0, text.length - 1)
          : text;
      if (CodeCitation.parse(language) case final citation?) {
        return CodeCitationCard(citation: citation, code: body);
      }
      // `python title="a.py"`: the language is the first word.
      final name = language?.trim().split(RegExp(r'\s')).first;
      if (name?.toLowerCase() == 'mermaid') {
        return MermaidCodeBlock(
          code: body,
          writing: node.attributes.containsKey(_writingAttribute),
        );
      }
      return MarkdownCodeBlock(
        code: body,
        language: name == null || name.isEmpty ? null : name,
      );
    case 'blockquote':
      final children = node.children ?? const <md.Node>[];
      return MarkdownQuoteBlock(
        // Its paragraphs' text, as they read.
        text: children.map((child) => child.textContent).join('\n\n'),
        child: MarkdownBlocks(
          nodes: children,
          style: style.copyWith(color: options.colors.onSurfaceVariant),
          options: options,
        ),
      );
    case 'hr':
      // As upstream's chat: the separator's color, faint.
      final separator = options.colors.outlineVariant;
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(
          height: 1,
          color: separator.withValues(alpha: separator.a * 0.33),
        ),
      );
    case 'table':
      return _Table(node: node, style: style, options: options);
    case TagBlockSyntax.tag:
      return TagSection(node: node, style: style, options: options);
    default:
      return InlineCodeText(_inlines([node], style, options));
  }
}

/// A list, numbered or not, whose items may hold blocks and nested lists.
class _List extends StatelessWidget {
  const _List({required this.node, required this.style, required this.options});

  final md.Element node;
  final TextStyle style;
  final MarkdownOptions options;

  @override
  Widget build(BuildContext context) {
    final ordered = node.tag == 'ol';
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final child in node.children ?? const <md.Node>[])
        if (child is md.Element && child.tag == 'li') child,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _isTask(item) ? 22 : (ordered ? 24 : 18),
                  child: _marker(item, ordered ? '${start + i}.' : '•'),
                ),
                Expanded(child: _itemBody(item)),
              ],
            ),
          ),
      ],
    );
  }

  static bool _isTask(md.Element item) => switch (item.children?.firstOrNull) {
    md.Element(tag: 'input') => true,
    _ => false,
  };

  Widget _marker(md.Element item, String text) {
    final checkbox = item.children?.firstOrNull;
    if (checkbox is md.Element && checkbox.tag == 'input') {
      final checked = checkbox.attributes['checked'] != null;
      // In the links' color, as tall as a capital and centred on the line.
      final accent = options.colors.primary;
      // Its own size, at the start of the marker's column (which is wider).
      final square = Container(
        width: 15,
        height: 15,
        margin: const EdgeInsets.only(top: 3.5),
        decoration: BoxDecoration(
          color: checked ? accent : null,
          border: Border.all(
            color: checked ? accent : accent.withValues(alpha: 0.7),
            width: 1.3,
          ),
          borderRadius: BorderRadius.circular(3.5),
        ),
        child: checked
            ? Icon(Icons.check, size: 13, color: options.colors.onPrimary)
            : null,
      );
      return Align(
        alignment: AlignmentDirectional.topStart,
        widthFactor: 1,
        heightFactor: 1,
        child: square,
      );
    }
    return Text(
      text,
      style: style.copyWith(color: options.colors.onSurfaceVariant),
    );
  }

  /// An item's text and blocks: a tight item's text is inline children, a
  /// loose one's is paragraphs.
  Widget _itemBody(md.Element item) {
    final children = [
      for (final child in item.children ?? const <md.Node>[])
        if (!(child is md.Element && child.tag == 'input')) child,
    ];
    final inline = <md.Node>[];
    final blocks = <Widget>[];
    void flush() {
      if (inline.isEmpty) return;
      blocks.add(InlineCodeText(_inlines([...inline], style, options)));
      inline.clear();
    }

    for (final child in children) {
      final isBlock =
          child is md.Element &&
          const {
            'p',
            'ul',
            'ol',
            'pre',
            'blockquote',
            'table',
            'h1',
            'h2',
            'h3',
            'h4',
            'hr',
          }.contains(child.tag);
      if (!isBlock) {
        inline.add(child);
        continue;
      }
      flush();
      final block = _block(child, style, options);
      if (block != null) blocks.add(block);
    }
    flush();
    if (blocks.length == 1) return blocks.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: 4),
          block,
        ],
      ],
    );
  }
}

/// A table in a card as the steps' are, as wide as its columns up to the
/// width there is; wider, it scrolls sideways, with a bar to show it while
/// the pointer is over it or it scrolls.
class _Table extends StatefulWidget {
  const _Table({
    required this.node,
    required this.style,
    required this.options,
  });

  final md.Element node;
  final TextStyle style;
  final MarkdownOptions options;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final options = widget.options;
    final rows = <(bool, List<md.Element>)>[];
    for (final section in widget.node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        rows.add((
          section.tag == 'thead',
          [
            for (final cell in row.children ?? const <md.Node>[])
              if (cell is md.Element) cell,
          ],
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((row) => row.$2.length)
        .reduce((a, b) => a > b ? a : b);
    final line = BorderSide(color: options.colors.outlineVariant);
    final table = Table(
      // 一列最多占大半屏，长文字折行，后面的列露出来才看得出能横滑。
      defaultColumnWidth: MinColumnWidth(
        const IntrinsicColumnWidth(),
        FixedColumnWidth(MediaQuery.sizeOf(context).width * .55),
      ),
      // The card draws the edge.
      border: TableBorder.symmetric(inside: line),
      children: [
        for (final (header, cells) in rows)
          TableRow(
            decoration: header
                ? BoxDecoration(color: options.colors.surfaceContainerHighest)
                : null,
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: i < cells.length
                      ? InlineCodeText(
                          _inlines(
                            cells[i].children ?? const [],
                            header
                                ? style.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: options.colors.onSurface,
                                  )
                                : style,
                            widget.options,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        // The edge over the cells, the header's color clipped to the corners.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.fromBorderSide(line),
        ),
        decoration: BoxDecoration(
          color: options.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: HoverScrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: FiniteSelectionEdges(child: WillChangePaint(child: table)),
          ),
        ),
      ),
    );
  }
}

/// 行内代码两头的留白：普通空格复制出来无害，收窄才不显得松散。
const _inlineCodePad = TextStyle(letterSpacing: -4);

/// 文件名的颜色：链接色往正文色调一半，满屏文件名也不抢眼。
Color? _fileColor(MarkdownOptions options) =>
    Color.lerp(options.colors.primary, options.colors.onSurface, .45);

bool _isWeb(String? href) =>
    RegExp(r'^(https?|mailto):', caseSensitive: false).hasMatch(href ?? '');

TextSpan _inlines(
  List<md.Node> nodes,
  TextStyle style,
  MarkdownOptions options,
) => TextSpan(
  style: style,
  children: [for (final node in nodes) _inline(node, options)],
);

InlineSpan _inline(md.Node node, MarkdownOptions options) {
  if (node is md.Text) {
    // A comment is the writer's note, not shown (as HTML has it); the
    // parser joins it to the text after it.
    final text = node.text.contains('<!--')
        ? node.text.replaceAll(_htmlComment, '')
        : node.text;
    return TextSpan(text: _unescape(text));
  }
  if (node is! md.Element) return const TextSpan();
  final children = node.children ?? const <md.Node>[];
  List<InlineSpan> inner() => [
    for (final child in children) _inline(child, options),
  ];
  return switch (node.tag) {
    'strong' || 'b' => TextSpan(
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: options.colors.onSurface,
      ),
      children: inner(),
    ),
    'em' || 'i' => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: inner(),
    ),
    'del' => TextSpan(
      style: const TextStyle(decoration: TextDecoration.lineThrough),
      children: inner(),
    ),
    'code' => switch (options.code?.call(_unescape(node.textContent))) {
      // A file's: tappable, in the link's color toned halfway to the text's,
      // so a reply naming many files doesn't read greener than its prose.
      final recognizer? => InlineCodeSpan(
        style: (options.inlineCodeStyle ?? MarkdownView.codeStyle).copyWith(
          color: _fileColor(options),
        ),
        children: [
          const TextSpan(text: ' '),
          TextSpan(
            text: '${_unescape(node.textContent)} ',
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
        ],
      ),
      null => InlineCodeSpan(
        style: (options.inlineCodeStyle ?? MarkdownView.codeStyle),
        children: [
          const TextSpan(text: ' ', style: _inlineCodePad),
          TextSpan(text: _unescape(node.textContent)),
          const TextSpan(text: ' ', style: _inlineCodePad),
        ],
      ),
    },
    'a' => switch (options.link?.call(node.attributes['href'])) {
      final recognizer? => TextSpan(
        // A file's link toned as a file's name in code; a web page's stays.
        style: TextStyle(
          color: _isWeb(node.attributes['href'])
              ? options.colors.primary
              : _fileColor(options),
        ),
        children: [for (final span in inner()) _linked(span, recognizer)],
      ),
      null => TextSpan(
        style: TextStyle(color: options.colors.primary),
        children: inner(),
      ),
    },
    'math' => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: MathView(
        node.textContent,
        display: node.attributes['display'] == 'block',
      ),
    ),
    'br' => const TextSpan(text: '\n'),
    'img' => switch (options.image) {
      final image? => WidgetSpan(
        child: image(
          _unescape(node.attributes['src'] ?? ''),
          _unescape(node.attributes['alt'] ?? ''),
          node.attributes['title'],
          width: double.tryParse(node.attributes['width'] ?? ''),
          height: double.tryParse(node.attributes['height'] ?? ''),
        ),
      ),
      null => TextSpan(text: '[${node.attributes['alt'] ?? 'image'}]'),
    },
    _ => TextSpan(children: inner()),
  };
}

/// Whether [text] is HTML comments alone (`<!-- note -->`), which do not
/// show.
bool isHtmlComment(String text) => _htmlComments.hasMatch(text);

final _htmlComments = RegExp(r'^\s*(?:<!--[\s\S]*?-->\s*)+$');
final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// [span] with every piece of its text tappable: a tap lands on the
/// innermost span, which does not inherit its parent's recognizer.
InlineSpan _linked(InlineSpan span, GestureRecognizer recognizer) =>
    switch (span) {
      // Code in a link keeps its background, and goes where the link does.
      InlineCodeSpan(:final text, :final style, :final children) =>
        InlineCodeSpan(
          text: text,
          style: style,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          children: [
            for (final child in children ?? const <InlineSpan>[])
              _linked(child, recognizer),
          ],
        ),
      // An image in a link (`[![alt](src)](href)`).
      WidgetSpan(:final child, :final alignment)
          when recognizer is TapGestureRecognizer =>
        WidgetSpan(
          alignment: alignment,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: recognizer.onTap, child: child),
          ),
        ),
      TextSpan(:final text, :final style, :final children) => TextSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
        children: [
          for (final child in children ?? const <InlineSpan>[])
            _linked(child, recognizer),
        ],
      ),
      _ => span,
    };

String _unescape(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
