import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'file_data_source.dart';
import 'save_download.dart';
import '../chat/chat.dart' show FileDropArea;
import 'powerboards/components/files/pb_files_data.dart';
import 'powerboards/components/files/pb_files_drop_target.dart';
import 'powerboards/components/files/pb_files_header.dart';
import 'powerboards/components/files/pb_files_layout_values.dart';
import 'powerboards/components/files/pb_files_side_pane.dart';
import 'powerboards/components/files/pb_files_table.dart';
import 'powerboards/components/layouts/pb_room_panel.dart';
import 'powerboards/models/pb_attachment_file_metadata.dart';
import 'powerboards/theme/pb_colors.dart';

typedef FileManagerDownload = Future<void> Function(String name, Stream<List<int>> bytes);

/// Powerboards' file widgets with an interchangeable storage transport.
class FileManager extends StatefulWidget {
  const FileManager({super.key, required this.source, this.onDownload});

  final FileDataSource source;
  final FileManagerDownload? onDownload;

  @override
  State<FileManager> createState() => _FileManagerState();
}

class _FileManagerState extends State<FileManager> {
  static const _padding = PbFilesPanelPadding(left: 28, right: 28);
  final _filter = TextEditingController();
  final _selected = <String>{};
  final _seenTokens = <String>{};
  final _rowPermissions = <String, FilePermissions>{};
  final _previewAbort = <Completer<void>>[];
  final _uploadAbort = <Completer<void>>{};
  final _downloadAbort = <Completer<void>>{};
  String? _imagePath;
  Future<Uint8List>? _imageBytes;
  StreamSubscription<void>? _changes;
  List<PbFilesItemData> _items = [];
  FilePermissions? _permissions;
  PbFilesItemData? _preview;
  PbFilesSortKey _sort = PbFilesSortKey.name;
  bool _descending = false;
  bool _fullscreen = false;
  bool _loading = true;
  bool _busy = false;
  int _generation = 0;
  String _path = '';
  String? _next;
  String? _message;
  Object? _error;
  int _uploaded = 0;
  int? _uploadSize;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_load());
  }

  void _subscribe() => _changes = widget.source.changes.listen(
    (_) => unawaited(_load()),
    onError: (Object error) {
      if (mounted) setState(() => _error = error);
    },
  );

  @override
  void didUpdateWidget(covariant FileManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      unawaited(_changes?.cancel());
      _cancelPreviews();
      _cancelUploads();
      _cancelDownloads();
      _path = '';
      _preview = null;
      _subscribe();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_changes?.cancel());
    _cancelPreviews();
    _cancelUploads();
    _cancelDownloads();
    _filter.dispose();
    super.dispose();
  }

  void _cancelPreviews() {
    for (final abort in _previewAbort) {
      if (!abort.isCompleted) abort.complete();
    }
    _previewAbort.clear();
    _imagePath = null;
    _imageBytes = null;
  }

  void _cancelUploads() {
    for (final abort in _uploadAbort) {
      if (!abort.isCompleted) abort.complete();
    }
    _uploadAbort.clear();
  }

  void _cancelDownloads() {
    for (final abort in _downloadAbort) {
      if (!abort.isCompleted) abort.complete();
    }
    _downloadAbort.clear();
  }

  Future<void> _put(String path, Stream<List<int>> bytes, {int? size, String? contentType, bool overwrite = false}) async {
    final source = widget.source;
    final abort = source.supportsAbortTrigger ? Completer<void>() : null;
    if (abort != null) _uploadAbort.add(abort);
    try {
      await source.upload(path, bytes, size: size, contentType: contentType, overwrite: overwrite, abortTrigger: abort?.future);
    } finally {
      if (abort != null) _uploadAbort.remove(abort);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_next == null || _loading)) return;
    final generation = ++_generation;
    final path = _path;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _items = [];
        _selected.clear();
        _seenTokens.clear();
        _rowPermissions.clear();
        _permissions = null;
        _next = null;
      }
    });
    try {
      final pageFuture = widget.source.listPage(path, continuationToken: more ? _next : null);
      final permissionsFuture = widget.source.permissions(path);
      final results = await Future.wait<Object>([pageFuture, permissionsFuture]);
      final page = results[0] as FilesPage;
      final permissions = results[1] as FilePermissions;
      if (!mounted || generation != _generation) return;
      if (page.continuationToken != null && !_seenTokens.add(page.continuationToken!)) {
        throw StateError('Files server returned a repeated pagination token');
      }
      final entries = page.entries.map((entry) {
        final fullPath = path.isEmpty ? entry.name : '$path/${entry.name}';
        return PbFilesItemData.fromFileName(
          id: fullPath,
          title: entry.name,
          thread: '',
          creator: '',
          creatorInitials: '',
          updatedLabel: entry.updatedAt?.toLocal().toString().split('.').first ?? '',
          updatedSort: entry.updatedAt?.millisecondsSinceEpoch ?? 0,
          parentPath: path,
          path: fullPath,
          folderPath: entry.isFolder ? fullPath : path,
          kind: entry.isFolder ? PbFilesItemKind.folder : PbFilesItemKind.file,
          sizeSort: entry.size ?? 0,
          sizeLabel: entry.isFolder ? '' : _size(entry.size),
        );
      });
      setState(() {
        _items = [..._items, ...entries];
        _permissions = permissions;
        _next = page.continuationToken;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  static String _size(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool _can(FileAction action, {PbFilesItemData? item, bool recursive = false}) {
    final permissions = item == null ? _permissions : _rowPermissions[item.id];
    if (permissions != null && (recursive ? permissions.recursiveActions : permissions.actions).contains(action)) return true;
    return item != null && (_permissions?.recursiveActions.contains(action) ?? false);
  }

  bool get _canCreate => !_busy && (_permissions?.recursiveActions.contains(FileAction.write) ?? false);

  List<PbFilesItemData> get _visible {
    final query = _filter.text.toLowerCase();
    final items = _items.where((item) => item.filterText.toLowerCase().contains(query)).toList();
    items.sort((left, right) {
      if (left.kind != right.kind) return left.kind == PbFilesItemKind.folder ? -1 : 1;
      final comparison = switch (_sort) {
        PbFilesSortKey.name => left.title.toLowerCase().compareTo(right.title.toLowerCase()),
        PbFilesSortKey.size => left.sizeSort.compareTo(right.sizeSort),
        PbFilesSortKey.type => left.type.compareTo(right.type),
        PbFilesSortKey.updated => left.updatedSort.compareTo(right.updatedSort),
        PbFilesSortKey.thread => left.thread.compareTo(right.thread),
        PbFilesSortKey.creator => left.creator.compareTo(right.creator),
      };
      return _descending ? -comparison : comparison;
    });
    return items;
  }

  void _navigate(String path) {
    _cancelPreviews();
    setState(() {
      _path = path;
      _preview = null;
      _filter.clear();
    });
    unawaited(_load());
  }

  Future<void> _activate(PbFilesItemData item) async {
    if (item.kind == PbFilesItemKind.folder) {
      _navigate(item.id);
      return;
    }
    try {
      final permissions = await widget.source.permissions(item.id);
      if (!mounted || !_items.any((value) => value.id == item.id)) return;
      _cancelPreviews();
      setState(() {
        _rowPermissions[item.id] = permissions;
        _preview = item;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    }
  }

  static String _errorText(Object error) => error is MeshagentException ? error.displayMessage : error.toString();

  Future<void> _run(Future<void> Function() operation, {bool refresh = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
      if (mounted && refresh) await _load();
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadSize = null;
        });
      }
    }
  }

  Future<String?> _prompt(String title, {String initial = '', bool component = true}) async {
    var value = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          onChanged: (text) => value = text,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, value), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted || result == null) return null;
    final location = FileLocation(
      target: FilesTarget(projectId: 'validation', kind: FilesTargetKind.room, name: 'validation'),
      path: result,
    );
    if (location.path.isEmpty || component && result.contains('/')) {
      throw ArgumentError('Enter a valid ${component ? 'name' : 'relative path'}');
    }
    return result;
  }

  String _child(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<void> _create({required bool folder}) => _run(() async {
    final name = await _prompt(folder ? 'New folder' : 'New text file');
    if (name == null) return;
    if (folder) {
      await widget.source.mkdir(_child(name));
    } else {
      await _put(_child(name), const Stream.empty(), size: 0, contentType: 'text/plain');
    }
  });

  Future<void> _rename(PbFilesItemData item, {bool move = false}) => _run(() async {
    final name = await _prompt(move ? 'Move to path' : 'Rename', initial: move ? item.id : item.title, component: !move);
    if (name != null) await widget.source.move(item.id, move ? name : _child(name));
  });

  Future<void> _delete(List<PbFilesItemData> items) => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${items.length == 1 ? items.single.title : '${items.length} items'}?'),
        content: const Text('Folders and their contents will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final item in items) {
      await widget.source.delete(item.id, recursive: item.kind == PbFilesItemKind.folder);
    }
    if (mounted && items.any((item) => item.id == _preview?.id)) {
      _cancelPreviews();
      setState(() => _preview = null);
    }
  });

  Future<void> _upload() => _run(() async {
    final selection = await FilePicker.pickFiles(allowMultiple: true, withReadStream: true);
    if (!mounted || selection == null) return;
    for (final file in selection.files) {
      final stream = file.readStream ?? (file.bytes == null ? null : Stream.value(file.bytes!));
      if (stream == null) throw StateError('Unable to read ${file.name}');
      setState(() {
        _uploaded = 0;
        _uploadSize = file.size;
      });
      Stream<List<int>> progress() async* {
        await for (final chunk in stream) {
          yield chunk;
          if (mounted) setState(() => _uploaded += chunk.length);
        }
      }

      await _put(_child(file.name), progress(), size: file.size, contentType: lookupMimeType(file.name));
    }
  });

  Future<void> _drop(String name, Stream<Uint8List> stream, int? size) => _run(() async {
    await _put(_child(name), stream, size: size, contentType: lookupMimeType(name));
  });

  Future<Uint8List> _readBounded(String path, int limit) async {
    final data = BytesBuilder(copy: false);
    final abort = widget.source.supportsAbortTrigger ? Completer<void>() : null;
    if (abort != null) _previewAbort.add(abort);
    try {
      await for (final chunk in widget.source.download(path, abortTrigger: abort?.future)) {
        if (data.length + chunk.length > limit) throw StateError('This file is too large for an in-app preview');
        data.add(chunk);
      }
      return data.takeBytes();
    } finally {
      if (abort != null) _previewAbort.remove(abort);
    }
  }

  Future<void> _download(List<PbFilesItemData> items) => _run(() async {
    for (final item in items) {
      if (!mounted) return;
      final source = widget.source;
      final abort = source.supportsAbortTrigger ? Completer<void>() : null;
      if (abort != null) _downloadAbort.add(abort);
      try {
        await (widget.onDownload ?? saveDownload)(item.title, source.download(item.id, abortTrigger: abort?.future));
      } finally {
        if (abort != null) _downloadAbort.remove(abort);
      }
    }
  }, refresh: false);

  PbFilePreviewSource _previewSource(PbFilesItemData item) {
    if (!_can(FileAction.read, item: item)) {
      return const PbFilePreviewSource(child: Center(child: Text('You do not have permission to read this file.')));
    }
    final pdf = p.extension(item.title).toLowerCase() == '.pdf';
    if (item.fileType == PbAttachmentFileType.image || pdf) {
      if (_imagePath != item.id) {
        _imagePath = item.id;
        _imageBytes = _readBounded(item.id, (pdf ? 32 : 8) * 1024 * 1024);
      }
      return PbFilePreviewSource(
        sourceKey: item.id,
        child: FutureBuilder<Uint8List>(
          future: _imageBytes,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text(_errorText(snapshot.error!)));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (pdf) return PdfViewer.data(snapshot.data!, sourceName: item.title);
            return InteractiveViewer(
              child: Image.memory(snapshot.data!, errorBuilder: (context, error, stack) => Center(child: Text(_errorText(error)))),
            );
          },
        ),
      );
    }
    final mime = lookupMimeType(item.title) ?? '';
    final text =
        mime.startsWith('text/') || {'application/json', 'application/javascript', 'application/xml', 'application/yaml'}.contains(mime);
    if (!text) return const PbFilePreviewSource(child: Center(child: Text('Download this file to view it.')));
    return PbFilePreviewSource(
      sourceKey: item.id,
      loadText: () async => utf8.decode(await _readBounded(item.id, 8 * 1024 * 1024)),
      saveText: !_can(FileAction.write, item: item)
          ? null
          : (text) async {
              final bytes = utf8.encode(text);
              await _put(item.id, Stream.value(bytes), size: bytes.length, contentType: mime, overwrite: true);
              if (mounted) await _load();
            },
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: PbColors.surfacePanel,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final items = _visible;
        final selected = _items.where((item) => _selected.contains(item.id)).toList();
        final canDelete =
            !_busy &&
            selected.isNotEmpty &&
            selected.every((item) => _can(FileAction.delete, item: item, recursive: item.kind == PbFilesItemKind.folder));
        final canDownload =
            !_busy &&
            selected.isNotEmpty &&
            selected.every((item) => item.kind == PbFilesItemKind.file && _can(FileAction.read, item: item));
        final browser = Column(
          children: [
            PbFilesHeader(
              currentPath: _path,
              folderLabelForPath: p.posix.basename,
              roomPanelExpanded: false,
              padding: _padding,
              showRoomPanelControls: false,
              onBreadcrumbPressed: _navigate,
              onOpenRecentFiles: () {},
              onRoomPanelToggle: () {},
            ),
            PbFilesToolbar(
              hasSelection: selected.isNotEmpty,
              selectedCount: selected.length,
              currentPath: _path,
              filterController: _filter,
              filterEnabled: !_loading,
              responsiveMode: constraints.maxWidth < 650 ? PbFilesResponsiveMode.mobile : PbFilesResponsiveMode.docked,
              padding: _padding,
              onFilterChanged: (_) => setState(() {}),
              onCreateFolder: _canCreate ? () => unawaited(_create(folder: true)) : null,
              onCreateTextFile: _canCreate ? () => unawaited(_create(folder: false)) : null,
              onUpload: _canCreate ? () => unawaited(_upload()) : null,
              showAskAgent: false,
              onClearSelection: () => setState(_selected.clear),
              onDeleteSelection: canDelete ? () => unawaited(_delete(selected)) : null,
              onDownloadSelection: canDownload ? () => unawaited(_download(selected)) : null,
              trailingAction: PbFilesToolbarTrailingAction(
                label: 'Refresh',
                iconAssetName: 'rotate-ccw',
                onPressed: _loading || _busy ? null : () => unawaited(_load()),
                width: 120,
              ),
            ),
            if (_busy && _uploadSize != null)
              LinearProgressIndicator(value: _uploadSize == null || _uploadSize == 0 ? null : (_uploaded / _uploadSize!).clamp(0, 1)),
            if (_message != null)
              ListTile(
                title: Text(_message!),
                trailing: IconButton(onPressed: () => setState(() => _message = null), icon: const Icon(Icons.close)),
              ),
            if (_loading && _items.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorText(_error!)),
                      TextButton(onPressed: () => unawaited(_load()), child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: PbFilesTable(
                  padding: _padding,
                  items: items,
                  selectedIds: _selected,
                  sortKey: _sort,
                  sortDirectionDescending: _descending,
                  previewFileId: _preview?.id,
                  keyboardPreviewFileId: null,
                  keyboardPreviewDirection: 0,
                  hasActiveFilter: _filter.text.isNotEmpty,
                  onSortChanged: (sort) => setState(() {
                    _descending = sort == _sort ? !_descending : false;
                    _sort = sort;
                  }),
                  onToggleSelection: (id) => setState(() {
                    if (!_selected.add(id)) _selected.remove(id);
                  }),
                  onToggleVisibleSelection: () => setState(() {
                    if (items.every((item) => _selected.contains(item.id))) {
                      _selected.removeAll(items.map((item) => item.id));
                    } else {
                      _selected.addAll(items.map((item) => item.id));
                    }
                  }),
                  onItemPressed: (item) => unawaited(_activate(item)),
                  onBrowseFolder: (item) => _navigate(item.id),
                  onRemoveProcessingRow: (_) {},
                  onLinkedThreadPressed: (_, _) {},
                  onDownload: !_busy && (_permissions?.recursiveActions.contains(FileAction.read) ?? false)
                      ? (item) {
                          if (item.kind == PbFilesItemKind.file) unawaited(_download([item]));
                        }
                      : null,
                  onRename:
                      !_busy &&
                          (_permissions?.recursiveActions.contains(FileAction.write) ?? false) &&
                          (_permissions?.recursiveActions.contains(FileAction.delete) ?? false)
                      ? (item) => unawaited(_rename(item))
                      : null,
                  onMoveTo:
                      !_busy &&
                          (_permissions?.recursiveActions.contains(FileAction.write) ?? false) &&
                          (_permissions?.recursiveActions.contains(FileAction.delete) ?? false)
                      ? (item) => unawaited(_rename(item, move: true))
                      : null,
                  onDelete: !_busy && (_permissions?.recursiveActions.contains(FileAction.delete) ?? false)
                      ? (item) => unawaited(_delete([item]))
                      : null,
                ),
              ),
            if (_next != null)
              TextButton(onPressed: _loading ? null : () => unawaited(_load(more: true)), child: Text(_loading ? 'Loading…' : 'Load more')),
          ],
        );
        final preview = _preview;
        Widget content = browser;
        if (preview != null) {
          final pane = PbFilesSidePane(
            files: _items,
            previewFile: preview,
            fullscreen: _fullscreen,
            resizing: false,
            borderOnTop: false,
            responsiveOverlay: false,
            responsiveOverlayMobile: constraints.maxWidth < 800,
            onPreviewFile: (item) => unawaited(_activate(item)),
            previewSourceBuilder: _previewSource,
            onDownload: !_busy && _can(FileAction.read, item: preview) ? (item) => unawaited(_download([item])) : null,
            onToggleFullscreen: () => setState(() => _fullscreen = !_fullscreen),
            onClosePreview: () {
              _cancelPreviews();
              setState(() {
                _preview = null;
                _fullscreen = false;
              });
            },
          );
          content = _fullscreen || constraints.maxWidth < 800
              ? pane
              : Row(
                  children: [
                    Expanded(child: browser),
                    SizedBox(width: constraints.maxWidth * .42, child: pane),
                  ],
                );
        }
        return _canCreate
            ? PbFilesDropTargetLayer(
                dropTargetTop: 76,
                padding: _padding,
                onFilesDropped: (_) {},
                child: FileDropArea(onFileDrop: _drop, overlayBuilder: (context, dragging) => const SizedBox.shrink(), child: content),
              )
            : content;
      },
    ),
  );
}
