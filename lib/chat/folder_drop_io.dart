import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as pathlib;

import 'folder_drop_types.dart';

Future<FolderDropPayload?> resolveFolderDrop(Uri uri) async {
  if (uri.scheme != 'file') return null;

  final path = uri.toFilePath();
  final dir = Directory(path);

  if (!await dir.exists()) return null;

  final folderName = pathlib.basename(path);
  final files = <FolderDropFile>[];

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final relativePath = pathlib.posix.joinAll(pathlib.split(pathlib.relative(entity.path, from: path)));
    final dataStream = entity.openRead().map(Uint8List.fromList);
    final size = await entity.length();

    files.add(FolderDropFile(relativePath: relativePath, dataStream: dataStream, fileSize: size));
  }

  return FolderDropPayload(folderName: folderName, files: files);
}

Future<FolderDropPayload?> resolveFolderDropFromEntry(dynamic entry) async {
  return null;
}
