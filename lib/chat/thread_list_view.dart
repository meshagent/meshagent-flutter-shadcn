import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' hide defaultThreadDisplayNameFromPath, defaultUntitledThreadName;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'conversation_descriptor.dart';
import '../ui/coordinated_context_menu.dart';

class ChatThreadListView extends StatefulWidget {
  const ChatThreadListView({
    super.key,
    required this.room,
    this.chatClient,
    required this.threadListPath,
    required this.selectedThreadPath,
    required this.onSelectedThreadPathChanged,
    this.onSelectedThreadResolved,
    this.selectedThreadDisplayName,
    this.agentName,
    this.showCreateItem = true,
    this.newThreadResetVersion = 0,
  });

  final RoomClient? room;
  final BaseChatClient? chatClient;
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
  _ChatThreadListStore? _store;
  String? _openedPath;
  Object? _error;
  bool _loading = true;
  final Map<String, String> _optimisticNames = <String, String>{};
  final Set<String> _optimisticDeletedPaths = <String>{};

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

  DateTime _sortDate(ThreadListEntry entry) {
    if (entry.modifiedAt.trim().isNotEmpty) {
      return _parseDate(entry.modifiedAt);
    }
    if (entry.createdAt.trim().isNotEmpty) {
      return _parseDate(entry.createdAt);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  DateTime _createdSortDate(ThreadListEntry entry) {
    if (entry.createdAt.trim().isNotEmpty) {
      return _parseDate(entry.createdAt);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  int _compareEntries(ThreadListEntry a, ThreadListEntry b) {
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

  List<ThreadListEntry> _entries() {
    final store = _store;
    if (store == null) {
      return const <ThreadListEntry>[];
    }
    final entries = store.entries().where((entry) => !_optimisticDeletedPaths.contains(entry.path)).map((entry) {
      final optimisticName = _optimisticNames[entry.path];
      if (optimisticName == null) {
        return entry;
      }
      return entry.renamed(optimisticName, entry.modifiedAt);
    }).toList();
    entries.sort(_compareEntries);
    return entries;
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

  Future<void> _renameThread(ThreadListEntry entry) async {
    final nextName = await _showRenameDialog(entry.name);
    if (nextName == null) {
      return;
    }

    final trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == entry.name) {
      return;
    }

    setState(() {
      _optimisticNames[entry.path] = trimmed;
    });
    try {
      await _sendThreadControlMessage(RenameThread(threadId: entry.path, name: trimmed));
    } catch (_) {
      if (mounted) {
        setState(() {
          _optimisticNames.remove(entry.path);
        });
      }
      rethrow;
    }
  }

  Future<bool> _confirmDeleteThread(ThreadListEntry entry) async {
    final result = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return ShadDialog(
          title: const Text("Delete thread"),
          description: Text('Delete "${entry.name}"?'),
          actions: [
            ShadButton.outline(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
            ShadButton.destructive(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Delete")),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _deleteThread(ThreadListEntry entry) async {
    if (!await _confirmDeleteThread(entry)) {
      return;
    }

    setState(() {
      _optimisticDeletedPaths.add(entry.path);
    });
    try {
      await _sendThreadControlMessage(DeleteThread(threadId: entry.path));
    } catch (_) {
      if (mounted) {
        setState(() {
          _optimisticDeletedPaths.remove(entry.path);
        });
      }
      rethrow;
    }
    if (_normalizePath(widget.selectedThreadPath) == entry.path) {
      widget.onSelectedThreadPathChanged(null);
      widget.onSelectedThreadResolved?.call(null, null);
    }
  }

  RemoteParticipant? _agentParticipant() {
    final room = widget.room;
    if (room == null) {
      return null;
    }
    final normalizedAgentName = widget.agentName?.trim();
    for (final participant in room.messaging.remoteParticipants) {
      if (normalizedAgentName != null && normalizedAgentName.isNotEmpty && participant.getAttribute("name") != normalizedAgentName) {
        continue;
      }
      if (participant.getAttribute("supports_agent_messages") == true) {
        return participant;
      }
    }
    return null;
  }

  Future<void> _sendThreadControlMessage(AgentMessage message) async {
    final chatClient = widget.chatClient;
    if (chatClient != null) {
      await chatClient.sendAgentMessage(message);
      return;
    }
    final room = widget.room;
    if (room == null) {
      throw StateError("Unable to send thread message without a room or agent chat client.");
    }
    final agent = _agentParticipant();
    if (agent == null) {
      throw StateError("Unable to find an agent that supports thread messages.");
    }
    await room.messaging.sendMessage(to: agent, type: agentRoomMessageType, message: message.toJson());
  }

  void _onStoreChanged() {
    if (mounted) {
      final storeEntries = _store?.entries() ?? const <ThreadListEntry>[];
      final storePaths = storeEntries.map((entry) => entry.path).toSet();
      _optimisticNames.removeWhere((path, name) {
        return storeEntries.any((entry) => entry.path == path && entry.name == name);
      });
      _optimisticDeletedPaths.removeWhere((path) => !storePaths.contains(path));
      setState(() {});
    }
  }

  Future<void> _closeStore() async {
    final store = _store;

    _store = null;
    _openedPath = null;
    _loading = false;

    if (store != null) {
      await store.close();
    }
  }

  _ChatThreadListStore _createStore(String path) {
    if (path.startsWith("agent://")) {
      final chatClient = widget.chatClient;
      if (chatClient == null) {
        throw StateError("Agent thread lists require an agent chat client.");
      }
      return _AgentChatThreadListStore(chatClient: chatClient, onChanged: _onStoreChanged);
    }
    final room = widget.room;
    if (room == null) {
      throw StateError("Room thread lists require a room client.");
    }
    if (path.startsWith("dataset://")) {
      return _DatasetChatThreadListStore(room: room, path: path, onChanged: _onStoreChanged);
    }
    return _MeshDocumentChatThreadListStore(room: room, path: path, onChanged: _onStoreChanged);
  }

  Future<void> _waitForAgentThreadListReady(String path) async {
    if (!path.startsWith("agent://")) {
      return;
    }
    final chatClient = widget.chatClient;
    if (chatClient == null) {
      throw StateError("Agent thread lists require an agent chat client.");
    }
    await chatClient.start();
    if (chatClient is MessagingChatClient) {
      await chatClient.waitForAgentParticipant();
    }
  }

  Future<void> _rebindStore() async {
    final nextPath = _normalizePath(widget.threadListPath);
    if (nextPath == _openedPath && _store != null) {
      return;
    }

    await _closeStore();

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
      await _waitForAgentThreadListReady(nextPath);
      if (!mounted || _normalizePath(widget.threadListPath) != nextPath) {
        return;
      }
      final store = _createStore(nextPath);
      await store.open();
      if (!mounted || _normalizePath(widget.threadListPath) != nextPath) {
        await store.close();
        return;
      }

      setState(() {
        _store = store;
        _openedPath = nextPath;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _store = null;
        _openedPath = null;
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_rebindStore());
  }

  @override
  void didUpdateWidget(covariant ChatThreadListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room || oldWidget.chatClient != widget.chatClient || oldWidget.threadListPath != widget.threadListPath) {
      _optimisticNames.clear();
      _optimisticDeletedPaths.clear();
      unawaited(_rebindStore());
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
    unawaited(_closeStore());
    super.dispose();
  }

  Widget _buildRow(
    BuildContext context, {
    required String title,
    required bool selected,
    required VoidCallback onTap,
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
                    child: Center(child: Icon(selected ? LucideIcons.check : fallbackIcon, size: 14, color: foreground)),
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
    final hasSelectedEntry = selectedThreadPath != null && entries.any((entry) => entry.path == selectedThreadPath);
    final showPendingNewThreadSelection = selectedThreadPath == null || !hasSelectedEntry;
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

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      children: [
        if (widget.showCreateItem)
          _buildRow(
            context,
            title: "New thread",
            selected: showPendingNewThreadSelection,
            fallbackIcon: showPendingNewThreadSelection ? LucideIcons.check : LucideIcons.messageSquarePlus,
            onTap: () {
              widget.onSelectedThreadPathChanged(null);
              widget.onSelectedThreadResolved?.call(null, null);
            },
          ),
        if (entries.isEmpty && showPendingNewThreadSelection)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("No threads yet", textAlign: TextAlign.center, style: ShadTheme.of(context).textTheme.muted),
          ),
        for (final entry in entries)
          _buildRow(
            context,
            title: entry.name,
            selected: entry.path == selectedThreadPath,
            trailing: _ChatThreadListMenuButton(onRename: () => _renameThread(entry), onDelete: () => _deleteThread(entry)),
            onTap: () {
              widget.onSelectedThreadPathChanged(entry.path);
              widget.onSelectedThreadResolved?.call(entry.path, entry.name);
            },
          ),
      ],
    );
  }
}

abstract class _ChatThreadListStore {
  Future<void> open();

  Future<void> close();

  List<ThreadListEntry> entries();
}

class _MeshDocumentChatThreadListStore implements _ChatThreadListStore {
  _MeshDocumentChatThreadListStore({required this.room, required this.path, required this.onChanged});

  final RoomClient room;
  final String path;
  final VoidCallback onChanged;
  MeshDocument? _document;

  @override
  Future<void> open() async {
    final document = await room.sync.open(path);
    _document = document;
    document.addListener(onChanged);
  }

  @override
  Future<void> close() async {
    final document = _document;
    _document = null;
    if (document != null) {
      document.removeListener(onChanged);
    }
    try {
      await room.sync.close(path);
    } catch (_) {}
  }

  @override
  List<ThreadListEntry> entries() {
    final document = _document;
    if (document == null) {
      return const <ThreadListEntry>[];
    }

    final entries = <ThreadListEntry>[];
    for (final child in document.root.getChildren()) {
      if (child is! MeshElement || child.tagName != "thread") {
        continue;
      }

      final rawPath = child.getAttribute("path");
      if (rawPath is! String || rawPath.trim().isEmpty) {
        continue;
      }

      final threadPath = rawPath.trim();
      final rawName = child.getAttribute("name");
      final createdAt = child.getAttribute("created_at");
      final modifiedAt = child.getAttribute("modified_at");
      entries.add(
        ThreadListEntry(
          path: threadPath,
          name: rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : defaultThreadDisplayNameFromPath(threadPath),
          createdAt: createdAt is String ? createdAt : "",
          modifiedAt: modifiedAt is String ? modifiedAt : "",
        ),
      );
    }
    return entries;
  }
}

class _DatasetChatThreadListStore implements _ChatThreadListStore {
  _DatasetChatThreadListStore({required RoomClient room, required String path, required this.onChanged})
    : storage = DatasetThreadStorage(room: room, path: path);

  final DatasetThreadStorage storage;
  final VoidCallback onChanged;

  @override
  Future<void> open() async {
    storage.addListener(onChanged);
    await storage.open();
  }

  @override
  Future<void> close() async {
    storage.removeListener(onChanged);
    await storage.close();
  }

  @override
  List<ThreadListEntry> entries() => storage.entries();
}

class _AgentChatThreadListStore implements _ChatThreadListStore {
  _AgentChatThreadListStore({required BaseChatClient chatClient, required this.onChanged})
    : storage = AgentThreadStorageRepository(chatClient: chatClient);

  final AgentThreadStorageRepository storage;
  final VoidCallback onChanged;

  @override
  Future<void> open() async {
    storage.addListener(onChanged);
    await storage.open();
  }

  @override
  Future<void> close() async {
    storage.removeListener(onChanged);
    await storage.close();
  }

  @override
  List<ThreadListEntry> entries() => storage.entries();
}

class _ChatThreadListMenuButton extends StatefulWidget {
  const _ChatThreadListMenuButton({required this.onRename, required this.onDelete});

  final VoidCallback onRename;
  final VoidCallback onDelete;

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
      estimatedMenuHeight: 88,
      items: [
        ShadContextMenuItem(
          height: 40,
          leading: const Icon(LucideIcons.pencil, size: 16),
          onPressed: widget.onRename,
          child: const Text("Rename"),
        ),
        ShadContextMenuItem(
          height: 40,
          leading: const Icon(LucideIcons.trash2, size: 16),
          onPressed: widget.onDelete,
          child: const Text("Delete"),
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
