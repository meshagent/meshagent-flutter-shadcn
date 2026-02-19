import 'folder_drop_stub.dart' if (dart.library.io) 'folder_drop_io.dart' if (dart.library.js_interop) 'folder_drop_web.dart' as impl;
import 'folder_drop_types.dart';

export 'folder_drop_types.dart';

Future<FolderDropPayload?> resolveFolderDrop(Uri uri) {
  return impl.resolveFolderDrop(uri);
}

Future<FolderDropPayload?> resolveFolderDropFromEntry(dynamic entry) {
  return impl.resolveFolderDropFromEntry(entry);
}
