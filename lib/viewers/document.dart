import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/document.dart' as docs;
import 'package:meshagent/room_server_client.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../file_preview/file_preview.dart';
import 'package:flutter/material.dart';
import "builder.dart";
import 'package:markdown_widget/markdown_widget.dart';

class DocumentViewer extends StatefulWidget {
  const DocumentViewer({required this.document, super.key, required this.client});

  final RoomClient client;
  final MeshDocument document;

  @override
  State createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  @override
  void initState() {
    super.initState();

    widget.document.addListener(onDocumentChanged);
  }

  @override
  void dispose() {
    super.dispose();
    widget.document.removeListener(onDocumentChanged);
  }

  void onDocumentChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DocumentViewerElement(client: widget.client, element: widget.document.root);
  }
}

class DocumentViewerElement extends StatelessWidget {
  const DocumentViewerElement({required this.client, required this.element, super.key});

  final RoomClient client;
  final docs.MeshElement element;

  List<Widget> buildChildren(BuildContext context) {
    final children = element.getChildren();
    return [
      for (var child in children)
        if (child is docs.MeshElement) DocumentViewerElement(client: client, element: child),
    ];
  }

  List<Widget> buildElement(BuildContext context) {
    if (element.tagName == "heading") {
      return [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(top: element.parent!.getChildren().indexOf(element) > 0 ? 50 : 0, left: 30, right: 30),
                child: Text(element.attributes["text"]!, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ];
    } else if (element.tagName == "content" || element.tagName == "body" || element.tagName == "speech") {
      final mdColor =
          ShadTheme.of(context).textTheme.p.color ??
          DefaultTextStyle.of(context).style.color ??
          ShadTheme.of(context).colorScheme.foreground;
      final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14)) * 1.3;

      return [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(left: 30, right: 30),
                child: MarkdownWidget(
                  config: MarkdownConfig(
                    configs: [
                      LinkConfig(
                        style: TextStyle(
                          color: ShadTheme.of(context).linkButtonTheme.foregroundColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      HrConfig(color: mdColor),
                      H1Config(style: TextStyle(fontSize: baseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold)),
                      H2Config(style: TextStyle(fontSize: baseFontSize * 1.8, color: mdColor, inherit: false)),
                      H3Config(style: TextStyle(fontSize: baseFontSize * 1.6, color: mdColor, inherit: false)),
                      H4Config(style: TextStyle(fontSize: baseFontSize * 1.4, color: mdColor, inherit: false)),
                      H5Config(style: TextStyle(fontSize: baseFontSize * 1.2, color: mdColor, inherit: false)),
                      H6Config(style: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false)),
                      PreConfig(
                        decoration: BoxDecoration(color: ShadTheme.of(context).cardTheme.backgroundColor),
                        textStyle: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor),
                        wrapper: (child, code, language) {
                          return DefaultTextStyle(
                            style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor),
                            child: child,
                          );
                        },
                      ),
                      PConfig(textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false, height: 1.5)),
                      CodeConfig(style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor)),
                      BlockquoteConfig(textColor: mdColor),
                      ListConfig(
                        marker: (isOrdered, depth, index) {
                          return Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Text(
                              "${index + 1}.",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: baseFontSize * 1.0, height: 1.5),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  data: element.attributes["text"]!,
                  shrinkWrap: true,
                ),
              ),
            ),
          ],
        ),
      ];
    } else if (element.tagName == "step") {
      return [Text(element.attributes["description"])];
    } else if (element.tagName == "file") {
      return [FilePreview(room: client, path: element.getAttribute("name"))];
    } else if (element.tagName == "plan") {
      return [
        Container(
          decoration: BoxDecoration(color: Color.from(alpha: 1.0, red: .9, green: .9, blue: .9), borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.only(bottom: 20),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [Text("Plan", style: TextStyle(fontWeight: FontWeight.bold)), ...buildChildren(context)],
          ),
        ),
      ];
    } else {
      return buildChildren(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: element,
      builder:
          (context) => Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [...buildElement(context)],
            ),
          ),
    );
  }
}
