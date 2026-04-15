import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/storage/transcript_file_name.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

enum FileBrowserSelectionMode { files, folders }

class FileBrowserPathViewModel {
  const FileBrowserPathViewModel({
    required this.path,
    required this.segments,
    required this.currentSelectionCount,
    required this.rootLabel,
    required this.onRootPressed,
    required this.onSegmentPressed,
  });

  final String path;
  final List<String> segments;
  final int currentSelectionCount;
  final String rootLabel;
  final VoidCallback onRootPressed;
  final void Function(int index) onSegmentPressed;
}

class FileBrowserRowViewModel {
  const FileBrowserRowViewModel({
    required this.entry,
    required this.fullPath,
    required this.displayName,
    required this.selected,
    required this.canActivate,
    required this.onPressed,
    required this.canToggleSelection,
    this.onToggleSelection,
  });

  final StorageEntry entry;
  final String fullPath;
  final String displayName;
  final bool selected;
  final bool canActivate;
  final VoidCallback onPressed;
  final bool canToggleSelection;
  final VoidCallback? onToggleSelection;
}

typedef FileBrowserHeaderBuilder = Widget Function(BuildContext context, FileBrowserPathViewModel model);
typedef FileBrowserRowBuilder = Widget Function(BuildContext context, FileBrowserRowViewModel model);
typedef FileBrowserSeparatorBuilder = Widget Function(BuildContext context, int index);
typedef FileBrowserEmptyBuilder = Widget Function(BuildContext context);

const String _defaultUntitledThreadName = 'New Chat';
const String _threadIndexFileName = 'index.threadl';
final RegExp _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);
const int _maxThreadDisplayNameLength = 64;

bool _isThreadFileName(String fileName) => fileName.toLowerCase().endsWith('.thread');

bool _isThreadPath(String path) => _isThreadFileName(p.posix.basename(path));

bool _shouldReadThreadDocumentForDisplayName(String path) {
  return p.posix.basename(path).toLowerCase() != 'main.thread';
}

String _defaultThreadDisplayNameFromPath(String path) {
  final basename = p.posix.basename(path);
  final rawName = basename.endsWith('.thread') ? basename.substring(0, basename.length - '.thread'.length) : basename;
  final trimmed = rawName.trim();
  if (trimmed.isEmpty || _uuidPattern.hasMatch(trimmed)) {
    return _defaultUntitledThreadName;
  }

  final normalized = trimmed.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return _defaultUntitledThreadName;
  }

  return normalized
      .split(' ')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => segment.length == 1 ? segment.toUpperCase() : '${segment[0].toUpperCase()}${segment.substring(1)}')
      .join(' ');
}

String _threadFileDisplayNameFromPath(String path, {String? threadDisplayName}) {
  final resolvedName = (threadDisplayName?.trim().isNotEmpty ?? false)
      ? threadDisplayName!.trim()
      : _defaultThreadDisplayNameFromPath(path);
  return resolvedName.toLowerCase().endsWith('.thread') ? resolvedName : '$resolvedName.thread';
}

String _displayFileName(String fileName) {
  return formatTranscriptFileNameForDisplay(fileName);
}

bool _shouldBackfillThreadDisplayName(String? displayName) {
  final trimmed = displayName?.trim();
  return trimmed == null || trimmed.isEmpty || trimmed == _defaultUntitledThreadName;
}

String? _deriveThreadDisplayNameFromDocument(MeshDocument document) {
  final messagesElement = document.root.getChildren().whereType<MeshElement>().firstWhereOrNull((child) => child.tagName == 'messages');
  if (messagesElement == null) {
    return null;
  }

  for (final child in messagesElement.getChildren().whereType<MeshElement>()) {
    if (child.tagName != 'message') {
      continue;
    }

    final text = child.getAttribute('text');
    if (text is! String) {
      continue;
    }

    final firstLine = text.split(RegExp(r'\r?\n')).map((line) => line.trim()).firstWhereOrNull((line) => line.isNotEmpty);
    if (firstLine == null) {
      continue;
    }

    final normalized = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      continue;
    }

    return normalized.length <= _maxThreadDisplayNameLength
        ? normalized
        : '${normalized.substring(0, _maxThreadDisplayNameLength - 1).trimRight()}…';
  }

  return null;
}

class FileBrowser extends StatefulWidget {
  const FileBrowser({
    super.key,
    required this.room,
    this.initialPath = "",
    this.multiple = false,
    this.onSelectionChanged,
    this.selectionMode = FileBrowserSelectionMode.files,
    this.rootLabel = "Files",
    this.headerBuilder,
    this.rowBuilder,
    this.separatorBuilder,
    this.emptyBuilder,
  });

