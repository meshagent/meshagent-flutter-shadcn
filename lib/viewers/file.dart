import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import "package:meshagent_flutter_shadcn/file_preview/file_preview.dart";
import 'package:path/path.dart';

import "file/image.dart";
import "file/video.dart";
import "file/audio.dart";
import "file/pdf.dart";
import "file/parquet.dart";

Widget? fileViewer(RoomClient client, String path) {
  final ext = basename(path).split(".").last.toLowerCase();
  if (customViewers[ext] != null) {
    return FilePreview(room: client, path: path);
  }
  return switch (extension(path).toLowerCase()) {
    ".jpg" => ImageViewer(room: client, path: path),
    ".jpeg" => ImageViewer(room: client, path: path),
    ".webp" => ImageViewer(room: client, path: path),
    ".png" => ImageViewer(room: client, path: path),
    ".svg" => ImageViewer(room: client, path: path),
    ".mp4" => VideoViewer(room: client, path: path),
    ".wav" => AudioViewer(room: client, path: path),
    ".pdf" => PdfViewer(room: client, path: path),
    ".parquet" => ParquetViewer(client: client, path: path),
    ".docx" => Center(child: Text("No preview available")),
    ".pptx" => Center(child: Text("No preview available")),
    ".xlsx" => Center(child: Text("No preview available")),
    _ => null,
  };
}
