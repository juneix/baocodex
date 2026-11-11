import 'dart:async';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../theme/app_theme.dart';
import '../../ui/widgets/copy_feedback.dart';
import 'finite_selection_edges.dart';
import 'hover_builder.dart';
import 'will_change_paint.dart';

String _label(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

bool _touchControls(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

/// Code the agent cited from a file, as it is asked to
/// (`ClaudeLaunch.citingCode`): a block fenced as ```` ```12:15:lib/a.dart ````.
class CodeCitation {
  const CodeCitation(this.start, this.end, this.path);

  /// The citation a fence's info string ([language], as markdown takes
  /// it) is; null for any other.
  static CodeCitation? parse(String? language) {
    final match = _info.firstMatch(language?.trim() ?? '');
    if (match == null) return null;
    final start = int.parse(match[1]!);
    final end = int.parse(match[2]!);
    if (start < 1) return null;
    return CodeCitation(start, end < start ? start : end, match[3]!.trim());
  }

  static final _info = RegExp(r'^(\d+):(\d+):(.+)$');

  /// First and last line, from 1.
  final int start;
  final int end;

  /// As the agent wrote it: relative to where it works, or absolute.
  final String path;

  String get fileName => path.split(RegExp(r'[/\\]')).last;

  /// `Ln 14–16`, or `Ln 14` for a line.
  String get lines => start == end ? 'Ln $start' : 'Ln $start–$end';

  /// [path] in [root], the folder the agent works in; null when outside.
  String? pathIn(String root) {
    final paths = RegExp(r'^[A-Za-z]:[/\\]|^\\\\').hasMatch(root)
        ? p.windows
        : p.posix;
    final normalizedRoot = paths.normalize(root);
    final full = paths.normalize(
      paths.isAbsolute(path) ? path : paths.join(normalizedRoot, path),
    );
    return paths.isWithin(normalizedRoot, full) ? full : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CodeCitation &&
      other.start == start &&
      other.end == end &&
      other.path == path;

  @override
  int get hashCode => Object.hash(start, end, path);
}

/// The fence a [CodeCitation] opens. Markdown closes a fence at the first
/// bare one in it, so code that has one (a markdown sample, a prompt)
/// would end early, the rest spilling out as text; but a citation says how
/// many lines it holds, and a bare fence just after that many closes it.
/// Without one there (lines left out, still being written), the first does.
class CodeCitationFenceSyntax extends md.BlockSyntax {
  const CodeCitationFenceSyntax();

  @override
  RegExp get pattern => _opening;

  static final _opening = RegExp(r'^( {0,3})(?:(`{3,})([^`]*)|(~{3,})(.*))$');

  @override
  bool canParse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content);
    return match != null && CodeCitation.parse(match[3] ?? match[5]) != null;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content)!;
    final indent = match[1]!.length;
    final marker = match[2] ?? match[4]!;
    final info = (match[3] ?? match[5]!).trim();
    final citation = CodeCitation.parse(info)!;
    final close = RegExp(
      '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
    );
    final cited = citation.end - citation.start + 1;
    // Lines ahead of the opening fence to the closing one: the one after
    // the lines cited (a fence among them, cited from markdown), else the
    // first. Past them too: more lines than cited, the rest of the reply is
    // not code (#308).
    int? end;
    for (var i = 1; end == null || i <= cited + 1; i++) {
      final line = parser.peek(i);
      if (line == null) break;
      if (!close.hasMatch(line.content)) continue;
      end = i == cited + 1 ? i : end ?? i;
    }
    parser.advance();
    final lines = <String>[];
    for (var i = 1; !parser.isDone && i != end; i++) {
      final line = parser.current.content;
      final spaces = line.length - line.trimLeft().length;
      lines.add(line.substring(spaces < indent ? spaces : indent));
      parser.advance();
    }
    if (end != null) {
      parser.advance();
    } else if (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    final text = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    return md.Element('pre', [
      md.Element.text('code', text)..attributes['class'] = 'language-$info',
    ]);
  }
}

/// [code] in the language a fence names ([language], an id or an alias),
/// in the editor's colors a line at a time; null when it is not known.
typedef CodeBlockColorizer = Future<List<List<TextSpan>>?> Function(
  String language,
  String code,
);

/// What the [CodeCitationCard]s and [MarkdownCodeBlock]s under it can do:
/// open the file cited and color the code.
class CodeCitationScope extends InheritedWidget {
  const CodeCitationScope({
    super.key,
    this.root,
    this.onOpen,
    this.colorizeBlock,
    required super.child,
  });

  /// Where the agent works, which relative paths are in. Files outside it
  /// do not open.
  final String? root;

  /// Opens the file at [path] (absolute, in [root]) with [start] to [end]
  /// (lines from 1) selected.
  final void Function(String path, int start, int end)? onOpen;

  /// Colors a [MarkdownCodeBlock]'s code by its language.
  final CodeBlockColorizer? colorizeBlock;

  static CodeCitationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeCitationScope>();

  @override
  bool updateShouldNotify(CodeCitationScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      colorizeBlock != oldWidget.colorizeBlock;
}

/// A [CodeCitation] as a card: the file's icon, name and lines, which open
/// it there, over the code with its line numbers, all of it; folded, only
/// the title shows.
class CodeCitationCard extends StatelessWidget {
  const CodeCitationCard({
    super.key,
    required this.citation,
    required this.code,
  });

  final CodeCitation citation;
  final String code;

  /// About a dozen lines: how tall a step's diff may be (not a card).
  static const maxCodeHeight = 220.0;

  @override
  Widget build(BuildContext context) =>
      _CodeCard(code: code, citation: citation);
}

/// A fenced code block as a [CodeCitationCard] is, its language (the
/// first word of the fence's info string) for a title and no line numbers.
/// Plain text (no language, or `text`) has no title, so does not fold.
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.onPreview,
  });

  final String code;
  final String? language;

  /// Back to what the source draws (a diagram), from the title.
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) =>
      _CodeCard(code: code, language: language, onPreview: onPreview);
}

