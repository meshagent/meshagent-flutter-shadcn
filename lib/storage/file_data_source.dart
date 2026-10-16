import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';

/// File widgets depend on operations, independently of room sessions or REST.
abstract interface class FileDataSource {
  bool get supportsAbortTrigger;
  Future<FilesPage> listPage(String path, {String? continuationToken});
  Future<FilePermissions> permissions(String path);
  Stream<List<int>> download(String path, {Future<void>? abortTrigger});
  Future<void> upload(
    String path,
    Stream<List<int>> data, {
    int? size,
    String? contentType,
    bool overwrite = false,
    Future<void>? abortTrigger,
  });
  Future<void> mkdir(String path);
  Future<void> delete(String path, {bool recursive = false});
  Future<void> move(String source, String destination, {bool overwrite = false});
  Stream<void> get changes;
}

class RestFileDataSource implements FileDataSource {
  RestFileDataSource(this.client);
  final TargetFilesClient client;

  @override
  bool get supportsAbortTrigger => true;

  @override
  Future<FilesPage> listPage(String path, {String? continuationToken}) => client.listPage(path: path, continuationToken: continuationToken);
  @override
  Future<FilePermissions> permissions(String path) => client.permissions(path);
  @override
  Stream<List<int>> download(String path, {Future<void>? abortTrigger}) => client.downloadStream(path, abortTrigger: abortTrigger);
  @override
  Future<void> upload(
    String path,
    Stream<List<int>> data, {
    int? size,
    String? contentType,
    bool overwrite = false,
    Future<void>? abortTrigger,
  }) => client.uploadStream(
    path,
    data,
    contentLength: size,
    contentType: contentType ?? 'application/octet-stream',
    overwrite: overwrite,
    abortTrigger: abortTrigger,
  );
  @override
  Future<void> mkdir(String path) => client.mkdir(path);
  @override
  Future<void> delete(String path, {bool recursive = false}) => client.delete(path, recursive: recursive);
  @override
  Future<void> move(String source, String destination, {bool overwrite = false}) =>
      client.move(client.location(source), destination, overwrite: overwrite);
  @override
  Stream<void> get changes => const Stream.empty();
}

/// Keeps the existing room storage transport available to Powerboards.
/// [permissionsForPath] must use the participant's effective storage grant.
class WebSocketFileDataSource implements FileDataSource {
  WebSocketFileDataSource(this.room, {required this.permissionsForPath, required this.createDirectory});
  final RoomClient room;

  @override
  bool get supportsAbortTrigger => false;
  final Future<FilePermissions> Function(String path) permissionsForPath;
  // The room adapter retains the application's existing folder marker policy.
  final Future<void> Function(String path) createDirectory;

  @override
  Future<FilesPage> listPage(String path, {String? continuationToken}) async {
    if (continuationToken != null) throw ArgumentError('Room storage does not use continuation tokens');
    return FilesPage(entries: await room.storage.list(path));
  }

  @override
  Future<FilePermissions> permissions(String path) => permissionsForPath(path);
  @override
  Stream<List<int>> download(String path, {Future<void>? abortTrigger}) async* {
    // Cancelling this subscription closes the room tool output stream.
    if (abortTrigger != null) throw UnsupportedError('Room downloads use stream subscription cancellation');
    final stream = await room.storage.downloadStream(path);
    await for (final chunk in stream) {
      yield chunk.data;
    }
  }

  @override
  Future<void> upload(
    String path,
    Stream<List<int>> data, {
    int? size,
    String? contentType,
    bool overwrite = false,
    Future<void>? abortTrigger,
  }) {
    if (abortTrigger != null) throw UnsupportedError('Explicit abort triggers require the REST transport');
    return room.storage.uploadStream(
      path,
      data.map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
      size: size,
      mimeType: contentType,
      overwrite: overwrite,
    );
  }

  @override
  Future<void> mkdir(String path) => createDirectory(path);
  @override
  Future<void> delete(String path, {bool recursive = false}) => room.storage.delete(path, recursive: recursive);
  @override
  Future<void> move(String source, String destination, {bool overwrite = false}) =>
      room.storage.move(source, destination, overwrite: overwrite);
  @override
  Stream<void> get changes =>
      room.events.where((event) => event is FileUpdatedEvent || event is FileDeletedEvent || event is FileMovedEvent).map((_) {});
}
