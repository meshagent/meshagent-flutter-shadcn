import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

class PdfViewer extends StatelessWidget {
  const PdfViewer({super.key, required this.client, required this.path});

  final RoomClient client;
  final String path;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Container(
          color: Color.from(alpha: 1, red: .9, green: .9, blue: .9),
          padding: EdgeInsets.all(50),
          child: FilePreview(client: client, path: path),
        ),
      ],
    );
  }
}
