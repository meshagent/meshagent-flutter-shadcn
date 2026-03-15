import 'package:flutter/widgets.dart';

TextSpan ansiToTextSpan(String source, {TextStyle? baseStyle}) {
  source = _normalizeControlChars(source);
  source = _stripNonSgrCsi(source);

  final sgr = RegExp(r'(\x1B|\u001B)\[([0-9;]*)m');

  final List<InlineSpan> spans = [];
  TextStyle current = baseStyle ?? const TextStyle();
  int last = 0;

  for (final m in sgr.allMatches(source)) {
    if (m.start > last) {
      spans.add(TextSpan(text: source.substring(last, m.start), style: current));
    }

    final params = m[2]!.isEmpty ? <int>[0] : m[2]!.split(';').where((s) => s.isNotEmpty).map(int.parse).toList();
    _applySgr(params, (t) => current = t(current));

    last = m.end;
  }
  if (last < source.length) {
    spans.add(TextSpan(text: source.substring(last), style: current));
  }

  return TextSpan(style: baseStyle, children: spans);
}

String _killSpinnerFrames(String s) {
  final spinner = RegExp(r'\x1B\[1G\x1B\[0K[^\x1B\r\n]\x1B\[1G\x1B\[0K');
  return s.replaceAll(spinner, '');
}

String _stripNonSgrCsi(String s) {
  s = _killSpinnerFrames(s);
  final nonSgrCsi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@A-LN-Z\\^_`{|}~]');
  s = s.replaceAll(nonSgrCsi, '');
  final oscLike = RegExp(r'\x1B[][PX^_].*?(?:\x07|\x1B\\)', dotAll: true);
  return s.replaceAll(oscLike, '');
}

String _normalizeControlChars(String s) {
  final out = <int>[];
  var cursor = 0;

  void insertAtCursor(int code) {
    if (cursor == out.length) {
      out.add(code);
    } else {
      out.insert(cursor, code);
    }
    cursor++;
  }

  void insertCaretControl(int code) {
    insertAtCursor(0x5E);
    final caret = code == 0x7F ? 0x3F : (code + 0x40);
    insertAtCursor(caret);
  }

  for (final code in s.codeUnits) {
    switch (code) {
      case 0x08:
        if (cursor > 0) {
          cursor--;
          out.removeAt(cursor);
        }
        break;
      case 0x0D:
        cursor = 0;
        break;
      default:
        if ((code < 0x20 || code == 0x7F) && code != 0x1B) {
          if (code == 0x0A || code == 0x09) {
            insertAtCursor(code);
          }
          if (code != 0x0A && code != 0x09) {
            insertCaretControl(code);
          }
          break;
        }

        if (cursor == out.length) {
          out.add(code);
        } else {
          out[cursor] = code;
        }
        cursor++;
        break;
    }
  }

  return String.fromCharCodes(out);
}

void _applySgr(List<int> p, void Function(TextStyle Function(TextStyle)) set) {
  var i = 0;

  while (i < p.length) {
    final v = p[i];
    switch (v) {
      case 0:
        set((_) => const TextStyle());
        break;
      case 1:
        set((s) => s.merge(const TextStyle(fontWeight: FontWeight.bold)));
        break;
      case 3:
        set((s) => s.merge(const TextStyle(fontStyle: FontStyle.italic)));
        break;
      case 4:
        set((s) => s.merge(const TextStyle(decoration: TextDecoration.underline)));
        break;
      case 22:
        set((s) => s.merge(const TextStyle(fontWeight: FontWeight.normal)));
        break;
      case 23:
        set((s) => s.merge(const TextStyle(fontStyle: FontStyle.normal)));
        break;
      case 24:
        set((s) => s.merge(const TextStyle(decoration: TextDecoration.none)));
        break;
      case >= 30 && <= 37:
        set((s) => s.merge(TextStyle(color: _ansi16Color(v - 30, false))));
        break;
      case >= 90 && <= 97:
        set((s) => s.merge(TextStyle(color: _ansi16Color(v - 90, true))));
        break;
      case >= 40 && <= 47:
        set((s) => s.merge(TextStyle(backgroundColor: _ansi16Color(v - 40, false))));
        break;
      case >= 100 && <= 107:
        set((s) => s.merge(TextStyle(backgroundColor: _ansi16Color(v - 100, true))));
        break;
      case 38:
        if (i + 1 < p.length) {
          if (p[i + 1] == 5 && i + 2 < p.length) {
            set((s) => s.merge(TextStyle(color: _ansi256Color(p[i + 2]))));
            i += 2;
          } else if (p[i + 1] == 2 && i + 4 < p.length) {
            set((s) => s.merge(TextStyle(color: Color.fromARGB(0xFF, p[i + 2], p[i + 3], p[i + 4]))));
            i += 4;
          }
        }
        break;
      case 48:
        if (i + 1 < p.length) {
          if (p[i + 1] == 5 && i + 2 < p.length) {
            set((s) => s.merge(TextStyle(backgroundColor: _ansi256Color(p[i + 2]))));
            i += 2;
          } else if (p[i + 1] == 2 && i + 4 < p.length) {
            set((s) => s.merge(TextStyle(backgroundColor: Color.fromARGB(0xFF, p[i + 2], p[i + 3], p[i + 4]))));
            i += 4;
          }
        }
        break;
      case 39:
        set((s) => s.merge(const TextStyle(color: null)));
        break;
      case 49:
        set((s) => s.merge(const TextStyle(backgroundColor: null)));
        break;
    }
    i++;
  }
}

Color _ansi16Color(int index, bool bright) {
  const normal = <Color>[
    Color(0xFF000000),
    Color(0xFF800000),
    Color(0xFF008000),
    Color(0xFF808000),
    Color(0xFF000080),
    Color(0xFF800080),
    Color(0xFF008080),
    Color(0xFFC0C0C0),
  ];
  const brightColors = <Color>[
    Color(0xFF808080),
    Color(0xFFFF0000),
    Color(0xFF00FF00),
    Color(0xFFFFFF00),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFF00FFFF),
    Color(0xFFFFFFFF),
  ];
  return bright ? brightColors[index] : normal[index];
}

Color _ansi256Color(int n) {
  if (n < 0) {
    return const Color(0x00000000);
  }
  if (n < 16) {
    return _ansi16Color(n % 8, n >= 8);
  }
  if (n <= 231) {
    final c = n - 16;
    final r = c ~/ 36;
    final g = (c % 36) ~/ 6;
    final b = c % 6;
    int v(int x) => x == 0 ? 0 : 55 + x * 40;
    return Color.fromARGB(0xFF, v(r), v(g), v(b));
  }
  if (n <= 255) {
    final gray = 8 + (n - 232) * 10;
    return Color.fromARGB(0xFF, gray, gray, gray);
  }
  return const Color(0x00000000);
}
