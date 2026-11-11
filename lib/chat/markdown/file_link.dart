/// A file the agent pointed at: a markdown link's address
/// (`[a.dart](lib/a.dart#L12)`, as `ClaudeLaunch.fileLinks` asks it to
/// write them), a path in inline code (`lib/a.dart:12`, as Claude Code's
/// own prompt has it), or a search's match. [path] as written: relative to
/// where the agent works, or absolute.
class FileLink {
  const FileLink(this.path);

  final String path;

  /// The file a link to [href] goes to; null for a web, mail or any other
  /// scheme's address, a heading's anchor, or nothing.
  static FileLink? parseHref(String? href) {
    var text = href?.trim() ?? '';
    // `<a b.dart>`, should the brackets come through.
    if (text.startsWith('<') && text.endsWith('>')) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty || text.startsWith('#')) return null;
    if (_scheme.firstMatch(text) case final match?
        when !_drive.hasMatch(text)) {
      if (match[1]!.toLowerCase() != 'file') return null;
      final uri = Uri.tryParse(text);
      if (uri == null) return null;
      var path = _decode(uri.path);
      // `file:///C:/a.dart`.
      if (RegExp(r'^/[A-Za-z]:[/\\]').hasMatch(path)) path = path.substring(1);
      if (path.isEmpty) return null;
      return _isFragment(uri.hasFragment ? uri.fragment : null)
          ? FileLink(path)
          : _withSuffix(path);
    }
    final hash = text.indexOf('#');
    final path = _decode(hash < 0 ? text : text.substring(0, hash));
    if (path.isEmpty) return null;
    // `a.md#usage`: the file, its heading not followed.
    if (hash >= 0) return FileLink(path);
    return _withSuffix(path);
  }

  /// The file inline code names (`lib/a.dart`, `lib/a.dart:12:5`,
  /// `a.dart#L3-L9`); null for code that does not look like a path: with
  /// blanks, quotes or brackets in it, an address, or a word without a
  /// folder or an extension. [blanks] lets a path have spaces (a search's
  /// match).
  static FileLink? parseText(String text, {bool blanks = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 400) return null;
    if (!blanks && RegExp(r'\s').hasMatch(trimmed)) return null;
    if (RegExp('["\'`(){}<>|*?;,=\$]').hasMatch(trimmed)) return null;
    if (trimmed.contains('://')) return null;
    final hash = trimmed.indexOf('#');
    final FileLink link;
    if (hash >= 0) {
      if (!_isFragment(trimmed.substring(hash + 1))) return null;
      link = FileLink(trimmed.substring(0, hash));
    } else {
      link = _withSuffix(trimmed);
    }
    return _pathLike(link.path) ? link : null;
  }

  /// A scheme (`https:`, `vscode:`); a drive (`C:`) is not one.
  static final _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):');
  static final _drive = RegExp(r'^[A-Za-z]:([/\\]|$)');

  /// Whether [fragment] is a line's: `L12`, `L12-L20`, `L12-20`, `L12C5`,
  /// `12`; not a heading's.
  static bool _isFragment(String? fragment) {
    final match = RegExp(
      r'^L?(\d+)(?:C(\d+))?(?:-L?(\d+)(?:C\d+)?)?$',
      caseSensitive: false,
    ).firstMatch(fragment?.trim() ?? '');
    return match != null && int.parse(match[1]!) >= 1;
  }

  /// [text] with a line, a line and column, or lines after it taken off:
  /// `a.dart:12`, `a.dart:12:5`, `a.dart:12-20`.
  static FileLink _withSuffix(String text) {
    final match = RegExp(r'^(.+?):(\d+)(?::(\d+)|-(\d+))?$').firstMatch(text);
    // Not a drive's letter (`C:12`).
    if (match == null || match[1]!.length < 2) return FileLink(text);
    if (int.parse(match[2]!) < 1) return FileLink(text);
    return FileLink(match[1]!);
  }

  /// A folder in it, or a name with an extension: `lib/a.dart`,
  /// `README.md`, `C:\a\b.rs`; not `foo`, `1.5`, `...`, `-v`.
  static bool _pathLike(String path) {
    if (path.isEmpty || path.startsWith('-')) return false;
    if (path.contains('/') || path.contains(r'\')) {
      // Not a bare `/` or `//`.
      return RegExp(r'[A-Za-z0-9_]').hasMatch(path);
    }
    return RegExp(r'^[\w@.+-]*[A-Za-z_][\w@+-]*\.[A-Za-z][\w]{0,9}$')
        .hasMatch(path);
  }

  static String _decode(String text) {
    if (!text.contains('%')) return text;
    try {
      return Uri.decodeComponent(text);
    } on ArgumentError {
      return text;
    } on FormatException {
      return text;
    }
  }

  @override
  bool operator ==(Object other) => other is FileLink && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileLink($path)';
}
