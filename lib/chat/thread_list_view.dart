import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat.dart';
import 'conversation_descriptor.dart';
import '../ui/coordinated_context_menu.dart';

class ChatThreadListView extends StatefulWidget {
  const ChatThreadListView({
    super.key,
    required this.room,
    required this.threadListPath,
    required this.selectedThreadPath,
    required this.onSelectedThreadPathChanged,
    this.onSelectedThreadResolved,
    this.selectedThreadDisplayName,
    this.agentName,
    this.showCreateItem = true,
    this.newThreadResetVersion = 0,
  });

  final RoomClient room;
  final String threadListPath;
  final String? agentName;
  final String? selectedThreadPath;
  final String? selectedThreadDisplayName;
  final ValueChanged<String?> onSelectedThreadPathChanged;
  final void Function(String? path, String? displayName)? onSelectedThreadResolved;
  final bool showCreateItem;
  final int newThreadResetVersion;

  @override
  State<ChatThreadListView> createState() => _ChatThreadListViewState();
}

class _ChatThreadListViewState extends State<ChatThreadListView> {
  MeshDocument? _document;
  String? _openedPath;
  Object? _error;
  bool _loading = true;

  String? _normalizePath(String? path) {
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  DateTime _parseDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return parsed.toUtc();
  }

  DateTime _sortDate(_ChatThreadListEntry entry) {
    if (entry.modifiedAt.trim().isNotEmpty) {
      return _parseDate(entry.modifiedAt);
    }
    if (entry.createdAt.trim().isNotEmpty) {
      return _parseDate(entry.createdAt);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  DateTime _createdSortDate(_ChatThreadListEntry entry) {
    if (entry.createdAt.trim().isNotEmpty) {
      return _parseDate(entry.createdAt);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  int _compareEntries(_ChatThreadListEntry a, _ChatThreadListEntry b) {
    final dateComparison = _sortDate(b).compareTo(_sortDate(a));
    if (dateComparison != 0) {
      return dateComparison;
    }

    final createdDateComparison = _createdSortDate(b).compareTo(_createdSortDate(a));
    if (createdDateComparison != 0) {
      return createdDateComparison;
    }

    return a.path.compareTo(b.path);
  }

  List<_ChatThreadListEntry> _entries() {
    final document = _document;
    if (document == null) {
      return const <_ChatThreadListEntry>[];
    }

    final entries = <_ChatThreadListEntry>[];
    for (final child in document.root.getChildren()) {
      if (child is! MeshElement || child.tagName != "thread") {
        continue;
      }

      final rawPath = child.getAttribute("path");
      if (rawPath is! String || rawPath.trim().isEmpty) {
        continue;
      }

      final path = rawPath.trim();
      final rawName = child.getAttribute("name");
      final createdAt = child.getAttribute("created_at");
      final modifiedAt = child.getAttribute("modified_at");

      entries.add(
        _ChatThreadListEntry(
          element: child,
          path: path,
          name: rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : defaultThreadDisplayNameFromPath(path),
          createdAt: createdAt is String ? createdAt : "",
          modifiedAt: modifiedAt is String ? modifiedAt : "",
        ),
      );
    }

    entries.sort(_compareEntries);
    return entries;
  }

  _ChatThreadListEntry? _entryForPath(String path) {
    for (final entry in _entries()) {
      if (entry.path == path) {
        return entry;
      }
    }
    return null;
  }

  Future<String?> _showRenameDialog(String initialValue) {
    final formKey = GlobalKey<ShadFormState>();

    return showShadDialog<String?>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (!formKey.currentState!.saveAndValidate()) {
            return;
          }

          final values = formKey.currentState!.value;
          final nextName = (values["name"] as String).trim();
          Navigator.of(dialogContext).pop(nextName);
        }

        return ShadDialog(
          title: const Text("Rename thread"),
          description: const Text("Use a short, descriptive name."),
          actions: [
            ShadButton.outline(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text("Cancel")),
            ShadButton(onPressed: submit, child: const Text("Save")),
          ],
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ShadForm(
              key: formKey,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: ShadInputFormField(
                  id: "name",
                  label: const Text("Name"),
                  initialValue: initialValue,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  validator: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isEmpty) {
                      return "Please enter a name.";
                    }
                    return null;
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameThread(_ChatThreadListEntry entry) async {
    final nextName = await _showRenameDialog(entry.name);
    if (nextName == null) {
      return;
    }

    final trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == entry.name) {
      return;
    }

    entry.element.setAttribute("name", trimmed);
  }

  void _onDocumentChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _closeDocument() async {
    final document = _document;
    final openedPath = _openedPath;

    if (document != null) {
      document.removeListener(_onDocumentChanged);
    }

    _document = null;
    _openedPath = null;
    _loading = false;

    if (openedPath != null) {
      try {
        await widget.room.sync.close(openedPath);
      } catch (_) {}
    }
  }

  Future<void> _rebindDocument() async {
    final nextPath = _normalizePath(widget.threadListPath);
    if (nextPath == _openedPath && _document != null) {
      return;
    }

    await _closeDocument();

    if (!mounted || nextPath == null) {
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final document = await widget.room.sync.open(nextPath);
      if (!mounted || _normalizePath(widget.threadListPath) != nextPath) {
        try {
          await widget.room.sync.close(nextPath);
        } catch (_) {}
        return;
      }

      document.addListener(_onDocumentChanged);
      setState(() {
        _document = document;
        _openedPath = nextPath;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _document = null;
        _openedPath = null;
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_rebindDocument());
  }

  @override
  void didUpdateWidget(covariant ChatThreadListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room || oldWidget.threadListPath != widget.threadListPath) {
      unawaited(_rebindDocument());
    }

    if (oldWidget.newThreadResetVersion != widget.newThreadResetVersion && widget.selectedThreadPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSelectedThreadPathChanged(null);
        widget.onSelectedThreadResolved?.call(null, null);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_closeDocument());
    super.dispose();
  }

  Widget _buildRow(
    BuildContext context, {
    required String title,
    required bool selected,
    required VoidCallback onTap,
    ChatThreadStatusState? status,
    IconData fallbackIcon = LucideIcons.messageSquare,
    Widget? trailing,
  }) {
    final theme = ShadTheme.of(context);
    final background = selected ? theme.colorScheme.accent : Colors.transparent;
    final foreground = selected ? theme.colorScheme.foreground : theme.colorScheme.mutedForeground;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Center(
                      child: status == null
                          ? Icon(fallbackIcon, size: 14, color: foreground)
                          : selected && !status.hasStatus
                          ? Icon(LucideIcons.check, size: 14, color: foreground)
                          : ChatThreadStatusIndicator(
                              statusText: status.text,
                              startedAt: status.startedAt,
                              reserveSpace: true,
                              size: 14,
                              strokeWidth: 2,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.small.copyWith(color: foreground, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ?? const SizedBox(width: 32, height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final selectedThreadPath = _normalizePath(widget.selectedThreadPath);
    final selectedEntry = selectedThreadPath == null ? null : _entryForPath(selectedThreadPath);
    final selectedThreadDisplayName = (() {
      final normalized = widget.selectedThreadDisplayName?.trim();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      return normalized;
    })();
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text("Unable to load threads: $_error", textAlign: TextAlign.center),
        ),
      );
    }

    final hasSelectedEntry = selectedEntry != null;
    final pendingSelectedThreadTitle = selectedThreadPath == null
        ? null
        : selectedThreadDisplayName ?? defaultThreadDisplayNameFromPath(selectedThreadPath);

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      children: [
        if (widget.showCreateItem)
          _buildRow(
            context,
            title: "New thread",
            selected: selectedThreadPath == null,
            fallbackIcon: selectedThreadPath == null ? LucideIcons.check : LucideIcons.messageSquarePlus,
            onTap: () {
              widget.onSelectedThreadPathChanged(null);
              widget.onSelectedThreadResolved?.call(null, null);
            },
          ),
        if (selectedThreadPath != null && !hasSelectedEntry)
          _buildRow(
            context,
            title: pendingSelectedThreadTitle!,
            selected: true,
            status: resolveChatThreadStatus(room: widget.room, path: selectedThreadPath, agentName: widget.agentName),
            onTap: () {},
          ),
        if (entries.isEmpty && selectedThreadPath == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("No threads yet", textAlign: TextAlign.center, style: ShadTheme.of(context).textTheme.muted),
          ),
        for (final entry in entries)
          _buildRow(
            context,
            title: entry.name,
            selected: entry.path == selectedThreadPath,
            status: resolveChatThreadStatus(room: widget.room, path: entry.path, agentName: widget.agentName),
            trailing: _ChatThreadListMenuButton(onRename: () => _renameThread(entry)),
            onTap: () {
              widget.onSelectedThreadPathChanged(entry.path);
              widget.onSelectedThreadResolved?.call(entry.path, entry.name);
            },
          ),
      ],
    );
  }
}

class _ChatThreadListEntry {
  const _ChatThreadListEntry({
    required this.element,
    required this.path,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
  });

  final MeshElement element;
  final String path;
  final String name;
  final String createdAt;
  final String modifiedAt;
}

class _ChatThreadListMenuButton extends StatefulWidget {
  const _ChatThreadListMenuButton({required this.onRename});

  final VoidCallback onRename;

  @override
  State<_ChatThreadListMenuButton> createState() => _ChatThreadListMenuButtonState();
}

class _ChatThreadListMenuButtonState extends State<_ChatThreadListMenuButton> {
  late final ShadContextMenuController _controller = ShadContextMenuController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoordinatedShadContextMenu(
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 160),
      estimatedMenuWidth: 160,
      estimatedMenuHeight: 48,
      items: [
        ShadContextMenuItem(
          height: 40,
          leading: const Icon(LucideIcons.pencil, size: 16),
          onPressed: widget.onRename,
          child: const Text("Rename"),
        ),
      ],
      child: ShadButton.ghost(
        onPressed: _controller.toggle,
        width: 32,
        height: 32,
        padding: EdgeInsets.zero,
        child: const Icon(LucideIcons.ellipsis, size: 16),
      ),
    );
  }
}
