import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

class CodeViewer extends StatelessWidget {
  const CodeViewer({super.key, required this.client, required this.path});

  final RoomClient client;
  final String path;

  @override
  Widget build(BuildContext context) {
    return FilePreview(client: client, path: path);
  }
}
