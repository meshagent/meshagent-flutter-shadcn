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
    this.toolkit = "chat",
    this.tool = "new_thread",
    this.toolsBuilder,
    this.onThreadPathChanged,
  });

  final RoomClient room;
  final String agentName;
  final NewChatThreadBuilder builder;
  final String toolkit;
  final String tool;
  final NewChatThreadToolsBuilder? toolsBuilder;
  final ValueChanged<String?>? onThreadPathChanged;

  @override
  State<NewChatThread> createState() => _NewChatThreadState();
}

class _NewChatThreadState extends State<NewChatThread> {
  static const _toolProviderProbePath = ".new-thread";

  late ChatThreadController _controller;
  StreamSubscription<RoomEvent>? _roomSubscription;
  RemoteParticipant? _agent;
  List<ThreadToolkitBuilder> _availableTools = const [];
  String? _requestedToolProvidersFromParticipantId;
  bool _creatingNewThread = false;
  String? _newThreadError;
  String? _threadPath;
  String? _pendingMessageText;
  List<String> _pendingAttachmentPaths = const [];
  int _newThreadOperationId = 0;
  final GlobalKey _sendingStatusKey = GlobalKey();

  void _notifyThreadPathChanged() {
    widget.onThreadPathChanged?.call(_threadPath);
  }

  @override
  void initState() {
    super.initState();
    _controller = ChatThreadController(room: widget.room);
    _roomSubscription = widget.room.listen(_onRoomEvent);
    widget.room.messaging.addListener(_onMessagingChanged);
    _onMessagingChanged();
  }

  @override
  void didUpdateWidget(covariant NewChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      _newThreadOperationId++;
      _roomSubscription?.cancel();
      _roomSubscription = widget.room.listen(_onRoomEvent);
      oldWidget.room.messaging.removeListener(_onMessagingChanged);
      widget.room.messaging.addListener(_onMessagingChanged);

      _controller.dispose();
      _controller = ChatThreadController(room: widget.room);
      _availableTools = const [];
      _requestedToolProvidersFromParticipantId = null;
      _onMessagingChanged();
    }

    if (oldWidget.agentName != widget.agentName) {
      _newThreadOperationId++;
      _threadPath = null;
      _newThreadError = null;
      _creatingNewThread = false;
      _pendingMessageText = null;
      _pendingAttachmentPaths = const [];
      _availableTools = const [];
      _requestedToolProvidersFromParticipantId = null;
      _controller.clear();
      _onMessagingChanged();
    }
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    widget.room.messaging.removeListener(_onMessagingChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is! RoomMessageEvent || event.message.type != "set_thread_tool_providers") {
      return;
    }

    final providers = event.message.message["tool_providers"];
    if (providers is! List) {
      return;
    }

    final nextTools = <ThreadToolkitBuilder>[];
    for (final provider in providers) {
      if (provider is Map && provider["name"] is String) {
        nextTools.add(ThreadToolkitBuilder(name: provider["name"] as String));
      }
    }

    final changed =
        nextTools.length != _availableTools.length || nextTools.indexed.any((entry) => entry.$2.name != _availableTools[entry.$1].name);
    if (!changed || !mounted) {
      return;
    }

