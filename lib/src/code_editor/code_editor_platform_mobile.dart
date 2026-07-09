import 'dart:async';

import 'package:code_forge/code_forge.dart' as forge;
import 'package:code_forge_web/code_forge_web.dart' as web_forge;
import 'package:flutter/material.dart';

import 'code_editor_types.dart';

Future<void>? _initialization;
bool _useTestBackend = false;

Future<void> initializeCodeEditor() {
  return _initialization ??= forge.RustLib.init();
}

Future<void> initializeCodeEditorForTesting() async {
  _useTestBackend = true;
}

class PlatformCodeLineEditingController {
  PlatformCodeLineEditingController({required String initialText})
    : _nativeDelegate = _useTestBackend ? null : forge.CodeForgeController(),
      _testDelegate = _useTestBackend ? web_forge.CodeForgeWebController() : null {
    text = initialText;
  }

  final forge.CodeForgeController? _nativeDelegate;
  final web_forge.CodeForgeWebController? _testDelegate;

  void addListener(VoidCallback listener) {
    if (_nativeDelegate != null) {
      _nativeDelegate.addListener(listener);
    } else {
      _testDelegate!.addListener(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    if (_nativeDelegate != null) {
      _nativeDelegate.removeListener(listener);
    } else {
      _testDelegate!.removeListener(listener);
    }
  }

  String get text => _nativeDelegate?.text ?? _testDelegate!.text;

  set text(String value) {
    if (_nativeDelegate != null) {
      _nativeDelegate.text = value;
    } else {
      _testDelegate!.text = value;
    }
  }

  TextSelection get selection => _nativeDelegate?.selection ?? _testDelegate!.selection;

  set selection(TextSelection value) {
    if (_nativeDelegate != null) {
      _nativeDelegate.selection = value;
    } else {
      _testDelegate!.selection = value;
    }
  }

  Future<void> copy() {
    return _nativeDelegate != null ? Future.sync(_nativeDelegate.copy) : Future.sync(_testDelegate!.copy);
  }

  void cut() {
    if (_nativeDelegate != null) {
      _nativeDelegate.cut();
    } else {
      _testDelegate!.cut();
    }
  }

  void paste() {
    if (_nativeDelegate != null) {
      _nativeDelegate.paste();
    } else {
      _testDelegate!.paste();
    }
  }

  void selectAll() {
    if (_nativeDelegate != null) {
      _nativeDelegate.selectAll();
    } else {
      _testDelegate!.selectAll();
    }
  }

  void dispose() {
    if (_nativeDelegate != null) {
      _nativeDelegate.dispose();
    } else {
      _testDelegate!.dispose();
    }
  }

  forge.CodeForgeController get nativeDelegate => _nativeDelegate!;

  web_forge.CodeForgeWebController get testDelegate => _testDelegate!;
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
  final cursorColor = style?.cursorColor ?? textStyle.color ?? Colors.blue;
  final Widget editor;
  if (_useTestBackend) {
    editor = web_forge.CodeForgeWeb(
      controller: controller.testDelegate,
      language: defaultMode,
      editorTheme: codeTheme?.theme,
      focusNode: focusNode,
      textStyle: textStyle,
      innerPadding: padding is EdgeInsets ? padding : null,
      readOnly: readOnly,
      lineWrap: wordWrap,
      enableGutter: showGutter,
      enableGutterDivider: showGutter,
      selectionStyle: web_forge.CodeSelectionStyle(cursorColor: cursorColor, selectionColor: _selectionColor(cursorColor)),
      gutterStyle: showGutter
          ? web_forge.GutterStyle(
              backgroundColor: style?.backgroundColor,
              lineNumberStyle: textStyle.copyWith(color: textStyle.color?.withValues(alpha: 0.7)),
              activeLineNumberColor: textStyle.color,
            )
          : null,
    );
  } else {
    editor = forge.CodeForge(
      controller: controller.nativeDelegate,
      language: defaultMode,
      editorTheme: codeTheme?.theme,
      focusNode: focusNode,
      textStyle: textStyle,
      innerPadding: padding is EdgeInsets ? padding : null,
      readOnly: readOnly,
      lineWrap: wordWrap,
      enableGutter: showGutter,
      enableGutterDivider: showGutter,
      selectionStyle: forge.CodeSelectionStyle(cursorColor: cursorColor, selectionColor: _selectionColor(cursorColor)),
      gutterStyle: showGutter
          ? forge.GutterStyle(
              backgroundColor: style?.backgroundColor,
              lineNumberStyle: textStyle.copyWith(color: textStyle.color?.withValues(alpha: 0.7)),
              activeLineNumberColor: textStyle.color,
            )
          : null,
    );
  }

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
