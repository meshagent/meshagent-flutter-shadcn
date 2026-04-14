import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

typedef NewChatThreadBuilder =
    Widget Function(BuildContext context, String threadPath, Widget Function(BuildContext context)? loadingBuilder);
typedef NewChatThreadToolsBuilder = Widget Function(BuildContext context, ChatThreadController controller, ChatThreadSnapshot state);

class NewChatThread extends StatefulWidget {
  const NewChatThread({
    super.key,
    required this.room,
    required this.agentName,
    required this.builder,
    this.controller,
    this.toolkit = "chat",
    this.tool = "new_thread",
    this.toolsBuilder,
    this.onThreadPathChanged,
    this.centerComposer = true,
    this.emptyState,
  });

  final RoomClient room;
  final String agentName;
  final NewChatThreadBuilder builder;
  final ChatThreadController? controller;
  final String toolkit;
  final String tool;
  final NewChatThreadToolsBuilder? toolsBuilder;
  final ValueChanged<String?>? onThreadPathChanged;
  final bool centerComposer;
  final Widget? emptyState;

  @override
  State<NewChatThread> createState() => _NewChatThreadState();
}

class _NewChatThreadState extends State<NewChatThread> {
  late ChatThreadController _controller;
  late bool _ownsController;
  StreamSubscription<RoomEvent>? _roomSubscription;
  RemoteParticipant? _agent;
  bool _creatingNewThread = false;
  bool _waitingForAgent = false;
  DateTime? _creatingNewThreadStartedAt;
  String? _newThreadError;
  String? _threadPath;
  String? _pendingMessageText;
  List<String> _pendingAttachmentPaths = const [];
  int _newThreadOperationId = 0;
  Completer<RemoteParticipant>? _waitForAgentCompleter;
  Completer<void>? _waitForAgentReadyCompleter;
  final GlobalKey _sendingStatusKey = GlobalKey();

  String? _pendingSenderDisplayName() {
    final rawName = widget.room.localParticipant?.getAttribute("name");
    if (rawName is! String) {
      return null;
    }

    final trimmedName = rawName.trim();
    if (trimmedName.isEmpty) {
      return null;
    }

    return trimmedName.split("@").first.trim();
  }

  DateTime _pendingCreatedAt() {
    return _creatingNewThreadStartedAt ?? DateTime.now();
  }

  String _chatPlaceholderText() {
    final normalizedAgentName = widget.agentName.trim();
    if (normalizedAgentName.isEmpty) {
      return "Type a message";
    }

    return "Type a message or @$normalizedAgentName";
  }

  void _notifyThreadPathChanged() {
    widget.onThreadPathChanged?.call(_threadPath);
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _roomSubscription = widget.room.listen(_onRoomEvent);
    widget.room.messaging.addListener(_onMessagingChanged);
    _onMessagingChanged();
  }

  @override
  void didUpdateWidget(covariant NewChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      _creatingNewThreadStartedAt = null;
      _cancelWaitingForAgent();
      _onMessagingChanged();
    }