    setState(() {
      _availableTools = nextTools;
    });
  }

  Future<void> _requestToolProviders() async {
    final agent = _agent;
    if (agent == null) {
      return;
    }
    if (_requestedToolProvidersFromParticipantId == agent.id) {
      return;
    }

    _requestedToolProvidersFromParticipantId = agent.id;
    try {
      await widget.room.messaging.sendMessage(to: agent, type: "get_thread_toolkit_builders", message: {"path": _toolProviderProbePath});
    } catch (_) {}
  }

  void _onMessagingChanged() {
    if (!mounted) {
      return;
    }

    final nextAgent = widget.room.messaging.remoteParticipants.firstWhereOrNull(
      (participant) => participant.getAttribute("name") == widget.agentName,
    );
    if (nextAgent == _agent) {
      unawaited(_requestToolProviders());
      return;
    }

    setState(() {
      _agent = nextAgent;
      if (nextAgent == null) {
        _availableTools = const [];
        _requestedToolProvidersFromParticipantId = null;
      }
    });

    unawaited(_requestToolProviders());
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
    if (_creatingNewThread || _agent == null || hasPendingUploads) {
      return;
    }
    if (prompt.isEmpty && attachments.isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final operationId = ++_newThreadOperationId;
    setState(() {
      _creatingNewThread = true;
      _newThreadError = null;
      _pendingMessageText = prompt;
      _pendingAttachmentPaths = attachmentPaths;
    });
    _controller.clear();

    try {
      final tools = <Map<String, dynamic>>[];
      for (final toolkit in _controller.toolkits) {
        tools.add((await toolkit.build(widget.room)).toJson());
      }

      final result = await widget.room.agents.invokeTool(
        toolkit: widget.toolkit,
        tool: widget.tool,
        participantId: _agent!.id,
        input: ToolContentInput(
          JsonContent(
            json: {
              "message": {
                "text": prompt,
                "attachments": [
                  for (final path in attachmentPaths) {"path": path},
                ],
                if (tools.isNotEmpty) "tools": tools,
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
      });
      _notifyThreadPathChanged();
    } catch (e) {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      _restoreDraft(text: prompt, attachmentPaths: attachmentPaths);
      setState(() {
        _creatingNewThread = false;
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
    if (!_creatingNewThread) {
      return;
    }

    _newThreadOperationId++;
    final pendingText = _pendingMessageText ?? "";
    final pendingAttachmentPaths = [for (final path in _pendingAttachmentPaths) path];
    _restoreDraft(text: pendingText, attachmentPaths: pendingAttachmentPaths);

    setState(() {
      _creatingNewThread = false;
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
      availableTools: _availableTools,
      agentOnline: _agent != null,
      threadStatus: null,
      threadStatusMode: null,
    );
  }

  Widget _buildPendingThreadView({required bool allowCancel}) {
    final snapshot = _buildSnapshot();
    final toolsBuilder = widget.toolsBuilder;
    final pendingText = _pendingMessageText;
    final hasPendingContent = (pendingText != null && pendingText.isNotEmpty) || _pendingAttachmentPaths.isNotEmpty;
    final pendingMessage = hasPendingContent
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      text: "Sending",
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
                leading: toolsBuilder == null
                    ? null
                    : _controller.toolkits.isNotEmpty
                    ? null
                    : toolsBuilder(context, _controller, snapshot),
                footer: toolsBuilder == null
                    ? null
                    : _controller.toolkits.isEmpty
                    ? null
                    : Padding(padding: const EdgeInsets.only(top: 8), child: toolsBuilder(context, _controller, snapshot)),
                trailing: null,
                onSend: (text, attachments) {},
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

  Widget _buildNewThreadComposer(BuildContext context) {
    final snapshot = _buildSnapshot();
    final toolsBuilder = widget.toolsBuilder;
    final headingStyle = ShadTheme.of(context).textTheme.h4;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 912),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Text("Start a new thread", style: headingStyle),
              ChatThreadInput(
                room: widget.room,
                controller: _controller,
                placeholder: Text(_agent == null ? "Waiting for @${widget.agentName} to come online..." : "Send the first message"),
                leading: toolsBuilder == null
                    ? null
                    : _controller.toolkits.isNotEmpty
                    ? null
                    : toolsBuilder(context, _controller, snapshot),
                footer: toolsBuilder == null
                    ? null
                    : _controller.toolkits.isEmpty
                    ? null
                    : Padding(padding: const EdgeInsets.only(top: 8), child: toolsBuilder(context, _controller, snapshot)),
                trailing: null,
                onSend: (value, attachments) {
                  if (_agent != null && !_creatingNewThread) {
                    _startNewThread();
                  }
                },
              ),
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
  }
}
