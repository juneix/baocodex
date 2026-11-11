// YCode — conversation UI. GPL-3.0-only.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/code_highlight.dart';
import 'ansi_text.dart';
import 'markdown/code_citation.dart';
import 'markdown/file_link.dart';
import 'markdown/markdown_view.dart';
import 'chat_links.dart';
import 'widgets/message_pictures.dart';

class ChatMarkdown extends StatefulWidget {
  const ChatMarkdown({
    super.key,
    required this.state,
    required this.desktopId,
    required this.text,
    this.projectId,
    this.botId,
  });
  final AppState state;
  final String desktopId, text;
  final String? projectId, botId;

  @override
  State<ChatMarkdown> createState() => _ChatMarkdownState();
}

class _ChatMarkdownState extends State<ChatMarkdown> {
  AppState get state => widget.state;
  String get desktopId => widget.desktopId;
  String? get projectId => widget.projectId;
  bool get _hasFiles => projectId != null || widget.botId != null;
  final _links = <String, TapGestureRecognizer>{};
  late MarkdownOptions _options;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _options = MarkdownOptions(
      colors: Theme.of(context).colorScheme,
      headingSizes: MobileTheme.headingSizesOf(context),
      gap: MobileTheme.markdownGap,
      inlineCodeStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: MobileTheme.codeFontSizeOf(context),
        color: Theme.of(context).colorScheme.onSurface,
      ),
      link: _link,
      code: _codeLink,
      image: _image,
    );
  }

  GestureRecognizer? _link(String? href) {
    if (href == null || href.trim().isEmpty) return null;
    return _links.putIfAbsent(
      href,
      () => TapGestureRecognizer()..onTap = () => _openLink(context, href),
    );
  }

  GestureRecognizer? _codeLink(String code) =>
      _hasFiles && FileLink.parseText(code) != null ? _link(code) : null;

  Widget _image(
    String src,
    String alt,
    String? title, {
    double? width,
    double? height,
  }) => ProjectPicture(
    state: state,
    desktopId: desktopId,
    projectId: projectId,
    botId: widget.botId,
    path: src,
    label: alt.isEmpty ? title ?? src : alt,
  );

  @override
  void dispose() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _openLink(BuildContext context, String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (['http', 'https'].contains(uri.scheme)) {
      await confirmExternalLink(context, state, href);
      return;
    }
    final file = FileLink.parseHref(href);
    if (file == null || !_hasFiles) return;
    await _showFile(context, file.path);
  }

  /// Reads [path] off the paired desktop and shows it; where a step row's
  /// open (and a file link's) goes.
  Future<void> _showFile(BuildContext context, String path) => showLinkedFile(
    context,
    state,
    desktopId,
    projectId,
    path,
    botId: widget.botId,
  );

  void _openCitation(String path, int start, int end) =>
      _openLink(context, path);

  Future<List<List<TextSpan>>?> _colorizeBlock(String language, String code) =>
      colorizeCode(
        language,
        code,
        dark: Theme.of(context).brightness == Brightness.dark,
      );

  @override
  Widget build(BuildContext context) {
    final root = state.projects
        .where(
          (ref) => ref.desktopId == desktopId && ref.project.id == projectId,
        )
        .firstOrNull
        ?.project
        .path;
    return CodeCitationScope(
      root: root,
      onOpen: _hasFiles ? _openCitation : null,
      colorizeBlock: _colorizeBlock,
      child: SelectionArea(
        child: MarkdownView(
          widget.text,
          style: MobileTheme.messageStyleOf(context),
          options: _options,
        ),
      ),
    );
  }
}

class CodePanel extends StatelessWidget {
  const CodePanel({super.key, required this.code, this.language = ''});
  final String code, language;
  @override
  Widget build(BuildContext context) => SelectionArea(
    child: ['terminal', 'output', 'command'].contains(language)
        ? MarkdownQuoteBlock(
            text: code,
            child: AnsiText(text: code),
          )
        : CodeCitationScope(
            colorizeBlock: (language, code) => colorizeCode(
              language,
              code,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            child: MarkdownCodeBlock(
              code: code,
              language: language.isEmpty ? null : language,
            ),
          ),
  );
}
