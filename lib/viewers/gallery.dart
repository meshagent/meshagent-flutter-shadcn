import 'package:meshagent/document.dart' as docs;
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/viewers/file.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../file_preview/file_preview.dart';
import 'package:flutter/material.dart';
import "builder.dart";

class GalleryViewer extends StatefulWidget {
  const GalleryViewer({required this.document, super.key, required this.client});

  final RoomClient client;
  final MeshDocument document;

  @override
  State createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
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
    return GalleryViewerElement(client: widget.client, element: widget.document.root);
  }
}

class GalleryViewerElement extends StatefulWidget {
  const GalleryViewerElement({required this.client, required this.element, super.key});

  final RoomClient client;
  final docs.MeshElement element;

  @override
  State createState() => _GalleryViewerElementState();
}

class _GalleryViewerElementState extends State<GalleryViewerElement> {
  late final RoomClient client = widget.client;
  late final docs.MeshElement element = widget.element;
  String? selectedImage;

  String? selectedDescription;

  Widget renderSelectedImage(BuildContext context, String path, String description) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(bottom: 10, left: 10, right: 10),
          color: ShadTheme.of(context).colorScheme.background,
          child: Row(
            children: [
              ShadButton.ghost(
                onTapDown: (value) {
                  setState(() {
                    selectedImage = null;
                  });
                },
                child: Icon(LucideIcons.x),
              ),
              Expanded(
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              SizedBox(width: 60),
            ],
          ),
        ),
        Expanded(child: fileViewer(client, path)!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: element,
      builder: (context) {
        final children = element.getChildren();

        return Stack(
          children: [
            Positioned.fill(
              child: Offstage(
                offstage: selectedImage != null,
                child: GridView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  itemCount: children.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(childAspectRatio: 4 / 3, maxCrossAxisExtent: 600),
                  itemBuilder:
                      (context, index) => ShadGestureDetector(
                        cursor: SystemMouseCursors.click,
                        onTapUp: (_) {
                          setState(() {
                            selectedImage = (children[index] as docs.MeshElement).getAttribute("path");
                            selectedDescription = (children[index] as docs.MeshElement).attributes["description"];
                          });
                        },
                        onTapDown: (_) {
                          setState(() {
                            selectedImage = (children[index] as docs.MeshElement).getAttribute("path");
                            selectedDescription = (children[index] as docs.MeshElement).attributes["description"];
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.all(5),
                          foregroundDecoration: BoxDecoration(
                            border: Border.all(color: Color.fromARGB(20, 0, 0, 0)),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
                          clipBehavior: Clip.antiAlias,
                          child: FilePreview(room: client, path: (children[index] as docs.MeshElement).getAttribute("path")),
                        ),
                      ),
                ),
              ),
            ),
            if (selectedImage != null) renderSelectedImage(context, selectedImage!, selectedDescription!),
          ],
        );
      },
    );
  }
}
