import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';

class CodeHighlightThemeMode {
  const CodeHighlightThemeMode({required this.mode});

  final Mode mode;
}

class CodeHighlightTheme {
  const CodeHighlightTheme({required this.languages, required this.theme});

  final Map<String, CodeHighlightThemeMode> languages;
  final Map<String, TextStyle> theme;
}

class CodeEditorStyle {
  const CodeEditorStyle({this.backgroundColor, this.cursorColor, this.fontFamily, this.fontSize, this.textColor, this.codeTheme});

  final Color? backgroundColor;
  final Color? cursorColor;
  final String? fontFamily;
  final double? fontSize;
  final Color? textColor;
  final CodeHighlightTheme? codeTheme;
}
