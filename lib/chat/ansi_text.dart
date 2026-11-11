import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Safe styled transcript, NOT a PTY/terminal emulator: cursor addressing,
/// screen clearing, carriage-return rewriting, input and raw PTY are unsupported.
/// OSC (including hyperlinks/clipboard), DCS and unknown controls are discarded.
/// Parsing/layout are bounded to 32K input code units and 2048 style runs.
class AnsiText extends StatelessWidget {
  const AnsiText({super.key, required this.text, this.selectable = true});

  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final span = _parse(text, dark);
    final style = MobileTheme.codeStyleOf(context);
    return selectable
        ? SelectableText.rich(span, style: style)
        : Text.rich(span, style: style);
  }
}

TextSpan _parse(String source, bool dark) {
  var limit = source.length > 32768 ? 32768 : source.length;
  if (limit < source.length &&
      limit > 0 &&
      source.codeUnitAt(limit - 1) >= 0xd800 &&
      source.codeUnitAt(limit - 1) <= 0xdbff) {
    limit--;
  }
  final spans = <TextSpan>[];
  var buffer = StringBuffer();
  Color? foreground;
  Color? background;
  var bold = false;
  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: TextStyle(
          color: foreground,
          backgroundColor: background,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
    buffer = StringBuffer();
  }

  var i = 0;
  while (i < limit && spans.length < 2048) {
    final c = source.codeUnitAt(i++);
    final escape = c == 27;
    var kind = c;
    if (escape) {
      if (i >= limit) break;
      kind = source.codeUnitAt(i++);
    }
    if ((escape && kind == 91) || c == 0x9b) {
      final start = i;
      while (i < limit &&
          !(source.codeUnitAt(i) >= 0x40 && source.codeUnitAt(i) <= 0x7e)) {
        i++;
      }
      if (i >= limit) break;
      final finalByte = source.codeUnitAt(i++);
      final parameters = source.substring(start, i - 1);
      if (finalByte != 109 || !RegExp(r'^[0-9;]*$').hasMatch(parameters)) {
        continue;
      }
      flush();
      final codes = parameters.isEmpty
          ? [0]
          : parameters.split(';').map((s) => int.tryParse(s) ?? 0).toList();
      for (var n = 0; n < codes.length; n++) {
        final code = codes[n];
        if (code == 0) {
          foreground = null;
          background = null;
          bold = false;
        } else if (code == 1) {
          bold = true;
        } else if (code == 22) {
          bold = false;
        } else if (code == 39) {
          foreground = null;
        } else if (code == 49) {
          background = null;
        } else if (code >= 30 && code <= 37) {
          foreground = _color(code - 30, dark);
        } else if (code >= 90 && code <= 97) {
          foreground = _color(code - 90 + 8, dark);
        } else if (code >= 40 && code <= 47) {
          background = _color(code - 40, dark);
        } else if (code >= 100 && code <= 107) {
          background = _color(code - 100 + 8, dark);
        } else if (code == 38 || code == 48) {
          Color? color;
          if (n + 2 < codes.length && codes[n + 1] == 5) {
            color = _color(codes[n + 2].clamp(0, 255), dark);
            n += 2;
          } else if (n + 4 < codes.length && codes[n + 1] == 2) {
            color = Color.fromARGB(
              255,
              codes[n + 2].clamp(0, 255),
              codes[n + 3].clamp(0, 255),
              codes[n + 4].clamp(0, 255),
            );
            n += 4;
          }
          if (color != null) {
            if (code == 38) {
              foreground = color;
            } else {
              background = color;
            }
          }
        }
      }
      continue;
    }
    // String controls terminate at ST; OSC may also terminate at BEL.
    if ((escape && [93, 80, 88, 94, 95].contains(kind)) ||
        [0x9d, 0x90, 0x98, 0x9e, 0x9f].contains(c)) {
      final osc = kind == 93 || c == 0x9d;
      while (i < limit) {
        final value = source.codeUnitAt(i++);
        if ((osc && value == 7) || value == 0x9c) break;
        if (value == 27 && i < limit && source.codeUnitAt(i) == 92) {
          i++;
          break;
        }
      }
      continue;
    }
    if (escape) {
      // ESC intermediate bytes plus final byte (e.g. charset designators).
      if (kind >= 0x20 && kind <= 0x2f) {
        while (i < limit &&
            source.codeUnitAt(i) >= 0x20 &&
            source.codeUnitAt(i) <= 0x2f) {
          i++;
        }
        if (i < limit) i++;
      }
      continue;
    }
    if (c == 10 || c == 9 || (c >= 32 && !(c >= 0x7f && c <= 0x9f))) {
      buffer.writeCharCode(c);
    }
  }
  flush();
  if (i < source.length) spans.add(const TextSpan(text: '\n[输出已截断]'));
  return TextSpan(children: spans);
}

Color _color(int index, bool dark) {
  const normal = [
    0xff242424,
    0xffb42318,
    0xff20752d,
    0xff8a6300,
    0xff245ac2,
    0xff9235a0,
    0xff087e8b,
    0xffd0d0d0,
  ];
  const bright = [
    0xff767676,
    0xffff6b68,
    0xff78c86b,
    0xffedcb68,
    0xff79a8ff,
    0xffdc8de2,
    0xff67d4df,
    0xfff2f2f2,
  ];
  if (index < 8) return Color(dark ? bright[index] : normal[index]);
  if (index < 16) return Color(bright[index - 8]);
  if (index >= 232) {
    final level = 8 + (index - 232) * 10;
    return Color.fromARGB(255, level, level, level);
  }
  final value = index - 16;
  int channel(int n) => n == 0 ? 0 : 55 + n * 40;
  return Color.fromARGB(
    255,
    channel(value ~/ 36),
    channel((value ~/ 6) % 6),
    channel(value % 6),
  );
}
