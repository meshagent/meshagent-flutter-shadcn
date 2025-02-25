import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

class AudioViewer extends StatelessWidget {
  const AudioViewer({super.key, required this.client, required this.path});

  final RoomClient client;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(child: FilePreview(client: client, path: path));
  }
}
