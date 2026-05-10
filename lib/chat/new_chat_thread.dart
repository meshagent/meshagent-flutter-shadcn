import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'dataset_chat_thread.dart';

const String _agentRoomMessageType = "agent-message";
const String _agentThreadStartType = "meshagent.agent.thread.start";
const String _agentThreadStartedType = "meshagent.agent.thread.started";
const String _agentTurnStartRejectedType = "meshagent.agent.turn.start.rejected";
const String _agentTurnStartType = "meshagent.agent.turn.start";
const String _agentRealtimeAudioChunkType = "meshagent.agent.realtime_audio.chunk";
const String _agentRealtimeAudioCommitType = "meshagent.agent.realtime_audio.commit";
const String _agentModelsRequestType = "meshagent.agent.models.request";
const String _agentModelsResponseType = "meshagent.agent.models.response";
const String _agentModelChangedType = "meshagent.agent.model.changed";

typedef NewChatThreadBuilder = Widget Function(BuildContext context, String threadPath);
typedef NewChatThreadToolsBuilder = Widget Function(BuildContext context, ChatThreadController controller, ChatThreadSnapshot state);
typedef NewChatThreadWrapperBuilder = Widget Function(BuildContext context, Widget newThread, DatasetChatModelController modelController);

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
    this.showUsageFooter = false,
    this.emptyState,
    this.inputPlaceholder,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.modelController,
    this.newThreadWrapperBuilder,
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
  final bool showUsageFooter;
  final Widget? emptyState;
  final Widget? inputPlaceholder;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final DatasetChatModelController? modelController;
  final NewChatThreadWrapperBuilder? newThreadWrapperBuilder;

  @override
  State<NewChatThread> createState() => _NewChatThreadState();
}

class _NewChatThreadState extends State<NewChatThread> {
  late ChatThreadController _controller;
  late Key _composerInputKey;
  late bool _ownsController;
  late DatasetChatModelController _modelController;
  late bool _ownsModelController;
  StreamSubscription<RoomEvent>? _roomSubscription;
  RemoteParticipant? _agent;
  bool _creatingNewThread = false;
  bool _waitingForAgent = false;
  String? _newThreadError;
  String? _threadPath;
  String? _realtimeAudioThreadPath;
  Completer<String>? _realtimeAudioThreadCompleter;
  PendingAgentMessage? _pendingFirstMessage;
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

