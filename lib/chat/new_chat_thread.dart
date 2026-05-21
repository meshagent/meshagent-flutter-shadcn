import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart'
    show
        AgentMessage,
        AgentMessageEvent,
        BaseChatClient,
        ModelsRequest,
        StartThread,
        ThreadStarted,
        ThreadStartRejected,
        agentInputContent,
        agentModelChangedType,
        agentModelsResponseType,
        agentRealtimeAudioChunkType,
        agentRealtimeAudioCommitType,
        agentRoomMessageType,
        agentTurnStartType;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'dataset_chat_thread.dart';
import 'realtime_webrtc_session.dart';

typedef NewChatThreadBuilder = Widget Function(BuildContext context, String threadPath);
typedef NewChatThreadToolsBuilder = Widget Function(BuildContext context, ChatThreadController controller, ChatThreadSnapshot state);
typedef NewChatThreadWrapperBuilder = Widget Function(BuildContext context, Widget newThread, DatasetChatModelController modelController);

class NewChatThread extends StatefulWidget {
  const NewChatThread({
    super.key,
    required this.agentName,
    required this.builder,
    this.room,
    this.chatClient,
    this.disposeChatClient = false,
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

  final RoomClient? room;
  final BaseChatClient? chatClient;
  final bool disposeChatClient;
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
  StreamSubscription<AgentMessageEvent>? _chatClientSubscription;
  RemoteParticipant? _agent;
  bool _creatingNewThread = false;
  bool _waitingForAgent = false;
  String? _newThreadError;
  String? _threadPath;
  String? _realtimeAudioThreadPath;
  RealtimeConnectionInfo? _realtimeAudioConnection;
  final RealtimeWebrtcSession _realtimeWebrtcSession = RealtimeWebrtcSession();
  Completer<String>? _realtimeAudioThreadCompleter;
  PendingAgentMessage? _pendingFirstMessage;
  int _newThreadOperationId = 0;
  Completer<RemoteParticipant>? _waitForAgentCompleter;
  Completer<void>? _waitForAgentReadyCompleter;

  bool get _composerLocked => _creatingNewThread || _waitingForAgent;

  bool get _usesInjectedChatClient => widget.chatClient != null;

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

  String? _localSenderName() {
    final roomName = widget.room?.localParticipant?.getAttribute("name");
    if (roomName is String && roomName.trim().isNotEmpty) {
      return roomName.trim();
    }
    return widget.chatClient?.localParticipantName();
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _ownsModelController = widget.modelController == null;
    _modelController = widget.modelController ?? DatasetChatModelController();
    _modelController.bindChangeHandler(_selectModelForNewThread);
    _modelController.bindVoiceChangeHandler(_selectVoiceForNewThread);
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    _bindRoom();
    _bindChatClient();
    _onMessagingChanged();
  }

  @override
  void didUpdateWidget(covariant NewChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerKey != widget.composerKey) {
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    }

    if (oldWidget.room != widget.room || oldWidget.controller != widget.controller || oldWidget.chatClient != widget.chatClient) {
      _newThreadOperationId++;
      _roomSubscription?.cancel();
      oldWidget.room?.messaging.removeListener(_onMessagingChanged);
      _bindRoom();
      _bindChatClient();

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
      _modelController.bindVoiceChangeHandler(_selectVoiceForNewThread);
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
    _chatClientSubscription?.cancel();
    widget.room?.messaging.removeListener(_onMessagingChanged);
    if (widget.disposeChatClient) {
      unawaited(widget.chatClient?.stop());
    }
    unawaited(_realtimeWebrtcSession.stop());
    _resetRealtimeAudioThreadState();
    _cancelWaitingForAgent();
    if (_ownsController) {
      _controller.dispose();
    }
    _modelController.unbindChangeHandler();
    _modelController.unbindVoiceChangeHandler();
    if (_ownsModelController) {
      _modelController.dispose();
    }
    super.dispose();
  }

  void _bindRoom() {
    final room = widget.room;
    if (room == null) {
      _roomSubscription = null;
      _agent = null;
      return;
    }
    _roomSubscription = room.listen(_onRoomEvent);
    room.messaging.addListener(_onMessagingChanged);
  }

  void _bindChatClient() {
    _chatClientSubscription?.cancel();
    _chatClientSubscription = null;
    final chatClient = widget.chatClient;
    if (chatClient == null) {
      return;
    }
    _agent = null;
    unawaited(chatClient.start());
    _chatClientSubscription = chatClient.events.listen((event) {
      final payload = event.payload;
      if (payload["type"] == agentModelsResponseType) {
        _modelController.applyModelsResponse(payload);
      } else if (payload["type"] == agentModelChangedType && payload["thread_id"] == null) {
        _modelController.applyModelChanged(payload);
      }
      _signalWaitingForAgentReady();
    });
    _requestModels();
  }

  void _resetRealtimeAudioThreadState() {
    _realtimeAudioThreadPath = null;
    _realtimeAudioConnection = null;
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
    if (event.message.type == agentRoomMessageType && event.message.fromParticipantId == _agent?.id) {
      final message = event.message.message;
      final rawPayload = message["type"] is String ? message : message["payload"];
      final payload = rawPayload is Map<String, dynamic>
          ? rawPayload
          : rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : null;
      if (payload != null) {
        if (payload["type"] == agentModelsResponseType) {
          _modelController.applyModelsResponse(payload);
        } else if (payload["type"] == agentModelChangedType && payload["thread_id"] == null) {
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
    final room = widget.room;
    if (room == null) {
      _signalWaitingForAgentReady();
      return;
    }

    final nextAgent = room.messaging.remoteParticipants.firstWhereOrNull(
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

  Future<void> _selectVoiceForNewThread(String voice) async {
    _modelController.selectVoiceLocally(voice);
  }

  void _requestModels() {
    final chatClient = widget.chatClient;
    if (chatClient != null) {
      unawaited(() async {
        try {
          await chatClient.sendAgentMessage(ModelsRequest(messageId: const Uuid().v4()), ignoreOffline: true);
        } catch (_) {}
      }());
      return;
    }
    final room = widget.room;
    if (room == null) {
      return;
    }
    final agent = _agent;
    if (agent == null) {
      return;
    }
    unawaited(() async {
      try {
        await room.messaging.sendMessage(
          to: agent,
          type: agentRoomMessageType,
          ignoreOffline: true,
          message: ModelsRequest(messageId: const Uuid().v4()).toJson(),
        );
      } catch (_) {}
    }());
  }

  Future<String> _sendStartThreadMessage({
    required RemoteParticipant? agent,
    required String messageId,
    required String text,
    required List<AgentFileContent> attachments,
    required String? senderName,
  }) async {
    final clientToolkits = _controller.clientToolkitDescriptions;
    final chatClient = widget.chatClient;
    if (chatClient != null) {
      final activeModel = _modelController.activeModel;
      final activeVoice = _modelController.activeVoice;
      final result = await chatClient.startThread(
        messageId: messageId,
        message: text,
        attachments: attachments,
        provider: activeModel?.provider,
        model: activeModel?.model,
        realtimeProtocol: null,
        voice: activeVoice != null && activeVoice.trim().isNotEmpty ? activeVoice.trim() : null,
        outputModalities: [_modelController.activeModality],
        senderName: senderName,
        clientToolkits: clientToolkits.isEmpty ? null : clientToolkits,
      );
      _realtimeAudioConnection = RealtimeConnectionInfo.fromJson(result.realtimeConnection);
      return result.threadPath;
    }
    final room = widget.room;
    if (room == null) {
      throw StateError('Starting a room-backed thread requires a room.');
    }
    if (agent == null) {
      throw StateError('No online agent supports agent messages.');
    }
    final completer = Completer<String>();
    late final StreamSubscription<RoomEvent> subscription;
    subscription = room.listen((event) {
      if (event is! RoomMessageEvent || event.message.fromParticipantId != agent.id || event.message.type != agentRoomMessageType) {
        return;
      }
      final rawMessage = event.message.message;
      final rawPayload = rawMessage["type"] is String ? rawMessage : rawMessage["payload"];
      if (rawPayload is! Map) {
        return;
      }
      final payload = AgentMessage.fromJson(Map<String, dynamic>.from(rawPayload));
      if (payload is ThreadStarted && payload.sourceMessageId == messageId) {
        final threadId = payload.threadId.trim();
        if (threadId.isNotEmpty && !completer.isCompleted) {
          _realtimeAudioConnection = RealtimeConnectionInfo.fromJson(payload.realtimeConnection?.toJson());
          completer.complete(threadId);
        }
        return;
      }
      if (payload is ThreadStartRejected && payload.sourceMessageId == messageId && !completer.isCompleted) {
        completer.completeError(RoomServerException(payload.error.message));
      }
    });

    try {
      final activeModel = _modelController.activeModel;
      final activeVoice = _modelController.activeVoice;
      final payload = StartThread(
        messageId: messageId,
        content: agentInputContent(text: text, attachments: attachments),
        provider: activeModel?.provider,
        model: activeModel?.model,
        realtimeProtocol: _modelController.activeTurnDetection == "automatic" && _modelController.prefersWebrtcRealtime ? "webrtc" : null,
        voice: activeVoice != null && activeVoice.trim().isNotEmpty ? activeVoice.trim() : null,
        outputModalities: [_modelController.activeModality],
        clientToolkits: clientToolkits.isEmpty ? null : clientToolkits,
        senderName: senderName != null && senderName.trim().isNotEmpty ? senderName.trim() : null,
      );
      await room.messaging.sendMessage(to: agent, type: agentRoomMessageType, message: payload.toJson());
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw RoomServerException("Timed out waiting for thread to start.");
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> _sendRealtimeAudioThreadStartMessage({
    required RemoteParticipant? agent,
    required String messageId,
    required String? senderName,
  }) async {
    final chatClient = widget.chatClient;
    if (chatClient != null) {
      final activeModel = _modelController.activeModel;
      final activeVoice = _modelController.activeVoice;
      final result = await chatClient.startThread(
        messageId: messageId,
        message: "",
        attachments: const <AgentFileContent>[],
        name: "Audio message",
        provider: activeModel?.provider,
        model: activeModel?.model,
        realtimeProtocol: _modelController.activeTurnDetection == "automatic" && _modelController.prefersWebrtcRealtime ? "webrtc" : null,
        voice: activeVoice != null && activeVoice.trim().isNotEmpty ? activeVoice.trim() : null,
        outputModalities: [_modelController.activeModality],
        senderName: senderName,
        omitContent: true,
      );
      _realtimeAudioConnection = RealtimeConnectionInfo.fromJson(result.realtimeConnection);
      return result.threadPath;
    }
    final room = widget.room;
    if (room == null) {
      throw StateError('Realtime audio requires a room.');
    }
    if (agent == null) {
      throw StateError('No online agent supports agent messages.');
    }
    final completer = Completer<String>();
    late final StreamSubscription<RoomEvent> subscription;
    subscription = room.listen((event) {
      if (event is! RoomMessageEvent || event.message.fromParticipantId != agent.id || event.message.type != agentRoomMessageType) {
        return;
      }
      final rawMessage = event.message.message;
      final rawPayload = rawMessage["type"] is String ? rawMessage : rawMessage["payload"];
      if (rawPayload is! Map) {
        return;
      }
      final payload = AgentMessage.fromJson(Map<String, dynamic>.from(rawPayload));
      if (payload is ThreadStarted && payload.sourceMessageId == messageId) {
        final threadId = payload.threadId.trim();
        if (threadId.isNotEmpty && !completer.isCompleted) {
          _realtimeAudioConnection = RealtimeConnectionInfo.fromJson(payload.realtimeConnection?.toJson());
          completer.complete(threadId);
        }
      } else if (payload is ThreadStartRejected && payload.sourceMessageId == messageId && !completer.isCompleted) {
        completer.completeError(RoomServerException(payload.error.message));
      }
    });

    try {
      final activeModel = _modelController.activeModel;
      final activeVoice = _modelController.activeVoice;
      final payload = StartThread(
        messageId: messageId,
        content: null,
        name: "Audio message",
        provider: activeModel?.provider,
        model: activeModel?.model,
        realtimeProtocol: _modelController.activeTurnDetection == "automatic" && _modelController.prefersWebrtcRealtime ? "webrtc" : null,
        voice: activeVoice != null && activeVoice.trim().isNotEmpty ? activeVoice.trim() : null,
        outputModalities: [_modelController.activeModality],
        senderName: senderName != null && senderName.trim().isNotEmpty ? senderName.trim() : null,
      );
      await room.messaging.sendMessage(to: agent, type: agentRoomMessageType, message: payload.toJson());
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw RoomServerException("Timed out waiting for thread to start.");
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> _ensureRealtimeAudioThread({bool resolveWhenStarted = false}) async {
    final existingPath = _realtimeAudioThreadPath;
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      if (resolveWhenStarted) {
        _resolveRealtimeAudioThreadPath(existingPath);
      }
      return existingPath;
    }
    final existingCompleter = _realtimeAudioThreadCompleter;
    if (existingCompleter != null) {
      final path = await existingCompleter.future;
      if (resolveWhenStarted) {
        _resolveRealtimeAudioThreadPath(path);
      }
      return path;
    }

    final completer = Completer<String>();
    _realtimeAudioThreadCompleter = completer;
    try {
      final agent = _usesInjectedChatClient ? null : _agent ?? await _waitForAgentOnline();
      final senderName = _localSenderName();
      final path = await _sendRealtimeAudioThreadStartMessage(
        agent: agent,
        messageId: const Uuid().v4(),
        senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
      );
      _realtimeAudioThreadPath = path;
      if (resolveWhenStarted) {
        _resolveRealtimeAudioThreadPath(path);
      }
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

  Future<void> _startWebrtcRealtimeAudioThread() async {
    await _ensureRealtimeAudioThread(resolveWhenStarted: true);
    final connection = _realtimeAudioConnection;
    if (connection == null || connection.protocol != "webrtc") {
      throw RoomServerException("Realtime WebRTC is not available for this model.");
    }
    await _realtimeWebrtcSession.start(connection);
  }

  Future<void> _stopWebrtcRealtimeAudioThread() async {
    await _realtimeWebrtcSession.stop();
  }

  void _resolveRealtimeAudioThreadPath(String path) {
    if (!mounted) {
      return;
    }
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || _activeThreadPath == normalizedPath) {
      return;
    }
    setState(() {
      _threadPath = normalizedPath;
      _newThreadError = null;
      _creatingNewThread = false;
      _waitingForAgent = false;
      _pendingFirstMessage = null;
    });
    _modelController.setLocked(false);
    _notifyThreadResolved(normalizedPath, "Audio message");
    _notifyThreadPathChanged(normalizedPath);
  }

  Future<void> _sendRealtimeAudioChunk(Uint8List chunk, {required bool finalChunk}) async {
    try {
      final path = await _ensureRealtimeAudioThread();
      final activeModel = _modelController.activeModel;
      final activeVoice = _modelController.activeVoice;
      final inputFormat = _modelController.activeInputFormat;
      final chatClient = widget.chatClient;
      final session = chatClient?.openThread(path);
      if (finalChunk) {
        if (_modelController.activeTurnDetection == "automatic") {
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
        final messageId = const Uuid().v4();
        final turnId = const Uuid().v4();
        if (session != null) {
          await session.commitRealtimeAudio(
            turnId: turnId,
            provider: activeModel?.provider,
            model: activeModel?.model,
            voice: activeVoice,
            outputModalities: [_modelController.activeModality],
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
        final room = widget.room;
        if (room == null) {
          throw StateError('Realtime audio requires a room or chat client.');
        }
        final agent = _agent ?? await _waitForAgentOnline();
        await room.messaging.sendMessage(
          to: agent,
          type: agentRoomMessageType,
          message: {"type": agentRealtimeAudioCommitType, "thread_id": path, "message_id": messageId, "turn_id": turnId},
        );
        await room.messaging.sendMessage(
          to: agent,
          type: agentRoomMessageType,
          message: {
            "type": agentTurnStartType,
            "thread_id": path,
            "message_id": const Uuid().v4(),
            "turn_id": turnId,
            if (activeModel != null) "provider": activeModel.provider,
            if (activeModel != null) "model": activeModel.model,
            if (activeVoice != null && activeVoice.trim().isNotEmpty) "voice": activeVoice.trim(),
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
      if (session != null) {
        await session.sendRealtimeAudioChunk(chunk: chunk, format: inputFormat.toJson());
        return;
      }
      final room = widget.room;
      if (room == null) {
        throw StateError('Realtime audio requires a room or chat client.');
      }
      final agent = _agent ?? await _waitForAgentOnline();
      await room.messaging.sendMessage(
        to: agent,
        type: agentRoomMessageType,
        message: {"type": agentRealtimeAudioChunkType, "thread_id": path, "message_id": const Uuid().v4(), "format": inputFormat.toJson()},
        attachment: chunk,
      );
    } catch (error) {
      if (!mounted) {
        rethrow;
      }
      setState(() {
        _newThreadError = "$error";
      });
      rethrow;
    }
  }

  Future<void> _startNewThread() async {
    final prompt = _controller.text.trim();
    final attachments = _controller.attachmentUploads;
    final agentAttachments = attachments
        .map(
          (attachment) => AgentFileContent(
            url: attachment.path,
            name: attachment.displayName?.trim().isNotEmpty == true ? attachment.displayName!.trim() : null,
          ),
        )
        .toList(growable: false);
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
    final waitingForAgent = !_usesInjectedChatClient && _agent == null;
    final senderName = _localSenderName();
    final pendingFirstMessage = PendingAgentMessage(
      messageId: pendingMessageId,
      messageType: agentTurnStartType,
      threadPath: "",
      text: prompt,
      attachments: agentAttachments,
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
      final agent = _usesInjectedChatClient ? null : _agent ?? await _waitForAgentOnline();
      final readyAgent = agent;
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
        attachments: agentAttachments,
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
    if (widget.room == null) {
      return child;
    }
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
    final room = widget.room;
    if (room == null) {
      return ChatThreadMessages(
        room: null,
        path: pendingMessage.threadPath,
        scrollController: _controller.threadScrollController,
        messages: const [],
        online: const [],
        showCompletedToolCalls: false,
        pendingMessages: [pendingMessage],
      );
    }

    return ChatThreadMessages(
      room: room,
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
    final headingStyle = ShadTheme.of(context).textTheme.h4;
    final input = AnimatedBuilder(
      animation: Listenable.merge([_modelController, _controller]),
      builder: (context, _) {
        final toolsBuilder = widget.toolsBuilder;
        final toolArea = resolveChatThreadToolArea(toolsBuilder == null ? null : toolsBuilder(context, _controller, snapshot));
        return ChatThreadInput(
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
          audioInputEnabled: (widget.room != null || widget.chatClient != null) && _modelController.supportsAudioInput,
          automaticAudioTurnDetection: _modelController.activeTurnDetection == "automatic",
          onExternalAudioRecordingStart:
              (widget.room != null || widget.chatClient != null) &&
                  _modelController.activeTurnDetection == "automatic" &&
                  _modelController.prefersWebrtcRealtime
              ? _startWebrtcRealtimeAudioThread
              : null,
          onExternalAudioRecordingStop:
              (widget.room != null || widget.chatClient != null) &&
                  _modelController.activeTurnDetection == "automatic" &&
                  _modelController.prefersWebrtcRealtime
              ? _stopWebrtcRealtimeAudioThread
              : null,
          onAudioRecordingStart: (widget.room != null || widget.chatClient != null) && _modelController.activeTurnDetection == "automatic"
              ? () => _ensureRealtimeAudioThread(resolveWhenStarted: true)
              : null,
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
        );
      },
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

    return _buildComposerDropArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight && constraints.maxHeight < 72) {
            return const SizedBox.shrink();
          }
          return content;
        },
      ),
    );
  }
}