/// A markdown quote, as a plain code block's card: its [child] (the quote
/// rendered) in it, the copy button over its corner copying [text].
class MarkdownQuoteBlock extends StatefulWidget {
  const MarkdownQuoteBlock({
    super.key,
    required this.text,
    required this.child,
  });

  final String text;
  final Widget child;

  @override
  State<MarkdownQuoteBlock> createState() => _MarkdownQuoteBlockState();
}

class _MarkdownQuoteBlockState extends State<MarkdownQuoteBlock>
    with CopyFeedback {
  bool _hovered = false;

  void _copy() => copyText(widget.text);

  @override
  Widget build(BuildContext context) {
    final background = MobileTheme.codeSurfaceOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Clear of the copy button on the right.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: widget.child,
            ),
            Positioned(
              top: 5,
              right: 6,
              child: SelectionContainer.disabled(
                child: Visibility.maintain(
                  visible: _hovered || copied || _touchControls(context),
                  child: CodeBlockIconButton(
                    icon: copied ? Icons.check : Icons.content_copy,
                    tooltip: _label(context, '复制', 'Copy'),
                    onTap: _copy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [citation]'s card, or a code block's in [language] without one.
class _CodeCard extends StatefulWidget {
  const _CodeCard({
    required this.code,
    this.citation,
    this.language,
    this.onPreview,
  });

  final String code;
  final CodeCitation? citation;
  final String? language;
  final VoidCallback? onPreview;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> with CopyFeedback {
  final _horizontal = ScrollController();
  bool _expanded = true;
  bool _hovered = false;

  CodeBlockColorizer? _colorizeBlock;

  /// The lines last colored, and their colors: kept for those still the
  /// same while the agent writes on.
  List<String> _coloredLines = const [];
  List<List<TextSpan>> _colors = const [];
  String? _coloredCode;
  bool _coloring = false;

  /// Its language has no grammar: no use asking again.
  bool _uncolored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CodeCitationScope.maybeOf(context);
    if (scope?.colorizeBlock != _colorizeBlock) {
      _colorizeBlock = scope?.colorizeBlock;
      _uncolored = false;
      _coloredCode = null;
    }
    _colorSoon();
  }

  @override
  void didUpdateWidget(_CodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation?.path != widget.citation?.path ||
        oldWidget.language != widget.language) {
      _uncolored = false;
    }
    _colorSoon();
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// Colors the code unless it is colored, one request at a time: code
  /// that grew meanwhile is asked for once that one is answered.
  void _colorSoon() {
    final code = widget.code;
    if (_uncolored || _coloring || code == _coloredCode) return;
    final colored = switch ((widget.citation, widget.language)) {
      (null, final language?) => _colorizeBlock?.call(language, code),
      _ => null,
    };
    if (colored == null) return;
    _coloring = true;
    colored.then(
      (lines) {
        _coloring = false;
        if (!mounted) return;
        _coloredCode = code;
        if (lines == null) {
          _uncolored = true;
        } else {
          setState(() {
            _coloredLines = code.split('\n');
            _colors = lines;
          });
        }
        _colorSoon();
      },
      onError: (_) {
        _coloring = false;
        _uncolored = true;
      },
    );
  }

  void _copy() => copyText(widget.code);

  /// Plain text: a fence that names no language, nor a file.
  bool get _plain =>
      widget.citation == null &&
      widget.onPreview == null &&
      switch (widget.language?.toLowerCase()) {
        null || 'text' || 'txt' || 'plaintext' => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = MobileTheme.codeSurfaceOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: _plain
            // No title to fold it by: the text, the copy button over its
            // corner.
            ? Stack(
                children: [
                  _body(),
                  Positioned(
                    top: 5,
                    right: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Opaque, to hide the text under it: the card's
                        // color is often a see-through one.
                        color: Color.alphaBlend(background, colors.surface),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: _copyButton(context),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [_title(context), if (_expanded) _body()],
              ),
      ),
    );
  }

  Widget _copyButton(BuildContext context) => SelectionContainer.disabled(
    child: Visibility.maintain(
      visible: _hovered || copied || _touchControls(context),
      child: CodeBlockIconButton(
        icon: copied ? Icons.check : Icons.content_copy,
        tooltip: _label(context, '复制', 'Copy'),
        onTap: _copy,
      ),
    ),
  );

  /// The chevron and the empty space fold it; the file opens it there.
  Widget _title(BuildContext context) {
    final hover = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.08);
    return SelectionContainer.disabled(
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            // Faintly lit while hovered.
            color: hovered
                ? hover.withValues(alpha: hover.a * 0.6)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                CodeBlockIconButton(
                  icon: _expanded ? Icons.expand_more : Icons.chevron_right,
                  tooltip: _expanded
                      ? _label(context, '收起', 'Collapse')
                      : _label(context, '展开', 'Expand'),
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
                const SizedBox(width: 2),
                // The rest of the row, the copy button at its end.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: switch (widget.citation) {
                      final citation? => _file(context, citation),
                      null => Text(
                        widget.language ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: MobileType.caption,
                        ),
                      ),
                    },
                  ),
                ),
                if (widget.onPreview case final onPreview?)
                  CodeBlockIconButton(
                    icon: Icons.preview_outlined,
                    tooltip: _label(context, '预览', 'Preview'),
                    onTap: onPreview,
                  ),
                _copyButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The cited file's icon, name and lines, which open it there.
  Widget _file(BuildContext context, CodeCitation citation) {
    final scope = CodeCitationScope.maybeOf(context);
    final open = scope?.onOpen;
    final root = scope?.root;
    final path = root == null ? null : citation.pathIn(root);
    final opens = open != null && path != null;
    Widget file = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description_outlined, size: 15),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            citation.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: MobileType.mono,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          citation.lines,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: MobileType.caption,
          ),
        ),
      ],
    );
    if (opens) {
      file = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => open(path, citation.start, citation.end),
          child: file,
        ),
      );
    }
    return Tooltip(message: citation.path, child: file);
  }

  /// Line numbers from the citation's first, beside the code; the code
  /// scrolls sideways alone, its scrollbar at the card's bottom, not the
  /// code's. A code block has no numbers.
  Widget _body() {
    final lines = widget.code.split('\n');
    final citation = widget.citation;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: MobileTheme.codeFontSizeOf(context),
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.5,
    );
    final numbers = switch (citation) {
      final citation? => SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 14),
          child: Text(
            [for (var i = 0; i < lines.length; i++) '${citation.start + i}']
                .join('\n'),
            textAlign: TextAlign.right,
            style: style.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      null => const SizedBox(width: 12),
    };
    // Where the code starts: the sideways scrollbar's track from there.
    final gutter = switch (citation) {
      final citation? => _numbersWidth(
        '${citation.start + lines.length - 1}',
        style,
      ),
      null => 12.0,
    };
    final code = Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const TextSpan(text: '\n'),
            if (i < _colors.length &&
                i < _coloredLines.length &&
                _coloredLines[i] == line)
              ..._colors[i]
            else
              TextSpan(text: line),
          ],
        ],
      ),
      softWrap: false,
    );
    // As tall as its lines, so nothing scrolls down in it: the page does.
    return MediaQuery(
      // The scrollbar's padding is the media's.
      data: MediaQuery.of(context)
          .copyWith(padding: EdgeInsets.only(left: gutter)),
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: _hovered,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numbers,
              Expanded(
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 12),
                  child: FiniteSelectionEdges(
                    child: WillChangePaint(child: code),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The line numbers' width with their padding: as wide as the last.
  double _numbersWidth(String last, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: last, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 12 + 14;
  }
}

/// A small icon button of a code card's title, or a diagram's toolbar.
class CodeBlockIconButton extends StatelessWidget {
  const CodeBlockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: _touchControls(context) ? 36 : 22,
            height: _touchControls(context) ? 36 : 22,
            decoration: BoxDecoration(
              color: hovered
                  ? Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: 14,
              color: hovered
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );
}
