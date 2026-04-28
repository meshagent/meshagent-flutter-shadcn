import 'package:flutter/material.dart';

import 'code_editor_platform.dart' as platform;
import 'code_editor_types.dart';

class CodeLines {
  const CodeLines._(this.text);

  final String text;

  factory CodeLines.fromText(String text) {
    return CodeLines._(text);
  }
}

typedef ToolbarMenuBuilder =
    Widget Function({
      required BuildContext context,
      required TextSelectionToolbarAnchors anchors,
      required CodeLineEditingController controller,
      required VoidCallback onDismiss,
      required VoidCallback onRefresh,
    });

abstract class SelectionToolbarController {}

abstract class MobileSelectionToolbarController implements SelectionToolbarController {
  factory MobileSelectionToolbarController({required ToolbarMenuBuilder builder}) = _NoopMobileSelectionToolbarController;
}

class _NoopMobileSelectionToolbarController implements MobileSelectionToolbarController {
  _NoopMobileSelectionToolbarController({required this.builder});

  final ToolbarMenuBuilder builder;
}

class CodeChunkController {
  const CodeChunkController();
}

class DefaultCodeLineNumber extends StatelessWidget {
  const DefaultCodeLineNumber({super.key, required this.controller, required this.notifier});

  final CodeLineEditingController controller;
  final ValueNotifier<Object?> notifier;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class DefaultCodeChunkIndicator extends StatelessWidget {
  const DefaultCodeChunkIndicator({super.key, required this.width, required this.controller, required this.notifier});

  final double width;
  final CodeChunkController controller;
  final ValueNotifier<Object?> notifier;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width);
  }
}

typedef CodeIndicatorBuilder =
    Widget Function(
      BuildContext context,
      CodeLineEditingController editingController,
      CodeChunkController chunkController,
      ValueNotifier<Object?> notifier,
    );

class CodeLineEditingController extends ChangeNotifier {
  CodeLineEditingController({CodeLines? codeLines})
    : _delegate = platform.PlatformCodeLineEditingController(initialText: codeLines?.text ?? '') {
    _delegate.addListener(_handleDelegateChange);
  }

  factory CodeLineEditingController.fromText(String text) {
    return CodeLineEditingController(codeLines: CodeLines.fromText(text));
  }

  final platform.PlatformCodeLineEditingController _delegate;

  platform.PlatformCodeLineEditingController get delegate => _delegate;

  String get text => _delegate.text;

  set text(String value) {
    _delegate.text = value;
  }

  TextSelection get selection => _delegate.selection;

  set selection(TextSelection value) {
    _delegate.selection = value;
  }

  String get selectedText {
    final currentSelection = selection;
    if (!currentSelection.isValid) {
      return '';
    }
    if (currentSelection.isCollapsed) {
      return '';
    }
    final start = currentSelection.start.clamp(0, text.length).toInt();
    final end = currentSelection.end.clamp(0, text.length).toInt();
    if (start >= end) {
      return '';
    }
    return text.substring(start, end);
  }

  Future<void> copy() {
    return _delegate.copy();
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

  void _handleDelegateChange() {
    notifyListeners();
  }

  @override
  void dispose() {
    _delegate.removeListener(_handleDelegateChange);
    _delegate.dispose();
    super.dispose();
  }
}

class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    this.controller,
    this.style,
    this.padding,
    this.readOnly = false,
    this.wordWrap = false,
    this.showCursorWhenReadOnly = true,
    this.focusNode,
    this.onChanged,
    this.indicatorBuilder,
    this.toolbarController,
  });

  final CodeLineEditingController? controller;
  final CodeEditorStyle? style;
  final EdgeInsetsGeometry? padding;
  final bool readOnly;
  final bool wordWrap;
  final bool showCursorWhenReadOnly;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final CodeIndicatorBuilder? indicatorBuilder;
  final SelectionToolbarController? toolbarController;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  String? _lastText;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    } else if (oldWidget.onChanged != widget.onChanged) {
      _lastText = widget.controller?.text;
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(CodeLineEditingController? controller) {
    if (controller == null) {
      _lastText = null;
      return;
    }
    _lastText = controller.text;
    controller.addListener(_handleChanged);
  }

  void _detach(CodeLineEditingController? controller) {
    controller?.removeListener(_handleChanged);
  }

  void _handleChanged() {
    final onChanged = widget.onChanged;
    final controller = widget.controller;
    if (onChanged == null || controller == null) {
      return;
    }
    final nextText = controller.text;
    if (nextText == _lastText) {
      return;
    }
    _lastText = nextText;
    onChanged(nextText);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return platform.buildCodeEditor(
      controller: controller.delegate,
      style: widget.style,
      padding: widget.padding,
      readOnly: widget.readOnly,
      wordWrap: widget.wordWrap,
      focusNode: widget.focusNode,
      showGutter: widget.indicatorBuilder != null,
    );
  }
}
