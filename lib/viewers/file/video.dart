import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

class VideoViewer extends StatelessWidget {
  const VideoViewer({super.key, required this.client, required this.path});

  final RoomClient client;
  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(child: FilePreview(client: client, path: path));
  }
}
