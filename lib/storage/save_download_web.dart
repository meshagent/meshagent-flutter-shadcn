import 'dart:js_interop';
import 'dart:typed_data';
import 'save_download_memory.dart';

@JS('window.showSaveFilePicker')
external JSAny? get _savePicker;
@JS('window.showSaveFilePicker')
external JSPromise<_FileHandle> _pickFile(_PickerOptions options);
extension type _PickerOptions._(JSObject _) implements JSObject {
  external factory _PickerOptions({String suggestedName});
}
extension type _FileHandle._(JSObject _) implements JSObject {
  external JSPromise<_WritableFile> createWritable();
}
extension type _WritableFile._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array data);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> abort();
}

Future<void> saveDownload(String name, Stream<List<int>> bytes) async {
  if (_savePicker == null) {
    await saveDownloadInMemory(name, bytes);
    return;
  }
  // Called directly from the user gesture, before starting the network stream.
  final handle = await _pickFile(_PickerOptions(suggestedName: name)).toDart;
  final writer = await handle.createWritable().toDart;
  try {
    await for (final chunk in bytes) {
      await writer.write(Uint8List.fromList(chunk).toJS).toDart;
    }
    await writer.close().toDart;
  } catch (_) {
    await writer.abort().toDart;
    rethrow;
  }
}
