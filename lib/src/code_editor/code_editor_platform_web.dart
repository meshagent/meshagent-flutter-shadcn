import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lapce_editor_flutter/lapce_editor_flutter.dart' as lapce;

import 'code_editor_types.dart';

Future<void> initializeCodeEditor() async {}
Future<void> initializeCodeEditorForTesting() async {}

class PlatformCodeLineEditingController {
  PlatformCodeLineEditingController({required String initialText}) : _delegate = lapce.LapceEditorController(text: initialText);

  static const _clipboard = lapce.SystemEditorClipboard();

  final lapce.LapceEditorController _delegate;

  void addListener(VoidCallback listener) {
    _delegate.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    _delegate.removeListener(listener);
  }

  String get text => _delegate.text;

  set text(String value) {
    final readOnly = _delegate.readOnly;
    _delegate.readOnly = false;
    _delegate.setText(value);
    _delegate.readOnly = readOnly;
  }

  TextSelection get selection {
    final region = _delegate.selection.lastInserted;
    if (region == null) {
      return const TextSelection.collapsed(offset: 0);
    }
    return TextSelection(baseOffset: region.start.value, extentOffset: region.end.value);
  }

  set selection(TextSelection value) {
    final textLength = _delegate.textLength;
    _delegate.setSelection(
      lapce.Selection.region(
        lapce.TextOffset(value.baseOffset.clamp(0, textLength)),
        lapce.TextOffset(value.extentOffset.clamp(0, textLength)),
      ),
    );
  }

  Future<void> copy() {
    return _delegate.copy(_clipboard);
  }

  void cut() {
    unawaited(_delegate.cut(_clipboard));
  }

  void paste() {
    unawaited(_delegate.paste(_clipboard));
  }

  void selectAll() {
    _delegate.selectAll();
  }

  void dispose() {
    _delegate.dispose();
  }

  lapce.LapceEditorController get rawController => _delegate;
}

Widget buildCodeEditor({
  required PlatformCodeLineEditingController controller,
  required CodeEditorStyle? style,
  required EdgeInsetsGeometry? padding,
  required bool readOnly,
  required bool wordWrap,
  required FocusNode? focusNode,
  required bool showGutter,
}) {
  return _LapceCodeEditor(
    controller: controller.rawController,
    style: style,
    padding: padding,
    readOnly: readOnly,
    wordWrap: wordWrap,
    focusNode: focusNode,
    showGutter: showGutter,
  );
}

class _LapceCodeEditor extends StatefulWidget {
  const _LapceCodeEditor({
    required this.controller,
    required this.style,
    required this.padding,
    required this.readOnly,
    required this.wordWrap,
    required this.focusNode,
    required this.showGutter,
  });

  final lapce.LapceEditorController controller;
  final CodeEditorStyle? style;
  final EdgeInsetsGeometry? padding;
  final bool readOnly;
  final bool wordWrap;
  final FocusNode? focusNode;
  final bool showGutter;

  @override
  State<_LapceCodeEditor> createState() => _LapceCodeEditorState();
}

class _LapceCodeEditorState extends State<_LapceCodeEditor> {
  lapce.TreeSitterSyntaxHighlighter? _syntaxHighlighter;

  @override
  void initState() {
    super.initState();
    _replaceSyntaxHighlighter();
  }

  @override
  void didUpdateWidget(covariant _LapceCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        _languageForStyle(oldWidget.style) != _languageForStyle(widget.style) ||
        !identical(oldWidget.style?.codeTheme?.theme, widget.style?.codeTheme?.theme)) {
      _replaceSyntaxHighlighter();
    }
  }

  @override
  void dispose() {
    _syntaxHighlighter?.dispose();
    super.dispose();
  }

  void _replaceSyntaxHighlighter() {
    _syntaxHighlighter?.dispose();
    final language = _languageForStyle(widget.style);
    if (language == lapce.LapceLanguage.plainText) {
      _syntaxHighlighter = null;
      return;
    }
    _syntaxHighlighter = lapce.TreeSitterSyntaxHighlighter(
      controller: widget.controller,
      language: language,
      theme: lapce.SyntaxHighlightTheme(widget.style?.codeTheme?.theme ?? const <String, TextStyle>{}),
    );
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.readOnly = widget.readOnly;
    final defaultTextStyle = DefaultTextStyle.of(context).style;
    final cursorColor = widget.style?.cursorColor ?? defaultTextStyle.color ?? Colors.blue;
    final backgroundColor = widget.style?.backgroundColor ?? Colors.transparent;
    final foregroundColor = widget.style?.textColor ?? defaultTextStyle.color ?? Colors.black;
    final resolvedPadding = widget.padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero;

    return lapce.LapceEditor(
      controller: widget.controller,
      focusNode: widget.focusNode,
      showGutter: widget.showGutter,
      syntaxHighlightProvider: _syntaxHighlighter,
      theme: lapce.LapceEditorTheme(
        background: backgroundColor,
        foreground: foregroundColor,
        caret: cursorColor,
        selection: cursorColor.withValues(alpha: 0.25),
        currentLine: Colors.transparent,
        textStyle: defaultTextStyle.copyWith(
          fontFamily: widget.style?.fontFamily,
          fontSize: widget.style?.fontSize,
          color: foregroundColor,
        ),
        padding: resolvedPadding,
        wrapMethod: widget.wordWrap ? const lapce.WrapMethod.editorWidth() : const lapce.WrapMethod.none(),
      ),
    );
  }
}

lapce.LapceLanguage _languageForStyle(CodeEditorStyle? style) {
  final modeName = style?.codeTheme?.languages['default']?.mode.name;
  if (modeName == null || modeName.isEmpty) {
    return lapce.LapceLanguage.plainText;
  }
  return lapce.LapceLanguage.fromName(modeName) ?? lapce.LapceLanguage.plainText;
}
