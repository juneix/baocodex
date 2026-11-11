import 'package:flutter/material.dart';

import '../ansi_text.dart';
import '../../theme/app_theme.dart';

/// What a command printed, as far as the mobile shows it. Mobile
/// adaptation of the desktop's `terminal_output.dart`, which replays
/// output through a headless `bao_xterm` terminal with the theme's colors:
/// here the `\r`/`\b` replay runs on the plain text only (what copying
/// takes and uncolored output shows), while colored output renders through
/// `AnsiText` as it came — a rewritten progress line keeps its earlier
/// rows, which the desktop's terminal would overwrite.
class TerminalText {
  const TerminalText._(this.text, this.styled);

  /// The plain text, ANSI stripped and `\r`/`\b` replayed; what copying
  /// takes and uncolored output shows.
  final String text;

  /// Whether the output carries ANSI colors, so a styled renderer shows it.
  final bool styled;
}

final _escape = RegExp(
  '\x1b\\[[0-9;?]*[A-Za-z]|\x1b\\][^\x07\x1b]*(\x07|\x1b\\\\)',
);

/// Replays [output]'s `\r` (a carriage return rewrites its line) and `\b`
/// (a backspace deletes the last character) on the plain text.
TerminalText terminalText(String output) {
  final styled = output.contains('\x1b');
  final plain = output.replaceAll(_escape, '');
  if (!plain.contains('\r') && !plain.contains('\b')) {
    return TerminalText._(plain.trimRight(), styled);
  }
  final lines = <StringBuffer>[StringBuffer()];
  var cursor = 0;
  for (final ch in plain.split('')) {
    switch (ch) {
      case '\r':
        lines[cursor] = StringBuffer();
      case '\b':
        final text = lines[cursor].toString();
        if (text.isNotEmpty) {
          lines[cursor]
            ..clear()
            ..write(text.substring(0, text.length - 1));
        }
      case '\n':
        lines.add(StringBuffer());
        cursor++;
      default:
        lines[cursor].write(ch);
    }
  }
  return TerminalText._(
    [for (final line in lines) line.toString()].join('\n').trimRight(),
    styled,
  );
}

/// A command's printed output as the mobile shows it: `AnsiText` when it
/// carries colors, the replayed plain text when not.
class TerminalPrinted extends StatelessWidget {
  const TerminalPrinted({super.key, required this.output});

  final String output;

  @override
  Widget build(BuildContext context) {
    final printed = terminalText(output);
    if (printed.text.isEmpty) return const SizedBox.shrink();
    if (printed.styled) return AnsiText(text: output);
    return Text(
      printed.text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: MobileType.mono,
        height: 1.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
