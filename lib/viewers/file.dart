import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import "package:meshagent_flutter_shadcn/file_preview/file_preview.dart";

import "file/image.dart";
import "file/video.dart";
import "file/audio.dart";
import "file/lance.dart";
import "file/parquet.dart";

Widget? fileViewer(RoomClient client, String path) {
  final kind = classifyFile(path);

  switch (kind) {
    case FileKind.thread:
      return ChatThread(path: path, room: client, includeLocalParticipant: client.localParticipant != null);
    case FileKind.lance:
      return const LanceViewer();
    case FileKind.pdf:
    case FileKind.code:
    case FileKind.markdown:
    case FileKind.tsv:
    case FileKind.custom:
      return FilePreview(room: client, path: path);
    case FileKind.image:
      return ImageViewer(room: client, path: path);
    case FileKind.video:
      return VideoViewer(room: client, path: path);
    case FileKind.audio:
      return AudioViewer(room: client, path: path);
    case FileKind.parquet:
      return ParquetViewer(client: client, path: path);
    case FileKind.office:
      return Center(child: Text("No preview available"));
    case FileKind.unknown:
      return null;
  }
}
