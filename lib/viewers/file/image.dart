import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:interactive_viewer_2/interactive_viewer_2.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.room, required this.path});

  final RoomClient room;
  final String path;

  @override
  State createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) => Container(
            color: ShadTheme.of(context).colorScheme.background,
            child: InteractiveViewer2(
              child: OverflowBox(
                maxHeight: double.infinity,
                maxWidth: double.infinity,
                child: Container(
                  padding: EdgeInsets.all(30),
                  width: constraints.maxWidth * .7,
                  child: FilePreview(room: widget.room, path: widget.path, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
    );
  }
}
