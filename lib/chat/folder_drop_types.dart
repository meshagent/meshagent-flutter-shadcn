import 'dart:typed_data';

class FolderDropFile {
  const FolderDropFile({required this.relativePath, required this.dataStream, required this.fileSize});

  final String relativePath;
  final Stream<Uint8List> dataStream;
  final int? fileSize;
}

class FolderDropPayload {
  const FolderDropPayload({required this.folderName, required this.files});

  final String folderName;
  final List<FolderDropFile> files;
}
