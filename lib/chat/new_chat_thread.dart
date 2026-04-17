import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

typedef NewChatThreadBuilder = Widget Function(BuildContext context, String threadPath);
typedef NewChatThreadToolsBuilder = Widget Function(BuildContext context, ChatThreadController controller, ChatThreadSnapshot state);

class NewChatThread extends StatefulWidget {
  const NewChatThread({
    super.key,
    required this.room,
    required this.agentName,
    required this.builder,
    this.controller,
    this.composerKey,
    this.toolkit = "chat",
    this.tool = "new_thread",
    this.toolsBuilder,
    this.selectedThreadPath,
    this.onThreadPathChanged,
    this.onThreadResolved,
    this.centerComposer = true,
    this.emptyState,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
  });

  final RoomClient room;
  final String agentName;
  final NewChatThreadBuilder builder;
  final ChatThreadController? controller;
  final GlobalKey? composerKey;
  final String toolkit;
  final String tool;
  final NewChatThreadToolsBuilder? toolsBuilder;
  final String? selectedThreadPath;
  final ValueChanged<String?>? onThreadPathChanged;
  final void Function(String? path, String? displayName)? onThreadResolved;
  final bool centerComposer;
  final Widget? emptyState;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;

  @override
  State<NewChatThread> createState() => _NewChatThreadState();
}

class _NewChatThreadState extends State<NewChatThread> {
  late ChatThreadController _controller;
  late Key _composerInputKey;
  late bool _ownsController;
  StreamSubscription<RoomEvent>? _roomSubscription;
  RemoteParticipant? _agent;
  bool _creatingNewThread = false;
  bool _waitingForAgent = false;
  String? _newThreadError;
  String? _threadPath;
  int _newThreadOperationId = 0;
  Completer<RemoteParticipant>? _waitForAgentCompleter;
  Completer<void>? _waitForAgentReadyCompleter;

  bool get _composerLocked => _creatingNewThread || _waitingForAgent;

  String? get _activeThreadPath {
    final externalPath = widget.selectedThreadPath?.trim();
    if (externalPath != null && externalPath.isNotEmpty) {
      return externalPath;
    }

    final localPath = _threadPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    return localPath;
  }

  String _chatPlaceholderText() {
    final normalizedAgentName = widget.agentName.trim();
    if (normalizedAgentName.isEmpty) {
      return "Type a message";
    }

    return "Type a message or @$normalizedAgentName";
  }

  void _notifyThreadPathChanged(String? path) {
    widget.onThreadPathChanged?.call(path);
  }

  void _notifyThreadResolved(String? path, String? displayName) {
    widget.onThreadResolved?.call(path, displayName);
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    _roomSubscription = widget.room.listen(_onRoomEvent);
    widget.room.messaging.addListener(_onMessagingChanged);
    _onMessagingChanged();
  }

  @override
  void didUpdateWidget(covariant NewChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerKey != widget.composerKey) {
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    }

    if (oldWidget.room != widget.room || oldWidget.controller != widget.controller) {
      _newThreadOperationId++;
      _roomSubscription?.cancel();
      _roomSubscription = widget.room.listen(_onRoomEvent);
      oldWidget.room.messaging.removeListener(_onMessagingChanged);
      widget.room.messaging.addListener(_onMessagingChanged);

      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? ChatThreadController(room: widget.room);
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
      _threadPath = null;
      _newThreadError = null;
      _creatingNewThread = false;
      _waitingForAgent = false;
      _cancelWaitingForAgent();
      _onMessagingChanged();
    }

