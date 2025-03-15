import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/document.dart' as docs;
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/viewers/editor_state.dart';
import 'package:meshagent_flutter_shadcn/viewers/viewers.dart';
import '../file_preview/file_preview.dart';
import 'package:flutter/material.dart';

class PresentationViewer extends StatefulWidget {
  PresentationViewer({required this.document, super.key, required this.client});

  final RoomClient client;
  final MeshDocument document;

  @override
  State createState() => _PresentationViewerState();
}

class _PresentationViewerState extends State<PresentationViewer> {
  @override
  void initState() {
    super.initState();

    widget.document.addListener(this.onDocumentChanged);
  }

  @override
  void dispose() {
    super.dispose();
    widget.document.removeListener(this.onDocumentChanged);
  }

  void onDocumentChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PresentationViewerElement(
      client: widget.client,
      element: widget.document.root,
    );
  }
}

class PresentationViewerElement extends StatefulWidget {
  PresentationViewerElement({
    required this.client,
    required this.element,
    super.key,
  });

  final RoomClient client;
  final docs.MeshElement element;

  @override
  State createState() => _PresentationViewerElementState();
}

class _PresentationViewerElementState extends State<PresentationViewerElement> {
  List<Widget> buildChildren(BuildContext context) {
    final client = widget.client;
    final element = widget.element;

    final children = element.getChildren();
    return [
      for (var child in children)
        if (child is docs.MeshElement)
          PresentationViewerElement(client: client, element: child),
    ];
  }

  @override
  void initState() {
    super.initState();

    controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    controller.dispose();
  }

  final controller = ElementEditorController();

  Widget buildSlide(BuildContext context, docs.MeshElement slide) {
    final client = widget.client;

    return FittedBox(
      child: UnconstrainedBox(
        child: Container(
          width: 1200,
          height: 900,
          decoration: BoxDecoration(color: Colors.black),
          margin: EdgeInsets.all(30),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: Color.from(alpha: .1, red: 0, green: 0, blue: 0),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: FilePreview(
                  client: client,
                  path: slide.getAttribute("background"),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.all(50),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ElementTextField(
                        controller: controller,
                        element: slide,
                        attributeName: "title",
                        style: GoogleFonts.outfit(
                          textBaseline: TextBaseline.alphabetic,
                          fontSize: 50,
                          color: Colors.white,
                          letterSpacing: .1,
                          height: 1.8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final bp
                              in slide.getChildren().whereType<docs.MeshElement>())
                            ElementTextField(
                              controller: controller,
                              element: bp,
                              attributeName: "line",
                              style: GoogleFonts.outfit(
                                textBaseline: TextBaseline.alphabetic,
                                fontSize: 30,
                                color: Colors.white,
                                letterSpacing: .1,
                                height: 1.8,
                              ),
                              textAlign: TextAlign.left,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final element = widget.element;

    return ChangeNotifierBuilder(
      source: element,
      builder:
          (context) => Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...element.getChildren().map(
                  (slide) => buildSlide(context, slide as docs.MeshElement),
                ),
              ],
            ),
          ),
    );
  }
}
