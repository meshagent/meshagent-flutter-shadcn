import 'dart:async';

import 'package:code_forge_web/code_forge_web.dart' as forge;
import 'package:flutter/material.dart';

import 'code_editor_types.dart';

class PlatformCodeLineEditingController {
  PlatformCodeLineEditingController({required String initialText}) : _delegate = forge.CodeForgeWebController() {
    _delegate.text = initialText;
  }

  final forge.CodeForgeWebController _delegate;

  void addListener(VoidCallback listener) {
    _delegate.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    _delegate.removeListener(listener);
  }

  String get text => _delegate.text;

  set text(String value) {
    _delegate.text = value;
  }

  TextSelection get selection => _delegate.selection;

  set selection(TextSelection value) {
    _delegate.selection = value;
  }

  Future<void> copy() {
    return Future.sync(_delegate.copy);
  }

  void cut() {
    _delegate.cut();
  }

  void paste() {
    _delegate.paste();
  }

  void selectAll() {
    _delegate.selectAll();
  }

  void dispose() {
    _delegate.dispose();
  }

  forge.CodeForgeWebController get rawController => _delegate;
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
  final codeTheme = style?.codeTheme;
  final defaultMode = codeTheme?.languages['default']?.mode;
  final textStyle = TextStyle(fontFamily: style?.fontFamily, fontSize: style?.fontSize, color: style?.textColor);
  final editor = forge.CodeForgeWeb(
    controller: controller.rawController,
    language: defaultMode,
    editorTheme: codeTheme?.theme,
    focusNode: focusNode,
    textStyle: textStyle,
    innerPadding: padding is EdgeInsets ? padding : null,
    readOnly: readOnly,
    lineWrap: wordWrap,
    enableGutter: showGutter,
    enableGutterDivider: showGutter,
    selectionStyle: forge.CodeSelectionStyle(
      cursorColor: style?.cursorColor ?? textStyle.color ?? Colors.blue,
      selectionColor: _selectionColor(style?.cursorColor ?? textStyle.color ?? Colors.blue),
    ),
    gutterStyle: showGutter
        ? forge.GutterStyle(
            backgroundColor: style?.backgroundColor,
            lineNumberStyle: textStyle.copyWith(color: textStyle.color?.withValues(alpha: 0.7)),
            activeLineNumberColor: textStyle.color,
          )
        : null,
  );

  final scopedEditor = LayoutBuilder(
    builder: (context, constraints) {
      final mediaQuery = MediaQuery.of(context);
      final resolvedPadding = padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero;
      final rawWidth = constraints.hasBoundedWidth ? constraints.maxWidth : mediaQuery.size.width;
      final rawHeight = constraints.hasBoundedHeight ? constraints.maxHeight : mediaQuery.size.height;
      final width = (rawWidth - resolvedPadding.right).clamp(0.0, double.infinity);
      final height = (rawHeight - resolvedPadding.bottom).clamp(0.0, double.infinity);
      return MediaQuery(
        data: mediaQuery.copyWith(size: Size(width, height)),
        child: editor,
      );
    },
  );

  if (style?.backgroundColor == null) {
    return scopedEditor;
  }

  return ColoredBox(color: style!.backgroundColor!, child: scopedEditor);
}

Color _selectionColor(Color cursorColor) {
  return cursorColor.withValues(alpha: 0.25);
}
