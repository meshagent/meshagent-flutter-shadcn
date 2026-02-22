import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'folder_drop_types.dart';

Future<FolderDropPayload?> resolveFolderDrop(Uri uri) async {
  return null;
}

Future<FolderDropPayload?> resolveFolderDropFromEntry(dynamic entry) async {
  final fsEntry = entry as web.FileSystemEntry;
  if (fsEntry.isFile) {
    return null;
  }

  final dirEntry = fsEntry as web.FileSystemDirectoryEntry;
  final folderName = fsEntry.name;
  final files = <FolderDropFile>[];

  await _readDirectory(dirEntry, files, '');

  if (files.isEmpty) {
    return null;
  }

  return FolderDropPayload(folderName: folderName, files: files);
}

Future<void> _readDirectory(web.FileSystemDirectoryEntry dir, List<FolderDropFile> files, String basePath) async {
  final reader = dir.createReader();
  final entries = await _readAllEntries(reader);

  for (final entry in entries) {
    final path = basePath.isEmpty ? entry.name : '$basePath/${entry.name}';

    if (entry.isFile) {
      final fileEntry = entry as web.FileSystemFileEntry;
      final file = await _readFileEntry(fileEntry);
      if (file != null) {
        files.add(FolderDropFile(relativePath: path, dataStream: file.stream, fileSize: file.size));
      }
    } else if (entry.isDirectory) {
      final subDir = entry as web.FileSystemDirectoryEntry;
      await _readDirectory(subDir, files, path);
    }
  }
}

Future<List<web.FileSystemEntry>> _readAllEntries(web.FileSystemDirectoryReader reader) async {
  final allEntries = <web.FileSystemEntry>[];

  while (true) {
    final completer = Completer<List<web.FileSystemEntry>>();
    void success(JSArray<web.FileSystemEntry> entries) {
      completer.complete(entries.toDart.cast<web.FileSystemEntry>());
    }

    void error(web.DOMException err) {
      completer.completeError(err);
    }

    reader.readEntries(success.toJS, error.toJS);
    final entries = await completer.future;

    if (entries.isEmpty) {
      break;
    }
    allEntries.addAll(entries);
  }

  return allEntries;
}

Future<_WebFile?> _readFileEntry(web.FileSystemFileEntry fileEntry) async {
  final completer = Completer<web.File>();

  void success(web.File file) {
    completer.complete(file);
  }

  void error(web.DOMException err) {
    completer.completeError(err);
  }

  fileEntry.file(success.toJS, error.toJS);

  try {
    final file = await completer.future;
    return _WebFile(file);
  } catch (_) {
    return null;
  }
}

class _WebFile {
  final web.File _file;

  _WebFile(this._file);

  int get size => _file.size;

  Stream<Uint8List> get stream async* {
    final arrayBuffer = await _file.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();
    yield bytes;
  }
}