  final RoomClient room;
  final String initialPath;
  final bool multiple;
  final void Function(List<String> selection)? onSelectionChanged;
  final FileBrowserSelectionMode selectionMode;
  final String rootLabel;
  final FileBrowserHeaderBuilder? headerBuilder;
  final FileBrowserRowBuilder? rowBuilder;
  final FileBrowserSeparatorBuilder? separatorBuilder;
  final FileBrowserEmptyBuilder? emptyBuilder;

  @override
  State createState() => _FileBrowser();
}

class _FileBrowser extends State<FileBrowser> {
  String path = "";

  List<StorageEntry>? files;
  final Set<String> selection = {};
  MeshDocument? _threadIndexDocument;
  String? _threadIndexPath;
  Map<String, String> _threadDisplayNamesByPath = const <String, String>{};
  final Set<String> _threadTitleResolutionsInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    path = widget.initialPath;

    load();
  }

  void load() async {
    files = (await widget.room.storage.list(path)).where((x) => !x.name.startsWith(".")).toList()..sort(compare);

    if (mounted) {
      setState(() {});
    }

    unawaited(_rebindThreadIndexDocument());
  }

  @override
  void dispose() {
    unawaited(_closeThreadIndexDocument(refreshUi: false));
    super.dispose();
  }

  String join(String path1, String path2) {
    if (path1 == "") {
      return path2;
    } else {
      return "$path1/$path2";
    }
  }

  int compare(StorageEntry a, StorageEntry b) {
    // folders before files
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  String _displayNameForPath(String fullPath) {
    final fileName = fullPath.split('/').where((segment) => segment.isNotEmpty).lastOrNull ?? fullPath;
    if (_isThreadPath(fullPath)) {
      return _threadFileDisplayNameFromPath(fullPath, threadDisplayName: _threadDisplayNamesByPath[fullPath]);
    }
    return _displayFileName(fileName);
  }

  String _displayNameForEntry(StorageEntry entry) {
    if (entry.isFolder) {
      return entry.name;
    }
    return _displayNameForPath(join(path, entry.name));
  }

  String? _threadIndexPathForFolder(String folder) {
    final trimmed = folder.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return join(trimmed, _threadIndexFileName);
  }

  Future<void> _closeThreadIndexDocument({bool refreshUi = true}) async {
    final document = _threadIndexDocument;
    final threadIndexPath = _threadIndexPath;
    if (document != null) {
      document.removeListener(_onThreadIndexChanged);
    }
    _threadIndexDocument = null;
    _threadIndexPath = null;
    _threadTitleResolutionsInFlight.clear();

    final shouldRefresh = refreshUi && mounted;
    if (shouldRefresh || _threadDisplayNamesByPath.isNotEmpty) {
      if (shouldRefresh) {
        setState(() {
          _threadDisplayNamesByPath = const <String, String>{};
        });
      } else {
        _threadDisplayNamesByPath = const <String, String>{};
      }
    }

    if (threadIndexPath != null) {
      try {
        await widget.room.sync.close(threadIndexPath);
      } catch (_) {}
    }
  }

  void _onThreadIndexChanged() {
    _refreshThreadDisplayNames();
    unawaited(_backfillThreadDisplayNames());
  }

  Future<void> _rebindThreadIndexDocument() async {
    final nextThreadIndexPath = _threadIndexPathForFolder(path);
    if (_threadIndexPath == nextThreadIndexPath && _threadIndexDocument != null) {
      _refreshThreadDisplayNames();
      unawaited(_backfillThreadDisplayNames());
      return;
    }

    await _closeThreadIndexDocument();
    if (!mounted) {
      return;
    }
    if (_threadIndexPathForFolder(path) != nextThreadIndexPath || nextThreadIndexPath == null) {
      return;
    }

    try {
      final exists = await widget.room.storage.exists(nextThreadIndexPath);
      if (!mounted || _threadIndexPathForFolder(path) != nextThreadIndexPath || !exists) {
        return;
      }

      final document = await widget.room.sync.open(nextThreadIndexPath);
      if (!mounted || _threadIndexPathForFolder(path) != nextThreadIndexPath) {
        try {
          await widget.room.sync.close(nextThreadIndexPath);
        } catch (_) {}
        return;
      }

      document.addListener(_onThreadIndexChanged);
      _threadIndexDocument = document;
      _threadIndexPath = nextThreadIndexPath;
      _refreshThreadDisplayNames();
      unawaited(_backfillThreadDisplayNames());
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _threadDisplayNamesByPath = const <String, String>{};
      });
    }
  }

  void _refreshThreadDisplayNames() {
    final document = _threadIndexDocument;
    final next = <String, String>{};
    if (document != null) {
      for (final node in document.root.getChildren().whereType<MeshElement>()) {
        if (node.tagName != 'thread') {
          continue;
        }

        final rawPath = node.getAttribute('path');
        if (rawPath is! String) {
          continue;
        }
        final threadPath = rawPath.trim();
        if (threadPath.isEmpty) {
          continue;
        }

        final rawName = node.getAttribute('name');
        if (rawName is! String) {
          continue;
        }
        final displayName = rawName.trim();
        if (displayName.isEmpty) {
          continue;
        }

        next[threadPath] = displayName;
      }
    }

    if (!mapEquals(_threadDisplayNamesByPath, next)) {
      if (mounted) {
        setState(() {
          _threadDisplayNamesByPath = next;
        });
      } else {
        _threadDisplayNamesByPath = next;
      }
    }
  }

  Future<void> _backfillThreadDisplayNames() async {
    final currentFiles = files;
    if (!mounted || currentFiles == null) {
      return;
    }

    final currentFolder = path;
    for (final entry in currentFiles) {
      if (entry.isFolder || !_isThreadFileName(entry.name)) {
        continue;
      }

      final fullPath = join(currentFolder, entry.name);
      if (!_shouldReadThreadDocumentForDisplayName(fullPath)) {
        continue;
      }

      final currentDisplayName = _threadDisplayNamesByPath[fullPath];
      if (!_shouldBackfillThreadDisplayName(currentDisplayName) || _threadTitleResolutionsInFlight.contains(fullPath)) {
        continue;
      }

      _threadTitleResolutionsInFlight.add(fullPath);
      unawaited(_resolveAndStoreThreadDisplayName(path: fullPath));
    }
  }

  MeshElement? _threadNodeForPath(String fullPath) {
    final document = _threadIndexDocument;
    if (document == null) {
      return null;
    }

    return document.root.getChildren().whereType<MeshElement>().firstWhereOrNull((node) {
      return node.tagName == 'thread' && node.getAttribute('path') == fullPath;
    });
  }

  Future<void> _resolveAndStoreThreadDisplayName({required String path}) async {
    try {
      final document = await widget.room.sync.open(path);
      try {
        final resolvedName = _deriveThreadDisplayNameFromDocument(document);
        if (!mounted || resolvedName == null || resolvedName.trim().isEmpty) {
          return;
        }

        final latestNode = _threadNodeForPath(path);
        if (latestNode != null && _shouldBackfillThreadDisplayName(latestNode.getAttribute('name') as String?)) {
          latestNode.setAttribute('name', resolvedName);
        }

        setState(() {
          _threadDisplayNamesByPath = <String, String>{..._threadDisplayNamesByPath, path: resolvedName};
        });
      } finally {
        try {
          await widget.room.sync.close(path);
        } catch (_) {}
      }
    } catch (_) {
      return;
    } finally {
      _threadTitleResolutionsInFlight.remove(path);
    }
  }

  void _openRoot() {
    setState(() {
      if (widget.selectionMode == FileBrowserSelectionMode.folders) {
        selection
          ..clear()
          ..add("");
      }
      path = "";
      load();
    });
  }

  void _openSegment(List<String> fileItems, int index) {
    String segmentPath = "";

    for (int i = 0; i <= index; i++) {
      if (segmentPath.isNotEmpty) {
        segmentPath += "/";
      }

      segmentPath += fileItems[i];
    }

    if (widget.selectionMode == FileBrowserSelectionMode.folders) {
      setState(() {
        selection
          ..clear()
          ..add(segmentPath);
        path = segmentPath;
        load();
      });
    } else {
      setState(() {
        path = segmentPath;
        load();
      });
    }
  }

  void _onEntryPressed(StorageEntry file) {
    if (file.isFolder) {
      if (widget.selectionMode == FileBrowserSelectionMode.folders) {
        // note: only single folder selection is supported
        final fullPath = join(path, file.name);
        setState(() {
          if (selection.contains(fullPath)) {
            selection.clear();
          } else {
            selection
              ..clear()
              ..add(fullPath);
          }
          path = fullPath;
          load();
        });
      } else {
        setState(() {
          path = join(path, file.name);
          selection.clear();
          load();
        });
      }
    } else {
      setState(() {
        final fullPath = join(path, file.name);
        if (widget.multiple) {
          if (!selection.contains(fullPath)) {
            selection.add(fullPath);
          } else {
            selection.remove(fullPath);
          }
        } else {
          if (selection.contains(fullPath)) {
            selection.clear();
          } else {
            selection.add(fullPath);
          }
        }
      });
    }

    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(selection.toList());
    }
  }

  void _toggleFileSelection(StorageEntry file) {
    final fullPath = join(path, file.name);

    setState(() {
      if (widget.multiple) {
        if (selection.contains(fullPath)) {
          selection.remove(fullPath);
        } else {
          selection.add(fullPath);
        }
      } else {
        if (selection.contains(fullPath)) {
          selection.clear();
        } else {
          selection
            ..clear()
            ..add(fullPath);
        }
      }
    });

    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(selection.toList());
    }
  }

  Widget _buildDefaultHeader(BuildContext context, List<String> fileItems, ShadTextTheme tt, ShadColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Path: ",
            style: tt.small.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
          ),
          Expanded(
            child: ShadBreadcrumb(
              separator: Icon(LucideIcons.chevronRight, size: 16),
              children: [
                ShadBreadcrumbLink(onPressed: _openRoot, child: const Text('Home')),
                if (path != "")
                  for (final segment in fileItems.indexed)
                    ShadBreadcrumbLink(onPressed: () => _openSegment(fileItems, segment.$1), child: Text(segment.$2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultRow(BuildContext context, StorageEntry file, ShadThemeData theme) {
    final fullPath = join(path, file.name);
    final selected = selection.contains(fullPath);
    final currentSelectionCount = files!.where((entry) => selection.contains(join(path, entry.name))).length;
    final canActivate = widget.selectionMode == FileBrowserSelectionMode.folders || !file.isFolder || currentSelectionCount == 0;

    return ShadButton.ghost(
      backgroundColor: selected ? theme.colorScheme.selection : null,
      decoration: selected ? ShadDecoration(border: ShadBorder.all(radius: const BorderRadius.all(Radius.zero))) : null,
      mainAxisAlignment: MainAxisAlignment.start,
      onPressed: canActivate ? () => _onEntryPressed(file) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Icon(
            selected ? LucideIcons.check : (file.isFolder ? LucideIcons.folder : LucideIcons.file),
            color: (file.isFolder ? const Color.fromARGB(0xff, 0xe0, 0xa0, 0x30) : null),
          ),
          Text(_displayNameForEntry(file), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;

    if (files == null) {
      return Center(child: CircularProgressIndicator());
    }

    final filteredFiles = widget.selectionMode == FileBrowserSelectionMode.folders ? files!.where((x) => x.isFolder) : files!;
    final currentSelectionCount = filteredFiles.where((file) => selection.contains(join(path, file.name))).length;

    final fileItems = path.split("/");
    final header =
        widget.headerBuilder?.call(
          context,
          FileBrowserPathViewModel(
            path: path,
            segments: fileItems.where((segment) => segment.isNotEmpty).toList(growable: false),
            currentSelectionCount: currentSelectionCount,
            rootLabel: widget.rootLabel,
            onRootPressed: _openRoot,
            onSegmentPressed: (index) => _openSegment(fileItems, index),
          ),
        ) ??
        _buildDefaultHeader(context, fileItems, tt, cs);

    return Column(
      spacing: 1,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: filteredFiles.isEmpty
              ? (widget.emptyBuilder?.call(context) ?? const SizedBox.shrink())
              : ListView.separated(
                  itemCount: filteredFiles.length,
                  separatorBuilder: widget.separatorBuilder ?? (_, _) => const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    final file = filteredFiles.elementAt(index);
                    final fullPath = join(path, file.name);

                    return widget.rowBuilder?.call(
                          context,
                          FileBrowserRowViewModel(
                            entry: file,
                            fullPath: fullPath,
                            displayName: _displayNameForEntry(file),
                            selected: selection.contains(fullPath),
                            canActivate:
                                widget.selectionMode == FileBrowserSelectionMode.folders || !file.isFolder || currentSelectionCount == 0,
                            onPressed: () => _onEntryPressed(file),
                            canToggleSelection: widget.selectionMode == FileBrowserSelectionMode.folders || !file.isFolder,
                            onToggleSelection: widget.selectionMode == FileBrowserSelectionMode.folders
                                ? () => _onEntryPressed(file)
                                : (file.isFolder ? null : () => _toggleFileSelection(file)),
                          ),
                        ) ??
                        _buildDefaultRow(context, file, theme);
                  },
                ),
        ),
      ],
    );
  }
}
