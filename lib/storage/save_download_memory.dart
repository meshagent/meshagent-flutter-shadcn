import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> saveDownloadInMemory(String name, Stream<List<int>> bytes) async {
  final data = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    if (data.length + chunk.length > 128 * 1024 * 1024) {
      throw StateError('This platform supports downloads up to 128 MiB. Use the MeshAgent CLI for larger files.');
    }
    data.add(chunk);
  }
  await FilePicker.saveFile(fileName: name, bytes: data.takeBytes());
}
