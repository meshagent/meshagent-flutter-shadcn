import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:path/path.dart';

import "file/image.dart";
import "file/video.dart";
import "file/audio.dart";
import "file/pdf.dart";
import "file/code.dart";
import "file/parquet.dart";

Widget? fileViewer(RoomClient client, String path) {
  return switch (extension(path).toLowerCase()) {
    ".jpg" => ImageViewer(client: client, path: path),
    ".jpeg" => ImageViewer(client: client, path: path),
    ".webp" => ImageViewer(client: client, path: path),
    ".png" => ImageViewer(client: client, path: path),
    ".svg" => ImageViewer(client: client, path: path),
    ".mp4" => VideoViewer(client: client, path: path),
    ".wav" => AudioViewer(client: client, path: path),
    ".pdf" => PdfViewer(client: client, path: path),
    ".txt" => CodeViewer(client: client, path: path),
    ".json" => CodeViewer(client: client, path: path),
    ".parquet" => ParquetViewer(client: client, path: path),
    _ => null,
  };
}