    if (oldWidget.agentName != widget.agentName) {
      _newThreadOperationId++;
      _threadPath = null;
      _newThreadError = null;
      _creatingNewThread = false;
      _waitingForAgent = false;
      _creatingNewThreadStartedAt = null;
      _pendingMessageText = null;
      _pendingAttachmentPaths = const [];
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

  Future<void> _waitForThreadCreated({required String path}) async {
    for (var i = 0; i < 50; i++) {
      try {
        if (await widget.room.storage.exists(path)) {
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
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

    FocusManager.instance.primaryFocus?.unfocus();
    final operationId = ++_newThreadOperationId;
    final waitingForAgent = _agent == null;
    setState(() {
      _creatingNewThread = !waitingForAgent;
      _waitingForAgent = waitingForAgent;
      _creatingNewThreadStartedAt = waitingForAgent ? null : DateTime.now();
      _newThreadError = null;
      _pendingMessageText = prompt;
      _pendingAttachmentPaths = attachmentPaths;
    });
    _controller.clear();

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
          _creatingNewThreadStartedAt = DateTime.now();
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

      await _waitForThreadCreated(path: path);

      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }

      _controller.clear();
      setState(() {
        _threadPath = path;
        _newThreadError = null;
        _creatingNewThread = false;
        _waitingForAgent = false;
        _creatingNewThreadStartedAt = null;
      });
      _notifyThreadPathChanged();
    } on ChatSendCancelledException {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      _restoreDraft(text: prompt, attachmentPaths: attachmentPaths);
      setState(() {
        _creatingNewThread = false;
        _waitingForAgent = false;
        _creatingNewThreadStartedAt = null;
        _pendingMessageText = null;
        _pendingAttachmentPaths = const [];
        _newThreadError = null;
      });
    } catch (e) {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      _restoreDraft(text: prompt, attachmentPaths: attachmentPaths);
      setState(() {
        _creatingNewThread = false;
        _waitingForAgent = false;
        _creatingNewThreadStartedAt = null;
        _pendingMessageText = null;
        _pendingAttachmentPaths = const [];
        _newThreadError = "$e";
      });
    }
  }

  void _restoreDraft({required String text, required List<String> attachmentPaths}) {
    _controller.textFieldController.text = text;
    final existingAttachments = _controller.attachmentUploads.map((attachment) => attachment.path).toSet();
    for (final path in attachmentPaths) {
      if (!existingAttachments.contains(path)) {
        _controller.attachFile(path);
      }
    }
  }

  Widget _buildPendingAttachmentPreviews() {
    if (_pendingAttachmentPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final path in _pendingAttachmentPaths)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              margin: const EdgeInsets.only(top: 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: ChatThreadPreview(room: widget.room, path: path),
              ),
            ),
          ),
      ],
    );
  }

  void _cancelPendingNewThread() {
    if (!_creatingNewThread && !_waitingForAgent) {
      return;
    }

    _newThreadOperationId++;
    _cancelWaitingForAgent();
    final pendingText = _pendingMessageText ?? "";
    final pendingAttachmentPaths = [for (final path in _pendingAttachmentPaths) path];
    _restoreDraft(text: pendingText, attachmentPaths: pendingAttachmentPaths);

    setState(() {
      _creatingNewThread = false;
      _waitingForAgent = false;
      _creatingNewThreadStartedAt = null;
      _newThreadError = null;
      _pendingMessageText = null;
      _pendingAttachmentPaths = const [];
    });
  }

  void _goToNewMessageScreen() {
    if (_creatingNewThread) {
      _cancelPendingNewThread();
      return;
    }
    if (_threadPath == null) {
      return;
    }
    setState(() {
      _threadPath = null;
      _newThreadError = null;
      _waitingForAgent = false;
      _creatingNewThreadStartedAt = null;
      _pendingMessageText = null;
      _pendingAttachmentPaths = const [];
    });
    _notifyThreadPathChanged();
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

  Widget _buildPendingThreadView({required bool allowCancel}) {
    final snapshot = _buildSnapshot();
    final toolsBuilder = widget.toolsBuilder;
    final toolArea = resolveChatThreadToolArea(toolsBuilder == null ? null : toolsBuilder(context, _controller, snapshot));
    final pendingText = _pendingMessageText;
    final pendingSenderDisplayName = _pendingSenderDisplayName();
    final pendingCreatedAt = _pendingCreatedAt();
    final hasPendingContent = (pendingText != null && pendingText.isNotEmpty) || _pendingAttachmentPaths.isNotEmpty;
    final pendingMessage = hasPendingContent
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (pendingSenderDisplayName != null)
                Padding(
                  padding: const EdgeInsets.only(left: 85, right: 5, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ChatThreadAuthorHeader(authorName: pendingSenderDisplayName, createdAt: pendingCreatedAt, text: pendingText),
                  ),
                ),
              if (pendingText != null && pendingText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: ChatBubble(mine: true, text: pendingText),
                ),
              if (_pendingAttachmentPaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Container(margin: const EdgeInsets.only(top: 0), child: _buildPendingAttachmentPreviews()),
                ),
            ],
          )
        : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: ChatThreadViewportBody(
            bottomAlign: true,
            bottomSpacer: 20,
            overlays: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: chatThreadStatusHorizontalPadding(constraints.maxWidth)),
                    child: ChatThreadProcessingStatusRow(
                      key: _sendingStatusKey,
                      text: "Sending message",
                      startedAt: _creatingNewThreadStartedAt,
                      onCancel: allowCancel ? _cancelPendingNewThread : null,
                    ),
                  ),
                ),
              ),
            ],
            children: [if (pendingMessage != null) pendingMessage],
          ),
        ),
        ChatThreadInputFrame(
          child: IgnorePointer(
            ignoring: true,
            child: Opacity(
              opacity: 0.6,
              child: ChatThreadInput(
                room: widget.room,
                controller: _controller,
                autoFocus: false,
                leading: toolArea.leading,
                footer: toolArea.footer,
                trailing: null,
                onSend: (text, attachments) async {
                  if (text.isNotEmpty || attachments.isNotEmpty) {
                    return;
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = switch ((_threadPath, _creatingNewThread)) {
      (final threadPath?, _) => widget.builder(context, threadPath, (context) => _buildPendingThreadView(allowCancel: false)),
      (_, true) => _buildPendingThreadView(allowCancel: true),
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
      room: widget.room,
      controller: _controller,
      sendEnabled: !_creatingNewThread && !_waitingForAgent,
      sendDisabledReason: _waitingForAgent ? "Waiting for ${widget.agentName} to be ready." : "Wait for the message to be accepted.",
      sendPendingText: _waitingForAgent ? "Waiting for ${widget.agentName} to be ready." : null,
      onCancelSend: _waitingForAgent ? _cancelPendingNewThread : null,
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
                    ] else ...[
                      // Reserve matching space below the composer so the heading above
                      // doesn't visually push the input downward in the centered state.
                      Opacity(opacity: 0, child: Text("Start a new thread", style: headingStyle)),
                    ],
                  ],
                ),
              ),
            ),
          );

    return _buildComposerDropArea(child: content);
  }
}
