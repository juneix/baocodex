/// What the agent suggests the user send next, written by itself at the
/// end of its reply, each in a [tag]: no request of its own. Shown over the
/// composer, apart from what it said (see [AssistantTextItem.text]).
abstract final class ReplySuggestions {
  static const tag = 'reply_suggestion';

  /// The most shown.
  static const max = 4;

  /// The longest shown, in characters: a line to send, not a message.
  static const maxLength = 80;

  /// [text] without the suggestions at its end, and without one still
  /// being written there (streaming): what the agent said. Only at the
  /// end: one spoken of in the middle of the text, or in code, stays.
  static String strip(String text) => switch (_tailAt(text)) {
    final at? => text.substring(0, at),
    null => text,
  };

  /// What the agent suggests the user send next, at the end of [text],
  /// at most [max] lines of at most [maxLength] characters each.
  static List<String> of(String text) {
    final at = _tailAt(text);
    if (at == null) return const [];
    return [
      for (final match in _whole.allMatches(text, at))
        for (final line in match[1]!.split('\n'))
          if (line.trim() case final said
              when said.isNotEmpty && said.length <= maxLength)
            said,
    ].take(max).toList();
  }

  /// [text] with [suggestions] at its end, as the agent writes them.
  static String write(String text, List<String> suggestions) =>
      [text, for (final said in suggestions) '<$tag>$said</$tag>'].join('\n');

  static const _open = '<$tag>';

  /// What one says: any text but a tag, code in it too (`npm test`).
  static final _whole = RegExp('<$tag>([^<]*)</$tag>');

  /// Before each, a list's marker some models put there.
  static const _marker = r'(?:(?:[-*•]|\d+[.)])[ \t]*)?';

  /// Whole ones; then perhaps one under way, its end tag not yet whole
  /// (not one in code, its tag the last of it: `` `<tag>` ``); or the start
  /// of its tag.
  static final _tail = RegExp(
    '(?:\\s*$_marker<$tag>[^<]*</$tag>)*\\s*'
    '(?:$_marker<$tag>(?:[^<`][^<]*)?(?:</?[a-z_]*)?|(<[a-z_]*))?\$',
  );

  /// Where the suggestions at the end of [text] start (the space before
  /// them too); null when there are none.
  static int? _tailAt(String text) {
    final lt = text.lastIndexOf('<');
    if (lt < 0) return null;
    // Cheap first: no tag of them, nor the start of one at the end.
    if (!text.contains(_open) && !_open.startsWith(text.substring(lt))) {
      return null;
    }
    final match = _tail.firstMatch(text);
    if (match == null || match.start == match.end) return null;
    // A tag's start at the end that is not theirs: none.
    if (match[1] case final start? when !_open.startsWith(start)) return null;
    final at = match.start;
    // Only space before: nothing said.
    if (text.substring(at).trim().isEmpty) return null;
    return at;
  }
}
