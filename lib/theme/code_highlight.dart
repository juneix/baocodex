import 'dart:convert';

import 'package:bao_editor/monaco/flutter/monaco_syntax.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';

/// Selectable, naturally sized code preview, not an editor. Files may supply
/// their own vertical scroll view. At most 16K code units / 300 lines are shown.
/// TextMateSyntax currently requires a library-private `_themes` argument;
/// use the public, time-sliced Monarch service without starting Monaco's UI.
class HighlightedCode extends StatelessWidget {
  const HighlightedCode({
    super.key,
    required this.code,
    this.language = '',
    this.lineNumbers = false,
    this.wrap = false,
  });

  final String code;
  final String language;
  final bool lineNumbers;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final normalized = code.replaceAll('\r\n', '\n');
    final preview = _preview(normalized);
    final lang = switch (language.trim().toLowerCase()) {
      'js' => 'javascript',
      'ts' => 'typescript',
      'py' => 'python',
      'sh' || 'bash' || 'shellscript' => 'shell',
      final name => name,
    };
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.45,
    );
    return FutureBuilder<List<List<TextSpan>>?>(
      future: _Syntax.colorize(lang, preview, dark),
      builder: (context, snapshot) {
        final fallback = snapshot.data == null;
        final lines = snapshot.data ?? _lexical(preview, lang, dark);
        final spans = <InlineSpan>[];
        for (var i = 0; i < lines.length; i++) {
          if (i > 0) spans.add(const TextSpan(text: '\n'));
          spans.addAll(lines[i]);
        }
        Widget body = SelectableText.rich(
          TextSpan(children: spans),
          style: style,
        );
        if (lineNumbers) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    List.generate(lines.length, (i) => '${i + 1}').join('\n'),
                    style: style.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
              if (wrap) Expanded(child: body) else body,
            ],
          );
        }
        if (!wrap) {
          body = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: body,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fallback && lang.isNotEmpty)
              Text(
                AppState.phrase('基础词法高亮', 'Basic highlighting'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            body,
            if (preview.length < normalized.length)
              Text(
                AppState.phrase(
                  '预览已截断（最多 16K 字符 / 300 行）',
                  'Preview cut short (16K characters / 300 lines at most)',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        );
      },
    );
  }
}

String _preview(String text) {
  var end = text.length > 16384 ? 16384 : text.length;
  var lines = 1;
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 10 && ++lines > 300) {
      end = i;
      break;
    }
    // A single pathological line cannot monopolize the tokenizer/layout.
    if (i > 0 && i % 2048 == 0) {
      final start = text.lastIndexOf('\n', i - 1) + 1;
      if (i - start >= 2048) {
        end = i;
        break;
      }
    }
  }
  if (end > 0 &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return text.substring(0, end);
}

Future<List<List<TextSpan>>?> colorizeCode(
  String language,
  String code, {
  required bool dark,
}) => _Syntax.colorize(
  switch (language.trim().toLowerCase()) {
    'js' => 'javascript',
    'ts' => 'typescript',
    'py' => 'python',
    'sh' || 'bash' || 'shellscript' => 'shell',
    final name => name,
  },
  code,
  dark,
);

abstract final class _Syntax {
  static final _service = MonacoSyntaxService();
  static final _cache =
      <(String, String, bool), Future<List<List<TextSpan>>?>>{};
  static Future<Map<String, dynamic>>? _themes;

  static Future<List<List<TextSpan>>?> colorize(
    String lang,
    String code,
    bool dark,
  ) {
    final key = (lang, code, dark);
    if (_cache.containsKey(key)) return _cache[key]!;
    if (_cache.length >= 8) _cache.remove(_cache.keys.first);
    return _cache[key] = _load(lang, code, dark);
  }

  static Future<List<List<TextSpan>>?> _load(
    String lang,
    String code,
    bool dark,
  ) async {
    if (lang.isEmpty || lang == 'text' || lang == 'plaintext') return null;
    try {
      if (!(await const MonacoLanguageAssets().availableLanguages()).contains(
        lang,
      )) {
        return null;
      }
      final themes = await (_themes ??= rootBundle
          .loadString('packages/bao_editor/assets/monaco/themes.json')
          .then(
            (s) =>
                (jsonDecode(s) as Map<String, dynamic>)['themes']
                    as Map<String, dynamic>,
          ));
      final theme = themes[dark ? 'vs-dark' : 'vs'] as Map<String, dynamic>;
      final rules = (theme['rules'] as List).cast<Map<String, dynamic>>();
      return await _service.colorize(lang, code, (token) {
        Map<String, dynamic>? best;
        for (final rule in rules) {
          final name = rule['token'] as String;
          if ((name.isEmpty || token == name || token.startsWith('$name.')) &&
              (best == null ||
                  name.length >= (best['token'] as String).length)) {
            best = rule;
          }
        }
        final hex = best?['foreground'] as String?;
        final font = best?['fontStyle'] as String? ?? '';
        return TextStyle(
          color: hex == null ? null : Color(int.parse('ff$hex', radix: 16)),
          fontWeight: font.contains('bold') ? FontWeight.bold : null,
          fontStyle: font.contains('italic') ? FontStyle.italic : null,
        );
      });
    } catch (_) {
      // Missing/broken assets and unsupported grammars are a visible fallback,
      // never an unhandled FutureBuilder error or an editor startup failure.
      return null;
    }
  }
}

List<List<TextSpan>> _lexical(String code, String lang, bool dark) {
  final supported = {
    'dart',
    'javascript',
    'typescript',
    'python',
    'shell',
    'java',
    'c',
    'cpp',
    'rust',
    'go',
    'json',
  };
  if (!supported.contains(lang)) {
    return code.split('\n').map((line) => [TextSpan(text: line)]).toList();
  }
  final hash = lang == 'python' || lang == 'shell';
  final pattern = RegExp(
    r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(//.*|\#.*)|(\b\d+(?:\.\d+)?\b)|(\b(?:class|const|final|var|let|if|else|return|void|import|from|def|for|while|true|false|null|None|async|await|function|fn|pub)\b)''',
  );
  return code.split('\n').map((line) {
    final spans = <TextSpan>[];
    var offset = 0;
    for (final m in pattern.allMatches(line)) {
      if (m.group(2)?.startsWith('#') == true && !hash) continue;
      if (m.start > offset) {
        spans.add(TextSpan(text: line.substring(offset, m.start)));
      }
      final color = m.group(1) != null
          ? (dark ? 0xffce9178 : 0xffa31515)
          : m.group(2) != null
          ? (dark ? 0xff6a9955 : 0xff008000)
          : m.group(3) != null
          ? (dark ? 0xffb5cea8 : 0xff098658)
          : (dark ? 0xff569cd6 : 0xff0000ff);
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(color: Color(color)),
        ),
      );
      offset = m.end;
    }
    if (offset < line.length) spans.add(TextSpan(text: line.substring(offset)));
    return spans;
  }).toList();
}