    if (oldWidget.agentName != widget.agentName) {
      _newThreadOperationId++;
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
      _threadPath = null;
      _newThreadError = null;
      _creatingNewThread = false;
      _waitingForAgent = false;
      _cancelWaitingForAgent();
      _controller.clear();
      _onMessagingChanged();
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    widget.room.messaging.removeListener(_onMessagingChanged);
    _cancelWaitingForAgent();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is! RoomMessageEvent) {
      return;
    }
    _signalWaitingForAgentReady();
  }

  void _onMessagingChanged() {
    if (!mounted) {
      return;
    }

    final nextAgent = widget.room.messaging.remoteParticipants.firstWhereOrNull(
      (participant) => participant.getAttribute("name") == widget.agentName,
    );
    if (nextAgent == _agent) {
      _signalWaitingForAgentReady();
      return;
    }

    setState(() {
      _agent = nextAgent;
    });

    final waitCompleter = _waitForAgentCompleter;
    if (nextAgent != null && waitCompleter != null && !waitCompleter.isCompleted) {
      waitCompleter.complete(nextAgent);
      _waitForAgentCompleter = null;
    }

    _signalWaitingForAgentReady();
  }

  Future<RemoteParticipant> _waitForAgentOnline() {
    final agent = _agent;
    if (agent != null) {
      return Future.value(agent);
    }

    final existing = _waitForAgentCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<RemoteParticipant>();
    _waitForAgentCompleter = completer;
    return completer.future;
  }

  void _cancelWaitingForAgent() {
    final completer = _waitForAgentCompleter;
    _waitForAgentCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const ChatSendCancelledException());
    }

    final readinessCompleter = _waitForAgentReadyCompleter;
    _waitForAgentReadyCompleter = null;
    if (readinessCompleter != null && !readinessCompleter.isCompleted) {
      readinessCompleter.completeError(const ChatSendCancelledException());
    }
  }

  void _signalWaitingForAgentReady() {
    final completer = _waitForAgentReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _waitForToolkitAvailable({required String toolkitName}) async {
    while (true) {
      final agent = _agent ?? await _waitForAgentOnline();

      try {
        final toolkits = await widget.room.agents.listToolkits(participantId: agent.id, timeout: 1000);
        if (toolkits.any((toolkit) => toolkit.name == toolkitName)) {
          return;
        }
      } catch (_) {}

      final completer = Completer<void>();
      _waitForAgentReadyCompleter = completer;
      try {
        await Future.any([completer.future, Future<void>.delayed(const Duration(milliseconds: 250))]);
      } on ChatSendCancelledException {
        rethrow;
      } finally {
        if (identical(_waitForAgentReadyCompleter, completer)) {
          _waitForAgentReadyCompleter = null;
        }
      }
    }
  }

  Future<void> _startNewThread() async {
    final prompt = _controller.text.trim();
    final attachments = _controller.attachmentUploads;
    final attachmentPaths = [for (final attachment in attachments) attachment.path];
    final hasPendingUploads = attachments.any((attachment) => attachment.status != UploadStatus.completed);
    if (_creatingNewThread || _waitingForAgent || hasPendingUploads) {
      return;
    }
    if (prompt.isEmpty && attachments.isEmpty) {
      return;
    }

    final operationId = ++_newThreadOperationId;
    final waitingForAgent = _agent == null;
    setState(() {
      _creatingNewThread = !waitingForAgent;
      _waitingForAgent = waitingForAgent;
      _newThreadError = null;
    });

    try {
      final agent = _agent ?? await _waitForAgentOnline();
      await _waitForToolkitAvailable(toolkitName: widget.toolkit);
      final readyAgent = _agent ?? agent;
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }

      if (_waitingForAgent) {
        setState(() {
          _waitingForAgent = false;
          _creatingNewThread = true;
        });
      }

      final result = await widget.room.agents.invokeTool(
        toolkit: widget.toolkit,
        tool: widget.tool,
        participantId: readyAgent.id,
        input: ToolContentInput(
          JsonContent(
            json: {
              "message": {
                "text": prompt,
                "attachments": [
                  for (final path in attachmentPaths) {"path": path},
                ],
              },
            },
          ),
        ),
      );

      final content = switch (result) {
        ToolContentOutput(:final content) => content,
        ToolStreamOutput() => throw RoomServerException("${widget.toolkit}.${widget.tool} returned a stream; expected json content"),
      };

      if (content is! JsonContent) {
        throw RoomServerException("${widget.toolkit}.${widget.tool} returned ${content.runtimeType}; expected json content");
      }

      final responsePath = content.json["path"];
      if (responsePath is! String || responsePath.trim().isEmpty) {
        throw RoomServerException("${widget.toolkit}.${widget.tool} response missing path");
      }
      final path = responsePath.trim();
      final responseName = content.json["name"];
      final threadName = responseName is String && responseName.trim().isNotEmpty ? responseName.trim() : null;
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }

      final defersToParent = widget.onThreadPathChanged != null || widget.onThreadResolved != null;
      setState(() {
        _threadPath = defersToParent ? null : path;
        _newThreadError = null;
        _creatingNewThread = false;
        _waitingForAgent = false;
      });
      _notifyThreadResolved(path, threadName);
      _notifyThreadPathChanged(path);
      _controller.clear();
    } on ChatSendCancelledException {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      setState(() {
        _creatingNewThread = false;
        _waitingForAgent = false;
        _newThreadError = null;
      });
    } catch (e) {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      setState(() {
        _creatingNewThread = false;
        _waitingForAgent = false;
        _newThreadError = "$e";
      });
    }
  }

  void _cancelPendingNewThread() {
    if (!_creatingNewThread && !_waitingForAgent) {
      return;
    }

    _newThreadOperationId++;
    _cancelWaitingForAgent();

    setState(() {
      _creatingNewThread = false;
      _waitingForAgent = false;
      _newThreadError = null;
    });
  }

  void _goToNewMessageScreen() {
    if (_creatingNewThread || _waitingForAgent) {
      _cancelPendingNewThread();
      return;
    }
    if (_activeThreadPath == null) {
      return;
    }
    setState(() {
      _threadPath = null;
      _newThreadError = null;
      _waitingForAgent = false;
    });
    _notifyThreadResolved(null, null);
    _notifyThreadPathChanged(null);
    _controller.clear();
  }

  ChatThreadSnapshot _buildSnapshot() {
    return ChatThreadSnapshot(
      messages: const [],
      online: _agent == null ? const [] : [_agent!],
      offline: const [],
      typing: const [],
      listening: const [],
      agentOnline: _agent != null,
      threadStatus: null,
      threadStatusStartedAt: null,
      threadStatusMode: null,
      supportsAgentMessages: _agent?.getAttribute("supports_agent_messages") == true,
      supportsMcp: _agent?.getAttribute("supports_mcp") == true,
      toolkits: const {},
      threadTurnId: null,
      pendingMessages: const [],
      pendingItemId: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_activeThreadPath) {
      final threadPath? => widget.builder(context, threadPath),
      _ => _buildNewThreadComposer(context),
    };

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyN, control: true): _goToNewMessageScreen},
      child: content,
    );
  }

  Widget _buildComposerDropArea({required Widget child}) {
    return FileDropArea(
      onFileDrop: (name, dataStream, fileSize) async {
        if (_composerLocked) {
          return;
        }
        await _controller.uploadFile(name, dataStream, fileSize ?? 0);
      },
      child: child,
    );
  }

  Widget _buildNewThreadComposer(BuildContext context) {
    final snapshot = _buildSnapshot();
    final toolsBuilder = widget.toolsBuilder;
    final toolArea = resolveChatThreadToolArea(toolsBuilder == null ? null : toolsBuilder(context, _controller, snapshot));
    final headingStyle = ShadTheme.of(context).textTheme.h4;
    final input = ChatThreadInput(
      key: _composerInputKey,
      focusTrigger: _controller,
      room: widget.room,
      controller: _controller,
      sendEnabled: !_composerLocked,
      sendDisabledReason: _waitingForAgent ? "Waiting for ${widget.agentName} to be ready." : "Wait for the message to be accepted.",
      sendPendingText: _waitingForAgent ? "Waiting for ${widget.agentName} to be ready." : "Wait for the message to be accepted.",
      onCancelSend: _composerLocked ? _cancelPendingNewThread : null,
      readOnly: false,
      clearOnSend: false,
      placeholder: Text(_chatPlaceholderText()),
      leading: toolArea.leading,
      footer: toolArea.footer,
      trailing: null,
      onSend: (value, attachments) async {
        if (value.isEmpty && attachments.isEmpty) {
          return;
        }
        if (!_creatingNewThread && !_waitingForAgent) {
          await _startNewThread();
        }
      },
      contextMenuBuilder: widget.inputContextMenuBuilder,
      onPressedOutside: widget.inputOnPressedOutside,
    );

    final content = !widget.centerComposer
        ? Column(
            children: [
              Expanded(child: Center(child: widget.emptyState ?? const SizedBox.shrink())),
              if (_newThreadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 912),
                      child: ShadAlert.destructive(title: const Text("Unable to start thread"), description: Text(_newThreadError!)),
                    ),
                  ),
                ),
              ChatThreadInputFrame(child: input),
            ],
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 912),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    Text("Start a new thread", style: headingStyle),
                    input,
                    if (_newThreadError != null) ...[
                      ShadAlert.destructive(title: const Text("Unable to start thread"), description: Text(_newThreadError!)),
                    ],
                  ],
                ),
              ),
            ),
          );

    return _buildComposerDropArea(child: content);
  }
}
