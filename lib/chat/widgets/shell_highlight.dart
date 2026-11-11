import 'package:flutter/painting.dart';

import '../../theme/app_theme.dart';

/// What a word of a shell command is, for its color.
enum _ShellToken { plain, program, string, option }

/// [command] colored as a shell reads it: the program each pipeline stage
/// runs, quoted strings, options. A light tokenizer, not a parser: anything
/// it does not know stays plain. Mobile adaptation: the desktop reads the
/// workbench theme; here the terminal palette is fixed per [dark].
List<TextSpan> highlightShell(String command, {bool dark = false}) {
  final styles = {
    _ShellToken.plain: TextStyle(
      color: dark ? const Color(0xffe5e5df) : const Color(0xff2e2e2a),
    ),
    _ShellToken.program: TextStyle(color: MobileTheme.syntaxCommand(dark)),
    _ShellToken.string: TextStyle(color: MobileTheme.syntaxString(dark)),
    _ShellToken.option: TextStyle(color: MobileTheme.syntaxOption(dark)),
  };
  return [
    for (final (text, token) in _shellTokens(command))
      TextSpan(text: text, style: styles[token]),
  ];
}

/// [command] cut into runs of one [_ShellToken], in order.
List<(String, _ShellToken)> _shellTokens(String command) {
  const plain = _ShellToken.plain;
  const program = _ShellToken.program;
  const string = _ShellToken.string;
  const option = _ShellToken.option;

  final tokens = <(String, _ShellToken)>[];
  void add(String text, _ShellToken token) {
    if (text.isEmpty) return;
    // Merge runs of one token, for fewer spans.
    if (tokens.isNotEmpty && tokens.last.$2 == token) {
      tokens[tokens.length - 1] = (tokens.last.$1 + text, token);
    } else {
      tokens.add((text, token));
    }
  }

  // Whether the next word starts a command (after `&&`, `|`, `;`, `(`…).
  var commandNext = true;
  var i = 0;
  while (i < command.length) {
    final char = command[i];
    if (char == ' ' || char == '\t' || char == '\n') {
      if (char == '\n') commandNext = true;
      add(char, plain);
      i++;
      continue;
    }
    if (char == '"' || char == '\'') {
      var end = i + 1;
      while (end < command.length && command[end] != char) {
        if (char == '"' && command[end] == r'\') end++;
        end++;
      }
      end = end < command.length ? end + 1 : command.length;
      add(command.substring(i, end), string);
      commandNext = false;
      i = end;
      continue;
    }
    const operators = ['&&', '||', '|', ';', '(', ')', '{', '}'];
    final operator = operators
        .where((operator) => command.startsWith(operator, i))
        .firstOrNull;
    if (operator != null) {
      add(operator, plain);
      commandNext = operator != ')' && operator != '}';
      i += operator.length;
      continue;
    }
    // A word: up to a space, a quote or an operator.
    var end = i;
    while (end < command.length && !(' \t\n"\'|&(){}'.contains(command[end]))) {
      end++;
    }
    if (end == i) {
      // A lone `&` (e.g. `2>&1`, a background job).
      add(char, plain);
      i++;
      continue;
    }
    final word = command.substring(i, end);
    final assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(word);
    if (commandNext && !assignment) {
      add(word, program);
      commandNext = false;
    } else if (word.startsWith('-')) {
      add(word, option);
    } else {
      add(word, plain);
    }
    i = end;
  }
  return tokens;
}
