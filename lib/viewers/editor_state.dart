import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/document.dart' as docs;

class ElementEditorController extends ChangeNotifier {
  Object? _editing;
  Object? get editing {
    return _editing;
  }

  String? _editingAttribute;
  String? get editingAttribute {
    return _editingAttribute;
  }

  FocusNode? _editingFocusNode;
  FocusNode? get editingFocusNode {
    return _editingFocusNode;
  }

  Object? editingValue;

  TextEditingController? _controller;
  TextEditingController? get controller {
    return _controller;
  }

  void startEditing(docs.MeshElement element, String attributeName) {
    String text = element.attributes[attributeName] ?? "";
    _controller = TextEditingController(text: text);
    _controller!.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    editingValue = _controller!.text;
    _editing = element;
    _editingAttribute = attributeName;
    _editingFocusNode?.dispose();
    _editingFocusNode = FocusNode(
      onKeyEvent: (_, evt) {
        if (evt.logicalKey == LogicalKeyboardKey.escape) {
          _editing = null;
          _editingAttribute = null;

          notifyListeners();

          return KeyEventResult.handled;
        } else if (evt.logicalKey == LogicalKeyboardKey.enter) {
          _editingFocusNode!.unfocus();

          _editing = null;
          _editingAttribute = null;

          notifyListeners();
        }
        return KeyEventResult.ignored;
      },
    );
    _editingFocusNode!.requestFocus();
    _editingFocusNode!.addListener(() {
      if (!_editingFocusNode!.hasFocus) {
        element.setAttribute(attributeName, editingValue);

        _editing = null;
        _editingAttribute = null;

        notifyListeners();
      }
    });

    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    _editingFocusNode?.dispose();
  }
}

const defaultSelectionColor = Color.from(alpha: 1, red: .1, green: .2, blue: .1);

class ElementTextField extends StatefulWidget {
  const ElementTextField({
    super.key,
    this.textAlign,
    this.maxLines,
    this.minLines,
    required this.controller,
    required this.element,
    required this.attributeName,
    required this.style,
    this.cursorColor = Colors.green,
    this.selectionColor = defaultSelectionColor,
    this.editingBackground = const Color.from(alpha: .1, red: 1, green: 1, blue: 1),
  });

  final ElementEditorController controller;
  final docs.MeshElement element;
  final String attributeName;
  final TextStyle style;
  final Color selectionColor;
  final Color editingBackground;
  final Color cursorColor;
  final int? maxLines;
  final int? minLines;
  final TextAlign? textAlign;

  @override
  State createState() => _ElementTextFieldState();
}

class _ElementTextFieldState extends State<ElementTextField> {
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    focusNode.addListener(() {
      setState(() {
        focused = focusNode.hasFocus;
      });
    });
    widget.controller.addListener(onControllerChanged);
  }

  void onControllerChanged() {
    editing = widget.controller.editing == widget.element && widget.controller.editingAttribute == widget.attributeName;
    focused = false;
  }

  @override
  void dispose() {
    super.dispose();
    focusNode.dispose();
    widget.controller.removeListener(onControllerChanged);
  }

  bool focused = false;
  bool editing = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return editing
        ? Container(
          foregroundDecoration: BoxDecoration(border: Border.all(color: widget.cursorColor, width: 2)),
          child: IntrinsicHeight(
            child: IntrinsicWidth(
              child: EditableText(
                onChanged: (value) {
                  controller.editingValue = value;
                },
                textHeightBehavior: TextHeightBehavior(
                  applyHeightToFirstAscent: true,
                  applyHeightToLastDescent: true,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                scrollPadding: EdgeInsets.zero,
                expands: true,
                textAlign: widget.textAlign ?? TextAlign.start,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                controller: controller.controller!,
                focusNode: controller.editingFocusNode!,
                style: widget.style,
                cursorColor: widget.cursorColor,
                backgroundCursorColor: widget.selectionColor,
                selectionColor: widget.selectionColor,
              ),
            ),
          ),
        )
        : Focus(
          focusNode: focusNode,
          child: GestureDetector(
            onTap: () {
              focusNode.requestFocus();
            },
            onDoubleTap: () {
              controller.startEditing(widget.element, widget.attributeName);
            },
            child: Container(
              constraints: BoxConstraints(minWidth: 10),
              foregroundDecoration: focused ? BoxDecoration(border: Border.all(color: widget.cursorColor, width: 2)) : null,
              padding: EdgeInsets.only(right: 3),
              child: Text(widget.element.attributes[widget.attributeName], style: widget.style, textAlign: widget.textAlign),
            ),
          ),
        );
  }
}
