import 'package:meshagent/document.dart' as docs;
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
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
                child: Text(element.getAttribute("text")!, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ];
    } else if (element.tagName == "content" || element.tagName == "body" || element.tagName == "speech") {
      return [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(left: 30, right: 30),
                child: MarkdownWidget(
                  config: buildChatBubbleMarkdownConfig(context),
                  data: element.getAttribute("text")!,
                  shrinkWrap: true,
                ),
              ),
            ),
          ],
        ),
      ];
    } else if (element.tagName == "step") {
      return [Text(element.getAttribute("description"))];
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
            children: [
              Text("Plan", style: TextStyle(fontWeight: FontWeight.bold)),
              ...buildChildren(context),
            ],
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
      builder: (context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [...buildElement(context)]),
      ),
    );
  }
}
