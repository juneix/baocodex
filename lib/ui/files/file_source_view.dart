import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/code_highlight.dart';
import 'page_zoom.dart';

class FileSourceView extends StatefulWidget {
  const FileSourceView({
    super.key,
    required this.text,
    required this.path,
    this.wrap = false,
    this.fontSize,
    this.query = '',
    this.activeMatchOffset,
    this.targetLine,
    this.navigationRevision = 0,
  });

  final String text, path, query;
  final bool wrap;
  final double? fontSize;
  final int? activeMatchOffset, targetLine;
  final int navigationRevision;

  @override
  State<FileSourceView> createState() => _FileSourceViewState();
}

class _FileSourceViewState extends State<FileSourceView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late List<String> _lines;
  late List<int> _starts;
  final _lineMatches = <int, List<({int start, int end, int offset})>>{};
  List<double> _heights = [];
  List<double> _offsets = [];
  Object? _layoutKey, _syntaxKey;
  List<List<TextSpan>>? _syntax;
  late TextStyle _style;
  late TextScaler _textScaler;
  late StrutStyle _strut;
  double _gutter = 0, _contentWidth = 0, _lineHeight = 0;
  bool _wrap = false, _revealScheduled = false, _pendingNavigation = false;
  ({int line, double fraction})? _anchor;

  static const _padding = 12.0;
  static const _gap = 12.0;
  static final _tokens = RegExp(
    r'''(//[^\n]*|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b\d+(?:\.\d+)?\b|\b(?:class|const|final|var|void|return|if|else|for|while|import|export|new|async|await|function|let|def|from|true|false|null|public|private|static|extends|implements|required)\b)''',
  );

  @override
  void initState() {
    super.initState();
    _readText();
    _pendingNavigation = _target != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSyntax();
  }

  void _loadSyntax() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = (widget.text, widget.path, dark);
    if (_syntaxKey == key) return;
    _syntaxKey = key;
    _syntax = null;
    if (widget.text.length > 16000 ||
        _lines.length > 300 ||
        _lines.any((line) => line.length > 1800)) {
      return;
    }
    final extension = widget.path.split('.').last.toLowerCase();
    final language =
        const {
          'md': 'markdown',
          'kt': 'kotlin',
          'yml': 'yaml',
          'txt': 'plaintext',
          'log': 'plaintext',
        }[extension] ??
        extension;
    colorizeCode(
      language,
      widget.text.replaceAll('\r\n', '\n'),
      dark: dark,
    ).then((lines) {
      if (mounted &&
          _syntaxKey == key &&
          lines != null &&
          lines.length == _lines.length) {
        setState(() => _syntax = lines);
      }
    });
  }

  void _readText() {
    final raw = widget.text.split('\n');
    _starts = [];
    var offset = 0;
    for (final line in raw) {
      _starts.add(offset);
      offset += line.length + 1;
    }
    _lines = [
      for (final line in raw)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
    _layoutKey = null;
    _readMatches();
  }

  int _lineAt(int offset) {
    var low = 0, high = _starts.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (_starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _readMatches() {
    _lineMatches.clear();
    if (widget.query.isEmpty) return;
    final expression = RegExp(
      RegExp.escape(widget.query),
      caseSensitive: false,
    );
    for (final match in expression.allMatches(widget.text)) {
      final first = _lineAt(match.start);
      final last = _lineAt(match.end - 1);
      for (var line = first; line <= last; line++) {
        final start = (match.start - _starts[line]).clamp(
          0,
          _lines[line].length,
        );
        final end = (match.end - _starts[line]).clamp(0, _lines[line].length);
        if (start < end) {
          (_lineMatches[line] ??= []).add((
            start: start,
            end: end,
            offset: match.start,
          ));
        }
      }
    }
  }

  @override
  void didUpdateWidget(FileSourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _readText();
    } else if (oldWidget.query != widget.query) {
      _readMatches();
    }
    if (oldWidget.text != widget.text || oldWidget.path != widget.path) {
      _loadSyntax();
    }
    if (oldWidget.targetLine != widget.targetLine ||
        oldWidget.activeMatchOffset != widget.activeMatchOffset ||
        oldWidget.navigationRevision != widget.navigationRevision ||
        oldWidget.query != widget.query) {
      _scheduleReveal(navigate: true);
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  TextPainter _painter(String text, {InlineSpan? content}) => TextPainter(
    text: content == null
        ? TextSpan(text: text.isEmpty ? ' ' : text, style: _style)
        : TextSpan(style: _style, children: [content]),
    textDirection: TextDirection.ltr,
    textScaler: _textScaler,
    strutStyle: _strut,
  );

  void _layout(double width) {
    final style = MobileTheme.codeStyleOf(context)
        .copyWith(fontSize: widget.fontSize);
    final scaler = MediaQuery.textScalerOf(context);
    final key = (widget.text, style, scaler, width, widget.wrap, _syntax);
    if (key == _layoutKey) return;
    if (_vertical.hasClients && _offsets.isNotEmpty) {
      final position = (_vertical.offset - _padding).clamp(0, _offsets.last);
      var low = 0, high = _heights.length;
      while (low + 1 < high) {
        final mid = (low + high) ~/ 2;
        if (_offsets[mid] <= position) {
          low = mid;
        } else {
          high = mid;
        }
      }
      _anchor = (
        line: low,
        fraction: (position - _offsets[low]) / _heights[low],
      );
    }
    _layoutKey = key;
    _style = style;
    _textScaler = scaler;
    _strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final numbers = _painter('9' * _lines.length.toString().length)..layout();
    _gutter = numbers.width;
    numbers.dispose();
    _wrap = widget.wrap || _lines.any((line) => line.length > 1800);
    final available = (width - _gutter - _gap - 2 * _padding).clamp(
      1.0,
      double.infinity,
    );
    final longest = _lines.fold<int>(
      0,
      (size, line) => line.length > size ? line.length : size,
    );
    final bodyWidth = _wrap
        ? available
        : (longest * scaler.scale(style.fontSize!) * 1.1).clamp(
            available,
            double.infinity,
          );
    _contentWidth = bodyWidth + _gutter + _gap + 2 * _padding;
    final sample = _painter('Mg')..layout();
    final lineHeight = sample.height;
    _lineHeight = lineHeight;
    sample.dispose();
    _heights = [
      for (var index = 0; index < _lines.length; index++)
        if (_wrap) _wrappedHeight(index, available) else lineHeight,
    ];
    _offsets = [0];
    for (final height in _heights) {
      _offsets.add(_offsets.last + height);
    }
    _scheduleReveal();
  }

  double _wrappedHeight(int index, double width) {
    final painter = _painter(
      _lines[index],
      content: _syntax == null || _lines[index].isEmpty ? null : _span(index),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  int? get _target {
    final match = widget.activeMatchOffset;
    if (match != null && match >= 0 && match <= widget.text.length) {
      return _lineAt(match);
    }
    final line = widget.targetLine;
    return line == null ? null : (line - 1).clamp(0, _lines.length - 1);
  }

  void _scheduleReveal({bool navigate = false}) {
    _pendingNavigation |= navigate;
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_vertical.hasClients || _offsets.isEmpty) return;
      final navigate = _pendingNavigation;
      _pendingNavigation = false;
      final target = navigate ? _target : null;
      final anchor = _anchor;
      _anchor = null;
      if (target == null && anchor == null) return;
      final line = target ?? anchor!.line.clamp(0, _lines.length - 1);
      final top = _padding + _offsets[line];
      final desired = target != null
          ? top - _vertical.position.viewportDimension * .2
          : top + _heights[line] * anchor!.fraction;
      _vertical.jumpTo(desired.clamp(0, _vertical.position.maxScrollExtent));
      if (!navigate || target == null || !_horizontal.hasClients || _wrap) {
        return;
      }
      var horizontal = 0.0;
      if (widget.activeMatchOffset case final match?) {
        final column = (match - _starts[line]).clamp(0, _lines[line].length);
        final prefix = _painter(_lines[line].substring(0, column))..layout();
        horizontal =
            _padding +
            _gutter +
            _gap +
            prefix.width -
            _horizontal.position.viewportDimension * .2;
        prefix.dispose();
      }
      _horizontal.jumpTo(
        horizontal.clamp(0, _horizontal.position.maxScrollExtent),
      );
    });
  }

  Color? _tokenColor(String token) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (token.startsWith('//') || token.startsWith('#')) {
      return Color(dark ? 0xff95b47f : 0xff52733c);
    }
    if (token.startsWith('"') || token.startsWith("'")) {
      return Color(dark ? 0xffd3a07a : 0xff8b5734);
    }
    if (RegExp(r'^\d').hasMatch(token)) {
      return Color(dark ? 0xff91c9ce : 0xff276a72);
    }
    return Color(dark ? 0xffc8a8e5 : 0xff805a9c);
  }

  List<({int start, int end, TextStyle style})> _styledTokens(int index) {
    if (_syntax case final syntax?) {
      final result = <({int start, int end, TextStyle style})>[];
      var offset = 0;
      void visit(TextSpan span, TextStyle inherited) {
        final style = inherited.merge(span.style);
        final text = span.text;
        if (text != null && text.isNotEmpty) {
          result.add((start: offset, end: offset + text.length, style: style));
          offset += text.length;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) visit(child, style);
        }
      }

      for (final span in syntax[index]) {
        visit(span, const TextStyle());
      }
      if (offset == _lines[index].length) return result;
    }
    return [
      for (final token in _tokens.allMatches(_lines[index]))
        (
          start: token.start,
          end: token.end,
          style: TextStyle(color: _tokenColor(token.group(0)!)),
        ),
    ];
  }

  TextSpan _span(int index) {
    final line = _lines[index];
    if (line.isEmpty) return const TextSpan(text: '');
    final tokens = _styledTokens(index);
    final matches = _lineMatches[index] ?? const [];
    final cuts = {
      0,
      line.length,
      for (final token in tokens) ...[token.start, token.end],
      for (final match in matches) ...[match.start, match.end],
    }.toList()..sort();
    var tokenIndex = 0, matchIndex = 0;
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      final start = cuts[i], end = cuts[i + 1];
      while (tokenIndex < tokens.length && tokens[tokenIndex].end <= start) {
        tokenIndex++;
      }
      while (matchIndex < matches.length && matches[matchIndex].end <= start) {
        matchIndex++;
      }
      final token =
          tokenIndex < tokens.length && tokens[tokenIndex].start <= start
          ? tokens[tokenIndex]
          : null;
      final match =
          matchIndex < matches.length && matches[matchIndex].start <= start
          ? matches[matchIndex]
          : null;
      final active = match != null && match.offset == widget.activeMatchOffset;
      spans.add(
        TextSpan(
          text: line.substring(start, end),
          style: (token?.style ?? const TextStyle()).copyWith(
            color: active ? scheme.onPrimaryContainer : token?.style.color,
            backgroundColor: match == null
                ? null
                : active
                ? scheme.primaryContainer
                : scheme.tertiaryContainer,
          ),
        ),
      );
    }
    return TextSpan(children: spans);
  }

  Widget _row(BuildContext context, int index) {
    return ColoredBox(
      key: ValueKey('file-source-line-${index + 1}'),
      color: _target == index
          ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: ExcludeSemantics(
                child: SizedBox(
                  width: _gutter,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.right,
                    style: _style.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    strutStyle: _strut,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    ...?_span(index).children,
                    if (index + 1 < _lines.length)
                      TextSpan(
                        text: widget.text.substring(
                          _starts[index] + _lines[index].length,
                          _starts[index + 1],
                        ),
                      ),
                  ],
                ),
                key: ValueKey('file-source-text-${index + 1}'),
                style: _style,
                strutStyle: _strut,
                maxLines: _wrap ? (_heights[index] / _lineHeight).ceil() : 1,
                softWrap: _wrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: PageZoom(
      vertical: _vertical,
      horizontal: _horizontal,
      builder: (context, physics, _) => SelectionArea(
        child: LayoutBuilder(
          builder: (context, box) {
            _layout(box.maxWidth);
            final list = Scrollbar(
              controller: _vertical,
              child: ListView.builder(
                key: PageStorageKey(('file-source', widget.path)),
                controller: _vertical,
                physics: physics,
                padding: const EdgeInsets.symmetric(vertical: _padding),
                itemCount: _lines.length,
                itemExtentBuilder: (index, _) => _heights[index],
                itemBuilder: _row,
              ),
            );
            if (_wrap) return list;
            return SingleChildScrollView(
              controller: _horizontal,
              physics: physics,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _contentWidth,
                height: box.maxHeight,
                child: list,
              ),
            );
          },
        ),
      ),
    ),
  );
}