  Widget _buildUsageFooter(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      "",
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.small.copyWith(color: theme.colorScheme.mutedForeground, fontSize: 11),
    );
  }

  Widget _buildComposerWithUsageFooter(BuildContext context, Widget input) {
    if (!widget.showUsageFooter) {
      return input;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, right: 8),
          child: Align(alignment: Alignment.centerRight, child: _buildUsageFooter(context)),
        ),
      ],
    );
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
    _ownsModelController = widget.modelController == null;
    _modelController = widget.modelController ?? DatasetChatModelController();
    _modelController.bindChangeHandler(_selectModelForNewThread);
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
      _pendingFirstMessage = null;
      _creatingNewThread = false;
      _waitingForAgent = false;
      _cancelWaitingForAgent();
      _onMessagingChanged();
    }

    if (oldWidget.modelController != widget.modelController) {
      _modelController.unbindChangeHandler();
      if (_ownsModelController) {
        _modelController.dispose();
      }
      _ownsModelController = widget.modelController == null;
      _modelController = widget.modelController ?? DatasetChatModelController();
      _modelController.bindChangeHandler(_selectModelForNewThread);
      _requestModels();
    }

    if (oldWidget.agentName != widget.agentName) {
      _newThreadOperationId++;
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
      _threadPath = null;
      _newThreadError = null;
      _pendingFirstMessage = null;
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
    _resetRealtimeAudioThreadState();
    _cancelWaitingForAgent();
    if (_ownsController) {
      _controller.dispose();
    }
    _modelController.unbindChangeHandler();
    if (_ownsModelController) {
      _modelController.dispose();
    }
    super.dispose();
  }

  void _resetRealtimeAudioThreadState() {
    _realtimeAudioThreadPath = null;
    final completer = _realtimeAudioThreadCompleter;
    _realtimeAudioThreadCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const ChatSendCancelledException());
    }
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is! RoomMessageEvent) {
      return;
    }
    if (event.message.type == _agentRoomMessageType && event.message.fromParticipantId == _agent?.id) {
      final message = event.message.message;
      final rawPayload = message["type"] is String ? message : message["payload"];
      final payload = rawPayload is Map<String, dynamic>
          ? rawPayload
          : rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : null;
      if (payload != null) {
        if (payload["type"] == _agentModelsResponseType) {
          _modelController.applyModelsResponse(payload);
        } else if (payload["type"] == _agentModelChangedType && payload["thread_id"] == null) {
          _modelController.applyModelChanged(payload);
        }
      }
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
    _requestModels();

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

  Future<void> _selectModelForNewThread(DatasetChatModelOption option) async {
    _modelController.selectModelLocally(option);
  }

  void _requestModels() {
    final agent = _agent;
    if (agent == null) {
      return;
    }
    unawaited(() async {
      try {
        await widget.room.messaging.sendMessage(
          to: agent,
          type: _agentRoomMessageType,
          ignoreOffline: true,
          message: {"type": _agentModelsRequestType, "message_id": const Uuid().v4()},
        );
      } catch (_) {}
    }());
  }

  List<Map<String, Object?>> _agentInputContent({required String text, required List<String> attachments}) {
    return [
      if (text.trim().isNotEmpty) {"type": "text", "text": text},
      for (final attachment in attachments)
        if (attachment.trim().isNotEmpty) {"type": "file", "url": attachment},
    ];
  }

  Future<String> _sendStartThreadMessage({
    required RemoteParticipant agent,
    required String messageId,
    required String text,
    required List<String> attachments,
    required String? senderName,
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription<RoomEvent> subscription;
    subscription = widget.room.listen((event) {
      if (event is! RoomMessageEvent || event.message.fromParticipantId != agent.id || event.message.type != _agentRoomMessageType) {
        return;
      }
      final rawMessage = event.message.message;
      final rawPayload = rawMessage["type"] is String ? rawMessage : rawMessage["payload"];
      if (rawPayload is! Map) {
        return;
      }
      if (rawPayload["source_message_id"] != messageId) {
        return;
      }
      if (rawPayload["type"] == _agentThreadStartedType) {
        final threadId = rawPayload["thread_id"];
        if (threadId is String && threadId.trim().isNotEmpty && !completer.isCompleted) {
          completer.complete(threadId.trim());
        }
      } else if (rawPayload["type"] == _agentTurnStartRejectedType && !completer.isCompleted) {
        final error = rawPayload["error"];
        final message = error is Map ? error["message"] : null;
        completer.completeError(
          RoomServerException(message is String && message.trim().isNotEmpty ? message.trim() : "Thread start rejected."),
        );
      }
    });

    try {
      final payload = <String, Object?>{
        "type": _agentThreadStartType,
        "message_id": messageId,
        "content": _agentInputContent(text: text, attachments: attachments),
      };
      final activeModel = _modelController.activeModel;
      if (activeModel != null) {
        payload["provider"] = activeModel.provider;
        payload["model"] = activeModel.model;
      }
      payload["output_modalities"] = [_modelController.activeModality];
      if (senderName != null && senderName.trim().isNotEmpty) {
        payload["sender_name"] = senderName.trim();
      }
      await widget.room.messaging.sendMessage(to: agent, type: _agentRoomMessageType, message: payload);
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw RoomServerException("Timed out waiting for thread to start.");
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> _sendRealtimeAudioThreadStartMessage({
    required RemoteParticipant agent,
    required String messageId,
    required String? senderName,
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription<RoomEvent> subscription;
    subscription = widget.room.listen((event) {
      if (event is! RoomMessageEvent || event.message.fromParticipantId != agent.id || event.message.type != _agentRoomMessageType) {
        return;
      }
      final rawMessage = event.message.message;
      final rawPayload = rawMessage["type"] is String ? rawMessage : rawMessage["payload"];
      if (rawPayload is! Map || rawPayload["source_message_id"] != messageId) {
        return;
      }
      if (rawPayload["type"] == _agentThreadStartedType) {
        final threadId = rawPayload["thread_id"];
        if (threadId is String && threadId.trim().isNotEmpty && !completer.isCompleted) {
          completer.complete(threadId.trim());
        }
      } else if (rawPayload["type"] == _agentTurnStartRejectedType && !completer.isCompleted) {
        final error = rawPayload["error"];
        final message = error is Map ? error["message"] : null;
        completer.completeError(
          RoomServerException(message is String && message.trim().isNotEmpty ? message.trim() : "Thread start rejected."),
        );
      }
    });

    try {
      final payload = <String, Object?>{"type": _agentThreadStartType, "message_id": messageId, "content": const <Object?>[]};
      final activeModel = _modelController.activeModel;
      if (activeModel != null) {
        payload["provider"] = activeModel.provider;
        payload["model"] = activeModel.model;
      }
      payload["output_modalities"] = [_modelController.activeModality];
      if (senderName != null && senderName.trim().isNotEmpty) {
        payload["sender_name"] = senderName.trim();
      }
      await widget.room.messaging.sendMessage(to: agent, type: _agentRoomMessageType, message: payload);
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw RoomServerException("Timed out waiting for thread to start.");
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> _ensureRealtimeAudioThread() async {
    final existingPath = _realtimeAudioThreadPath;
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      return existingPath;
    }
    final existingCompleter = _realtimeAudioThreadCompleter;
    if (existingCompleter != null) {
      return existingCompleter.future;
    }

    final completer = Completer<String>();
    _realtimeAudioThreadCompleter = completer;
    try {
      final agent = _agent ?? await _waitForAgentOnline();
      final senderName = widget.room.localParticipant?.getAttribute("name");
      final path = await _sendRealtimeAudioThreadStartMessage(
        agent: agent,
        messageId: const Uuid().v4(),
        senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
      );
      _realtimeAudioThreadPath = path;
      if (!completer.isCompleted) {
        completer.complete(path);
      }
      return path;
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      rethrow;
    } finally {
      if (_realtimeAudioThreadCompleter == completer) {
        _realtimeAudioThreadCompleter = null;
      }
    }
  }

  Future<void> _sendRealtimeAudioChunk(Uint8List chunk, {required bool finalChunk}) async {
    try {
      final path = await _ensureRealtimeAudioThread();
      final agent = _agent ?? await _waitForAgentOnline();
      final activeModel = _modelController.activeModel;
      if (finalChunk) {
        await widget.room.messaging.sendMessage(
          to: agent,
          type: _agentRoomMessageType,
          message: {
            "type": _agentRealtimeAudioCommitType,
            "thread_id": path,
            "message_id": const Uuid().v4(),
            if (activeModel != null) "provider": activeModel.provider,
            if (activeModel != null) "model": activeModel.model,
            "output_modalities": [_modelController.activeModality],
          },
        );
        if (!mounted) {
          return;
        }
        _realtimeAudioThreadPath = null;
        setState(() {
          _threadPath = path;
          _newThreadError = null;
          _creatingNewThread = false;
          _waitingForAgent = false;
          _pendingFirstMessage = null;
        });
        _modelController.setLocked(false);
        _notifyThreadResolved(path, null);
        _notifyThreadPathChanged(path);
        _controller.clear();
        return;
      }
      await widget.room.messaging.sendMessage(
        to: agent,
        type: _agentRoomMessageType,
        message: {
          "type": _agentRealtimeAudioChunkType,
          "thread_id": path,
          "message_id": const Uuid().v4(),
          if (activeModel != null) "provider": activeModel.provider,
          if (activeModel != null) "model": activeModel.model,
          "mime_type": "audio/pcm",
          "sample_rate": 24000,
        },
        attachment: chunk,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _newThreadError = "$error";
      });
    }
  }

  Future<void> _startNewThread() async {
    final prompt = _controller.text.trim();
    final attachments = _controller.attachmentUploads;
    final attachmentPaths = [for (final attachment in attachments) attachment.path];
    final pendingMessageId = const Uuid().v4();
    final pendingCreatedAt = DateTime.now();
    final hasPendingUploads = attachments.any((attachment) => attachment.status != UploadStatus.completed);
    if (_creatingNewThread || _waitingForAgent || hasPendingUploads) {
      return;
    }
    if (prompt.isEmpty && attachments.isEmpty) {
      return;
    }

    final operationId = ++_newThreadOperationId;
    final waitingForAgent = _agent == null;
    final senderName = widget.room.localParticipant?.getAttribute("name");
    final pendingFirstMessage = PendingAgentMessage(
      messageId: pendingMessageId,
      messageType: _agentTurnStartType,
      threadPath: "",
      text: prompt,
      attachments: attachmentPaths,
      senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
      createdAt: pendingCreatedAt,
      matchByContentOnly: true,
      awaitingAcceptance: true,
      awaitingOnline: waitingForAgent,
    );
    setState(() {
      _creatingNewThread = !waitingForAgent;
      _waitingForAgent = waitingForAgent;
      _newThreadError = null;
      _pendingFirstMessage = pendingFirstMessage;
    });
    _modelController.setLocked(true);
    _controller.scrollThreadToBottom(animated: false);

    try {
      final agent = _agent ?? await _waitForAgentOnline();
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

      final path = await _sendStartThreadMessage(
        agent: readyAgent,
        messageId: pendingFirstMessage.messageId,
        text: prompt,
        attachments: attachmentPaths,
        senderName: pendingFirstMessage.senderName,
      );
      final messageId = pendingFirstMessage.messageId;
      final threadName = null;
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }

      final resolvedPendingMessage = PendingAgentMessage(
        messageId: messageId,
        messageType: pendingFirstMessage.messageType,
        threadPath: path,
        text: pendingFirstMessage.text,
        attachments: pendingFirstMessage.attachments,
        senderName: pendingFirstMessage.senderName,
        createdAt: pendingFirstMessage.createdAt,
        matchByContentOnly: false,
        awaitingAcceptance: pendingFirstMessage.awaitingAcceptance,
      );
      _controller.markPendingAgentMessage(resolvedPendingMessage);

      final defersToParent = widget.onThreadPathChanged != null || widget.onThreadResolved != null;
      setState(() {
        _threadPath = defersToParent ? null : path;
        _newThreadError = null;
        _creatingNewThread = false;
        _waitingForAgent = false;
        _pendingFirstMessage = defersToParent ? resolvedPendingMessage : null;
      });
      _modelController.setLocked(false);
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
        _pendingFirstMessage = null;
      });
      _modelController.setLocked(false);
    } catch (e) {
      if (!mounted || operationId != _newThreadOperationId) {
        return;
      }
      setState(() {
        _creatingNewThread = false;
        _waitingForAgent = false;
        _newThreadError = "$e";
        _pendingFirstMessage = null;
      });
      _modelController.setLocked(false);
    }
  }

  void _cancelPendingNewThread() {
    if (!_creatingNewThread && !_waitingForAgent) {
      return;
    }

    _newThreadOperationId++;
    _cancelWaitingForAgent();
    _resetRealtimeAudioThreadState();

    setState(() {
      _creatingNewThread = false;
      _waitingForAgent = false;
      _newThreadError = null;
      _pendingFirstMessage = null;
    });
    _modelController.setLocked(false);
  }

  void _goToNewMessageScreen() {
    if (_creatingNewThread || _waitingForAgent) {
      _cancelPendingNewThread();
      return;
    }
    if (_activeThreadPath == null) {
      return;
    }
    _resetRealtimeAudioThreadState();
    setState(() {
      _threadPath = null;
      _newThreadError = null;
      _waitingForAgent = false;
      _pendingFirstMessage = null;
    });
    _notifyThreadResolved(null, null);
    _notifyThreadPathChanged(null);
    _controller.clear();
    _controller.resetThreadScrollPosition();
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
      threadStatusTotalBytes: null,
      threadStatusLinesAdded: null,
      threadStatusLinesRemoved: null,
      supportsAgentMessages: _agent?.getAttribute("supports_agent_messages") == true,
      supportsMcp: _agent?.getAttribute("supports_mcp") == true,
      toolkits: const {},
      threadTurnId: null,
      pendingMessages: const [],
      pendingItemId: null,
      usage: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeThreadPath = _activeThreadPath;
    var content = switch (activeThreadPath) {
      final threadPath? => widget.builder(context, threadPath),
      _ => _buildNewThreadComposer(context),
    };
    if (activeThreadPath == null && widget.newThreadWrapperBuilder != null) {
      content = widget.newThreadWrapperBuilder!(context, content, _modelController);
    }

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

  Widget _buildNewThreadFeedArea(BuildContext context) {
    final pendingMessage = _pendingFirstMessage;
    if (pendingMessage == null) {
      return Expanded(child: Center(child: widget.emptyState ?? const SizedBox.shrink()));
    }

    return ChatThreadMessages(
      room: widget.room,
      path: pendingMessage.threadPath,
      scrollController: _controller.threadScrollController,
      messages: const [],
      online: _agent == null ? const [] : [_agent!],
      showCompletedToolCalls: false,
      pendingMessages: [pendingMessage],
    );
  }

  Widget _buildNewThreadComposer(BuildContext context) {
    final snapshot = _buildSnapshot();
    final toolsBuilder = widget.toolsBuilder;
    final toolArea = resolveChatThreadToolArea(toolsBuilder == null ? null : toolsBuilder(context, _controller, snapshot));
    final headingStyle = ShadTheme.of(context).textTheme.h4;
    final input = AnimatedBuilder(
      animation: _modelController,
      builder: (context, _) => ChatThreadInput(
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
        placeholder: widget.inputPlaceholder,
        leading: toolArea.leading,
        footer: toolArea.footer,
        trailing: null,
        audioInputEnabled: _modelController.supportsAudioInput,
        onAudioChunk: _sendRealtimeAudioChunk,
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
      ),
    );
    final composer = _buildComposerWithUsageFooter(context, input);

    final content = !widget.centerComposer
        ? Column(
            children: [
              _buildNewThreadFeedArea(context),
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
              ChatThreadInputFrame(hasFooter: widget.showUsageFooter, child: composer),
            ],
          )
        : _pendingFirstMessage != null
        ? Column(
            children: [
              _buildNewThreadFeedArea(context),
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
              ChatThreadInputFrame(hasFooter: widget.showUsageFooter, child: composer),
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
                    composer,
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
