import 'package:flutter/foundation.dart';

class PendingStorageDeleteScope {
  const PendingStorageDeleteScope({required this.projectId, required this.roomName});

  final String? projectId;
  final String? roomName;

  String get key => '${projectId?.trim() ?? ''}:${roomName?.trim() ?? ''}';
}

class PendingStorageDeleteHandle {
  PendingStorageDeleteHandle._(this._scopeKey, this._entryKey);

  final String _scopeKey;
  final String _entryKey;
  bool _completed = false;

  void complete() {
    if (_completed) {
      return;
    }

    _completed = true;
    PendingStorageDeletes._remove(_scopeKey, _entryKey);
  }
}

class PendingStorageDeleteEntry {
  const PendingStorageDeleteEntry({required this.path, required this.isFolder, required this.startedAt, required this.sequence});

  final String path;
  final bool isFolder;
  final DateTime startedAt;
  final int sequence;
}

class _PendingStorageDeleteEntry {
  _PendingStorageDeleteEntry({required this.path, required this.isFolder, required this.startedAt, required this.sequence});

  final String path;
  final bool isFolder;
  final DateTime startedAt;
  final int sequence;
  int count = 1;

  String get key => PendingStorageDeletes._entryKey(path: path, isFolder: isFolder);

  bool contains({required String candidatePath, required bool candidateIsFolder}) {
    if (path == '') {
      return true;
    }

    if (path == candidatePath && isFolder == candidateIsFolder) {
      return true;
    }

    if (!isFolder) {
      return false;
    }

    return candidatePath.startsWith('$path/');
  }
}

class _PendingStorageDeleteBucket {
  final entries = <String, _PendingStorageDeleteEntry>{};
  final revision = ValueNotifier<int>(0);

  void notify() {
    revision.value++;
  }
}

class PendingStorageDeletes {
  static final _buckets = <String, _PendingStorageDeleteBucket>{};
  static int _sequence = 0;

  static ValueListenable<int> listenableFor(PendingStorageDeleteScope scope) {
    return _bucket(scope.key).revision;
  }

  static String normalizePath(String path) {
    return path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static PendingStorageDeleteHandle begin({required PendingStorageDeleteScope scope, required String path, required bool isFolder}) {
    final normalizedPath = normalizePath(path);
    final entryKey = _entryKey(path: normalizedPath, isFolder: isFolder);
    final bucket = _bucket(scope.key);
    final existing = bucket.entries[entryKey];
    if (existing == null) {
      bucket.entries[entryKey] = _PendingStorageDeleteEntry(
        path: normalizedPath,
        isFolder: isFolder,
        startedAt: DateTime.now(),
        sequence: _sequence++,
      );
    } else {
      existing.count++;
    }
    bucket.notify();
    return PendingStorageDeleteHandle._(scope.key, entryKey);
  }

  static bool contains({required PendingStorageDeleteScope scope, required String path, required bool isFolder}) {
    final normalizedPath = normalizePath(path);
    final bucket = _buckets[scope.key];
    if (bucket == null) {
      return false;
    }

    return bucket.entries.values.any((entry) => entry.contains(candidatePath: normalizedPath, candidateIsFolder: isFolder));
  }

  static List<PendingStorageDeleteEntry> entriesFor(PendingStorageDeleteScope scope) {
    final bucket = _buckets[scope.key];
    if (bucket == null) {
      return const <PendingStorageDeleteEntry>[];
    }

    return [
      for (final entry in bucket.entries.values)
        PendingStorageDeleteEntry(path: entry.path, isFolder: entry.isFolder, startedAt: entry.startedAt, sequence: entry.sequence),
    ];
  }

  static _PendingStorageDeleteBucket _bucket(String scopeKey) {
    return _buckets.putIfAbsent(scopeKey, _PendingStorageDeleteBucket.new);
  }

  static void _remove(String scopeKey, String entryKey) {
    final bucket = _buckets[scopeKey];
    if (bucket == null) {
      return;
    }

    final entry = bucket.entries[entryKey];
    if (entry == null) {
      return;
    }

    entry.count--;
    if (entry.count <= 0) {
      bucket.entries.remove(entryKey);
    }
    bucket.notify();
  }

  static String _entryKey({required String path, required bool isFolder}) {
    return '${isFolder ? 'folder' : 'file'}:${normalizePath(path)}';
  }
}
