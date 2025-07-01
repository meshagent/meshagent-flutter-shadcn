import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:interactive_viewer_2/interactive_viewer_2.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

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
    return InteractiveViewer2(
      child: Center(
        child: Container(
          padding: EdgeInsets.all(20),
          child: FilePreview(
            room: widget.room,
            path: widget.path,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
