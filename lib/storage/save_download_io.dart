import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'save_download_memory.dart';

Future<void> saveDownload(String name, Stream<List<int>> bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await saveDownloadInMemory(name, bytes);
    return;
  }
  final path = await FilePicker.saveFile(fileName: name);
  if (path == null) return;
  await saveDownloadToFile(File(path), bytes);
}

Future<void> saveDownloadToFile(File destination, Stream<List<int>> bytes) async {
  final staging = await destination.parent.createTemp('.meshagent-download-');
  final file = File('${staging.path}/download');
  final sink = await file.open(mode: FileMode.write);
  var closed = false;
  try {
    await for (final chunk in bytes) {
      await sink.writeFrom(chunk);
    }
    await sink.flush();
    await sink.close();
    closed = true;
    await file.rename(destination.path);
  } finally {
    try {
      if (!closed) await sink.close();
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
