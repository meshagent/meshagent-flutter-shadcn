import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/document.dart' as docs;

import 'package:flutter/material.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent/schema.dart';
import 'package:meshagent_flutter_shadcn/viewers/editor_state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final sourceCodeStyle = GoogleFonts.sourceCodePro(
  fontSize: 16,
  fontWeight: FontWeight.w500,
  height: 1.3,
);

class DocumentJson extends StatefulWidget {
  DocumentJson({required this.document, super.key});

  final MeshDocument document;

  @override
  State createState() => _DocumentJsonState();
}

class _DocumentJsonState extends State<DocumentJson> {
  @override
  void initState() {
    super.initState();

    widget.document.addListener(this.onDocumentChanged);
    controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    widget.document.removeListener(this.onDocumentChanged);
    controller.dispose();
  }

  void onDocumentChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
      color: Colors.black,
      child: SelectionArea(
        contextMenuBuilder:
            (context, selectableRegionState) => SizedBox.shrink(),
        child: Text.rich(
          selectionColor: defaultSelectionColor,
          TextSpan(
            children: elementSpans(widget.document.root),
            style: sourceCodeStyle,
          ),
        ),
      ),
    );
  }

  ElementEditorController controller = ElementEditorController();

  bool showNull = true;

  List<InlineSpan> _openingTag(docs.Element element, List<docs.Node> children) {
    List<InlineSpan> spans = [code("<"), tag(element.tagName)];
    

    element.elementType.properties.where((p) => p is ValueProperty).map((e) {
      if(element.attributes[e.name] != null || showNull) {
        spans.add(space());
        spans.add(attribute(e.name));
        spans.add(equals("="));

        if (controller.editing == element &&
            controller.editingAttribute == e.name) {
          if (element.attributes[e.name] != null ||
              controller.editing == element &&
                  controller.editingAttribute == e.name) {
            spans.add(quote("\""));
          }
          spans.add(
            WidgetSpan(
              baseline: TextBaseline.alphabetic,
              alignment: PlaceholderAlignment.baseline,
              child: IntrinsicHeight(
                child: IntrinsicWidth(
                  child: ShadInput(
                    focusNode: controller.editingFocusNode,
                    maxLines: null,
                    autofocus: false,
                    onChanged: (value) {
                      controller.editingValue = value;
                    },
                    inputPadding: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    scrollPadding: EdgeInsets.zero,
                    decoration: ShadDecoration.none,
                    selectionColor: defaultSelectionColor,
                    cursorColor: Colors.green,
                    style: sourceCodeStyle.copyWith(
                      color: Colors.white,
                      textBaseline: TextBaseline.alphabetic,
                      letterSpacing: .2,
                    ),
                    controller: controller.controller,
                  ),
                ),
              ),
            ),
          );
          if (element.attributes[e.name] != null ||
              controller.editing == element &&
                  controller.editingAttribute == e.name) {
            spans.add(quote("\""));
          }
        } else {
          final recognizer =
              TapGestureRecognizer()
                ..onTap = () {
                  if (controller.editing == element &&
                      controller.editingAttribute == e.name) {
                    return;
                  }

                  setState(() {
                    controller.startEditing(element, e.name);
                  });
                };

        
            if (element.attributes[e.name] != null ||
                controller.editing == element &&
                    controller.editingAttribute == e.name) {
              spans.add(quote("\"", recognizer));
            }
          
            spans.add(
              element.attributes[e.name] != null
                  ? value("${element.attributes[e.name]}", recognizer)
                  : missingValue("required", recognizer),
            );
          
          if (element.attributes[e.name] != null ||
              controller.editing == element &&
                  controller.editingAttribute == e.name) {
            spans.add(quote("\"", recognizer));
          }
        }
      }
    }).toList();

    if (children.isEmpty) {
      spans.add(space());
      spans.add(code("/>"));
    }
    if (children.isNotEmpty) {
      spans.add(code(">"));
    }

    return spans;
  }

  TextSpan space() {
    return TextSpan(text: " ", style: TextStyle(color: Colors.grey));
  }

  TextSpan value(String text, [GestureRecognizer? recognizer]) {
    return TextSpan(
      text: text,
      style: TextStyle(color: Colors.white),
      recognizer: recognizer,
    );
  }

  TextSpan missingValue(String text, [GestureRecognizer? recognizer]) {
    return TextSpan(
      text: text,
      style: TextStyle(color: Colors.red),
      recognizer: recognizer,
    );
  }

  TextSpan quote(String text, [GestureRecognizer? recognizer]) {
    return TextSpan(
      text: text,
      style: TextStyle(color: Colors.white),
      recognizer: recognizer,
    );
  }

  TextSpan code(String text) {
    return TextSpan(text: text, style: TextStyle(color: Colors.grey));
  }

  TextSpan equals(String text) {
    return TextSpan(text: text, style: TextStyle(color: Colors.grey));
  }

  TextSpan tag(String text) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: Color.from(alpha: 1, red: .5, green: 1, blue: .5),
      ),
    );
  }

  TextSpan attribute(String text) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: Color.from(alpha: 1, red: .6, green: .8, blue: 1),
      ),
    );
  }

  InlineSpan elementContextMenu(
    docs.Element element,
    List<InlineSpan> children,
  ) {
    final List<String> tagNames = [];
    for (final child in element.elementType.properties.where(
      (x) => x is ChildProperty,
    )) {
      for (final tagName in (child as ChildProperty).childTagNames) {
        tagNames.add(tagName);
      }
    }
    return WidgetSpan(
      child: ShadContextMenuRegion(
        items: [
          ...tagNames.map(
            (childTagName) => ShadContextMenuItem(
              onPressed: () async {
                element.createChildElement(childTagName, {});
              },
              child: Text("Add $childTagName"),
            ),
          ),
          ShadContextMenuItem(
            onPressed: () {
              element.delete();
            },
            child: Text("Delete ${element.tagName}"),
          ),
        ],
        child: Text.rich(
          TextSpan(children: children),
          selectionColor: defaultSelectionColor,
          style: sourceCodeStyle,
        ),
      ),
    );
  }

  List<TextSpan> elementSpans(docs.Element element) {
    final children = element.getChildren();

    if(element.tagName == "text") {
      return [
        TextSpan(text: "\n"),
        ...(element.children[0] as docs.TextElement).delta.map((d) => TextSpan(text: jsonEncode(d)+"\n"))
      ];
    }

    return [
      TextSpan(
        children: [
          elementContextMenu(element, _openingTag(element, children)),
          for (var child in children)
            if (child is docs.Element)
              WidgetSpan(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(left: 16 * .6 * 2),
                  child: Text.rich(
                    selectionColor: defaultSelectionColor,
                    TextSpan(
                      children: [...elementSpans(child)],
                      style: sourceCodeStyle,
                    ),
                  ),
                ),
              ),
          if (children.isNotEmpty)
            elementContextMenu(element, [
              code("</"),
              tag(element.tagName),
              code(">"),
            ]),
        ],
      ),
    ];
  }
}
