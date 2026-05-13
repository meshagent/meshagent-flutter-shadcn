import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent_agents/meshagent_agents.dart'
    show
        ToolkitCapabilities,
        agentAudioGenerationCompletedType,
        agentAudioGenerationDeltaType,
        agentAudioGenerationFailedType,
        agentAudioGenerationStartedType,
        agentAudioInputSpeechStartedType,
        agentAudioTranscriptionCompletedType,
        agentAudioTranscriptionDeltaType,
        agentAudioTranscriptionFailedType,
        agentAudioTranscriptionStartedType,
        agentContextCompactedType,
        agentFileContentDeltaType,
        agentFileContentEndedType,
        agentFileContentStartedType,
        agentImageGenerationCompletedType,
        agentImageGenerationFailedType,
        agentImageGenerationPartialType,
        agentImageGenerationStartedType,
        agentModelChangedType,
        agentModelChangeType,
        agentModelsRequestType,
        agentModelsResponseType,
        agentReasoningContentDeltaType,
        agentReasoningContentEndedType,
        agentReasoningContentStartedType,
        agentRealtimeAudioCommitType,
        agentRoomMessageType,
        agentTextContentDeltaType,
        agentTextContentEndedType,
        agentTextContentStartedType,
        agentToolCallArgumentsDeltaType,
        agentToolCallEndedType,
        agentToolCallInProgressType,
        agentToolCallLogDeltaType,
        agentToolCallPendingType,
        agentToolCallStartedType,
        agentTurnEndedType,
        agentTurnInterruptedType,
        agentTurnInterruptAcceptedType,
        agentTurnInterruptType,
        agentTurnStartedType,
        agentTurnStartAcceptedType,
        agentTurnStartRejectedType,
        agentTurnStartType,
        agentTurnSteeredType,
        agentTurnSteerAcceptedType,
        agentTurnSteerRejectedType,
        agentTurnSteerType,
        agentUsageUpdatedType;
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'chat.dart';
import 'agent_stream_accumulator.dart';
import 'realtime_audio_output.dart';
import 'tool_call_summary.dart';
import 'usage_footer_tooltip.dart';

const double _datasetDiffPreviewHorizontalPadding = 16;

class DatasetChatAudioFormat {
  const DatasetChatAudioFormat({this.type = 'audio/pcm', this.sampleRate = 24000, this.bitrate});

  final String type;
  final int? sampleRate;
  final int? bitrate;

  static DatasetChatAudioFormat? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final rawType = value['type']?.toString().trim();
    final rawSampleRate = value['sample_rate'] ?? value['rate'];
    final rawBitrate = value['bitrate'];
    return DatasetChatAudioFormat(
      type: rawType == null || rawType.isEmpty ? 'audio/pcm' : rawType,
      sampleRate: rawSampleRate is int ? rawSampleRate : int.tryParse(rawSampleRate?.toString() ?? ''),
      bitrate: rawBitrate is int ? rawBitrate : int.tryParse(rawBitrate?.toString() ?? ''),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'type': type, if (sampleRate != null) 'sample_rate': sampleRate, if (bitrate != null) 'bitrate': bitrate};
  }
}

class DatasetChatModelOption {
  const DatasetChatModelOption({
    required this.provider,
    required this.providerFriendlyName,
    required this.model,
    this.modelFriendlyName,
    this.modelDescription,
    this.modalities = const <String>['text'],
    this.availableVoices = const <String>[],
    this.defaultOutputVoice,
    this.inputFormat,
    this.outputFormat,
    this.turnDetection,
    this.realtimeProtocols = const <String>[],
    this.active = false,
  });

  final String provider;
  final String providerFriendlyName;
  final String model;
  final String? modelFriendlyName;
  final String? modelDescription;
  final List<String> modalities;
  final List<String> availableVoices;
  final String? defaultOutputVoice;
  final DatasetChatAudioFormat? inputFormat;
  final DatasetChatAudioFormat? outputFormat;
  final String? turnDetection;
  final List<String> realtimeProtocols;
  final bool active;

  String get key => '$provider/$model';

  String get label {
    final displayModel = modelFriendlyName == null || modelFriendlyName!.trim().isEmpty ? model : modelFriendlyName!.trim();
    final displayProvider = providerFriendlyName.trim().isEmpty ? provider : providerFriendlyName.trim();
    return '$displayProvider / $displayModel';
  }

  DatasetChatModelOption copyWith({bool? active}) {
    return DatasetChatModelOption(
      provider: provider,
      providerFriendlyName: providerFriendlyName,
      model: model,
      modelFriendlyName: modelFriendlyName,
      modelDescription: modelDescription,
      modalities: modalities,
      availableVoices: availableVoices,
      defaultOutputVoice: defaultOutputVoice,
      inputFormat: inputFormat,
      outputFormat: outputFormat,
      turnDetection: turnDetection,
      realtimeProtocols: realtimeProtocols,
      active: active ?? this.active,
    );
  }
}

class DatasetChatModelController extends ChangeNotifier {
  List<DatasetChatModelOption> _models = const <DatasetChatModelOption>[];
  DatasetChatModelOption? _activeModel;
  String _activeModality = 'text';
  String? _activeVoice;
  Future<void> Function(DatasetChatModelOption option)? _changeHandler;
  Future<void> Function(String voice)? _voiceChangeHandler;
  bool _locked = false;
  bool _changing = false;

  List<DatasetChatModelOption> get models => _models;
  DatasetChatModelOption? get activeModel => _activeModel;
  String get activeModality => _activeModality;
  String? get activeVoice => _activeModality == 'audio' ? _activeVoice : null;
  DatasetChatAudioFormat get activeInputFormat => _activeModel?.inputFormat ?? const DatasetChatAudioFormat();
  String get activeTurnDetection => _activeModel?.turnDetection == 'automatic' ? 'automatic' : 'none';
  List<String> get activeRealtimeProtocols => List<String>.unmodifiable(_activeModel?.realtimeProtocols ?? const <String>[]);
  String get preferredRealtimeProtocol => activeRealtimeProtocols.contains('webrtc') ? 'webrtc' : 'websocket';
  bool get prefersWebrtcRealtime => preferredRealtimeProtocol == 'webrtc';
  List<String> get availableVoices =>
      _activeModality == 'audio' ? List<String>.unmodifiable(_activeModel?.availableVoices ?? const <String>[]) : const <String>[];
  List<String> get outputModalities {
    final modalities = _activeModel?.modalities ?? const <String>['text'];
    final supported = [
      for (final modality in modalities)
        if (modality == 'text' || modality == 'audio') modality,
    ];
    return supported.isEmpty ? const <String>['text'] : List<String>.unmodifiable(supported);
  }

  bool get supportsAudioInput => _activeModel?.modalities.contains('audio') ?? false;

  bool get isChanging => _changing;
  bool get isLocked => _locked;
  bool get canChange => !_locked && !_changing;

  String _resolvedOutputModality(DatasetChatModelOption? model, String current) {
    final supported = [
      for (final modality in model?.modalities ?? const <String>['text'])
        if (modality == 'text' || modality == 'audio') modality,
    ];
    if (supported.isEmpty) {
      return 'text';
    }
    return supported.contains(current) ? current : supported.first;
  }

  String? _resolvedVoice(DatasetChatModelOption? model, String? current) {
    if (_activeModality != 'audio' || model == null || model.availableVoices.isEmpty) {
      return null;
    }
    if (current != null && model.availableVoices.contains(current)) {
      return current;
    }
    final defaultVoice = model.defaultOutputVoice;
    if (defaultVoice != null && model.availableVoices.contains(defaultVoice)) {
      return defaultVoice;
    }
    return model.availableVoices.first;
  }

  void bindChangeHandler(Future<void> Function(DatasetChatModelOption option) handler) {
    _changeHandler = handler;
  }

  void bindVoiceChangeHandler(Future<void> Function(String voice) handler) {
    _voiceChangeHandler = handler;
  }

  void unbindChangeHandler() {
    _changeHandler = null;
    _voiceChangeHandler = null;
  }

  void unbindVoiceChangeHandler() {
    _voiceChangeHandler = null;
  }

  void setLocked(bool locked) {
    if (_locked == locked) {
      return;
    }
    _locked = locked;
    notifyListeners();
  }

  void replaceModelsFrom(DatasetChatModelController other) {
    _models = [for (final model in other.models) model.copyWith()];
    _activeModel = other.activeModel?.copyWith();
    _activeModality = other.activeModality;
    _activeVoice = other.activeVoice;
    notifyListeners();
  }

  Future<void> changeModel(DatasetChatModelOption option) async {
    if (!canChange || _changeHandler == null || option.key == _activeModel?.key) {
      return;
    }
    _changing = true;
    notifyListeners();
    try {
      await _changeHandler!(option);
    } finally {
      _changing = false;
      notifyListeners();
    }
  }

  Future<void> changeVoice(String voice) async {
    final normalized = voice.trim();
    if (_activeModality != 'audio' || !canChange || _voiceChangeHandler == null || normalized.isEmpty || normalized == _activeVoice) {
      return;
    }
    _changing = true;
    notifyListeners();
    try {
      await _voiceChangeHandler!(normalized);
    } finally {
      _changing = false;
      notifyListeners();
    }
  }

  void selectVoiceLocally(String voice) {
    final normalized = voice.trim();
    if (_activeModality != 'audio' || _locked || normalized.isEmpty || normalized == _activeVoice) {
      return;
    }
    if (availableVoices.isNotEmpty && !availableVoices.contains(normalized)) {
      return;
    }
    _activeVoice = normalized;
    notifyListeners();
  }

  void selectModelLocally(DatasetChatModelOption option) {
    if (_locked || option.key == _activeModel?.key) {
      return;
    }
    _models = _models.any((model) => model.key == option.key)
        ? [for (final model in _models) model.copyWith(active: model.key == option.key)]
        : [for (final model in _models) model.copyWith(active: false), option.copyWith(active: true)];
    _activeModel = option.copyWith(active: true);
    _activeModality = _resolvedOutputModality(_activeModel, _activeModality);
    _activeVoice = _resolvedVoice(_activeModel, option.defaultOutputVoice);
    notifyListeners();
  }

  void selectOutputModality(String modality) {
    final normalized = modality.trim();
    if (_locked || normalized.isEmpty || normalized == _activeModality || !outputModalities.contains(normalized)) {
      return;
    }
    _activeModality = normalized;
    _activeVoice = _resolvedVoice(_activeModel, _activeVoice);
    notifyListeners();
  }

  void applyModelsResponse(Map<String, dynamic> payload) {
    final providers = payload['providers'];
    if (providers is! List) {
      return;
    }
    final nextModels = <DatasetChatModelOption>[];
    DatasetChatModelOption? active;
    for (final providerValue in providers) {
      if (providerValue is! Map) {
        continue;
      }
      final provider = providerValue['name']?.toString().trim();
      if (provider == null || provider.isEmpty) {
        continue;
      }
      final providerFriendlyName = providerValue['friendly_name']?.toString() ?? provider;
      final models = providerValue['models'];
      if (models is! List) {
        continue;
      }
      for (final modelValue in models) {
        if (modelValue is! Map) {
          continue;
        }
        final model = modelValue['name']?.toString().trim();
        if (model == null || model.isEmpty) {
          continue;
        }
        final rawModalities = modelValue['modalities'];
        final modalities = rawModalities is List
            ? [
                for (final value in rawModalities)
                  if (value.toString().trim().isNotEmpty) value.toString().trim(),
              ]
            : const <String>['text'];
        final option = DatasetChatModelOption(
          provider: provider,
          providerFriendlyName: providerFriendlyName,
          model: model,
          modelFriendlyName: modelValue['friendly_name']?.toString(),
          modelDescription: modelValue['description']?.toString(),
          modalities: modalities.isEmpty ? const <String>['text'] : modalities,
          availableVoices: _stringList(modelValue['available_voices']),
          defaultOutputVoice: modelValue['default_output_voice']?.toString(),
          inputFormat: DatasetChatAudioFormat.fromJson(modelValue['input_format']),
          outputFormat: DatasetChatAudioFormat.fromJson(modelValue['output_format']),
          turnDetection: modelValue['turn_detection']?.toString(),
          realtimeProtocols: _stringList(modelValue['realtime_protocols']),
          active: modelValue['active'] == true,
        );
        nextModels.add(option);
        if (option.active) {
          active = option;
        }
      }
    }
    final priorActive = _activeModel;
    if (priorActive != null) {
      final refreshedActive = nextModels.firstWhereOrNull((option) => option.key == priorActive.key);
      if (refreshedActive != null) {
        active = refreshedActive;
      }
    }
    active ??= nextModels.isEmpty ? null : nextModels.first;
    _models = [for (final option in nextModels) option.copyWith(active: option.key == active?.key)];
    _activeModel = active?.copyWith(active: true);
    _activeModality = _resolvedOutputModality(_activeModel, _activeModality);
    _activeVoice = _resolvedVoice(_activeModel, _activeVoice);
    notifyListeners();
  }

  void applyModelChanged(Map<String, dynamic> payload) {
    final provider = payload['provider']?.toString().trim();
    final model = payload['model']?.toString().trim();
    if (provider == null || provider.isEmpty || model == null || model.isEmpty) {
      return;
    }
    final existing = _models.firstWhereOrNull((option) => option.provider == provider && option.model == model);
    final outputModalities = payload['output_modalities'];
    if (outputModalities is List && outputModalities.isNotEmpty) {
      final firstOutputModality = outputModalities.first?.toString().trim();
      if (firstOutputModality != null && firstOutputModality.isNotEmpty) {
        _activeModality = firstOutputModality;
      }
    }
    final active =
        existing?.copyWith(active: true) ??
        DatasetChatModelOption(
          provider: provider,
          providerFriendlyName: payload['provider_friendly_name']?.toString() ?? provider,
          model: model,
          modelFriendlyName: payload['model_friendly_name']?.toString(),
          modelDescription: payload['model_description']?.toString(),
          inputFormat: DatasetChatAudioFormat.fromJson(payload['input_format']),
          outputFormat: DatasetChatAudioFormat.fromJson(payload['output_format']),
          turnDetection: payload['turn_detection']?.toString(),
          realtimeProtocols: _stringList(payload['realtime_protocols']),
          modalities: const <String>[],
          active: true,
        );
    if (existing == null) {
      _models = [for (final option in _models) option.copyWith(active: false), active];
    } else {
      _models = [for (final option in _models) option.copyWith(active: option.key == active.key)];
    }
    _activeModel = active;
    _activeModality = _resolvedOutputModality(_activeModel, _activeModality);
    final payloadVoice = payload['voice']?.toString().trim();
    _activeVoice = _resolvedVoice(_activeModel, payloadVoice == null || payloadVoice.isEmpty ? active.defaultOutputVoice : payloadVoice);
    notifyListeners();
  }
}

class DatasetChatThread extends StatefulWidget {
  const DatasetChatThread({
    super.key,
    required this.room,
    required this.path,
    this.controller,
    this.composerKey,
    this.agentName,
    this.emptyStateTitle,
    this.emptyStateDescription,
    this.openFile,
    this.toolsBuilder,
    this.inputPlaceholder,
    this.attachmentBuilder,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.modelController,
    this.initialShowCompletedToolCalls = false,
    this.showUsageFooter = false,
  });

  final RoomClient room;
  final String path;
  final ChatThreadController? controller;
  final GlobalKey? composerKey;
  final String? agentName;
  final String? emptyStateTitle;
  final String? emptyStateDescription;
  final FutureOr<void> Function(String path)? openFile;
  final Widget Function(BuildContext, ChatThreadController, ChatThreadSnapshot)? toolsBuilder;
  final Widget? inputPlaceholder;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final DatasetChatModelController? modelController;
  final bool initialShowCompletedToolCalls;
  final bool showUsageFooter;

  @override
  State<DatasetChatThread> createState() => _DatasetChatThreadState();
}

class _DatasetChatThreadState extends State<DatasetChatThread> {
  StreamSubscription<ArrowRecordBatch>? _tableLoadSubscription;
  StreamSubscription<RoomEvent>? _roomSubscription;
  Timer? _tableLoadRetryTimer;
  agent_sessions.MessagingChatClient? _chatClient;
  agent_sessions.ChatThreadSession? _threadSession;
  final Map<String, Map<String, Object?>> _rowsByItemId = {};
  final Map<String, Map<String, Object?>> _agentRowsByItemId = {};
  final List<Map<String, dynamic>> _bufferedAgentPayloads = <Map<String, dynamic>>[];
  final TextStreamAccumulator _liveTextContent = TextStreamAccumulator();
  final TextStreamAccumulator _liveReasoningContent = TextStreamAccumulator();
  final FileStreamAccumulator _liveFileContent = FileStreamAccumulator();
  final Map<String, String> _realtimeAudioCommitItemIdsByTurnId = <String, String>{};
  final _DatasetThreadRealtimeAudioPlayer _audioPlayer = _DatasetThreadRealtimeAudioPlayer();
  late ChatThreadController _controller;
  late bool _ownsController;
  late DatasetChatModelController _modelController;
  late bool _ownsModelController;
  late Key _composerInputKey;
  int _tableLoadGeneration = 0;
  Object? _error;
  bool _fatalError = false;
  bool _ready = false;
  ChatThreadStatusState _status = const ChatThreadStatusState();
  AgentUsageSnapshot? _usage;
  int _nextAgentSequence = 0;
  int _threadSessionMessageCursor = 0;
  final OverlayPortalController _imageViewerController = OverlayPortalController();
  LocalHistoryEntry? _imageViewerHistoryEntry;
  List<ChatThreadFeedImage> _overlayImages = const <ChatThreadFeedImage>[];
  int _overlayInitialIndex = 0;
  final Set<String> _expandedDetailGroupIds = <String>{};
  final Set<String> _expandedToolCallIds = <String>{};

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _ownsModelController = widget.modelController == null;
    _modelController = widget.modelController ?? DatasetChatModelController();
    _modelController.bindChangeHandler(_changeModel);
    _modelController.bindVoiceChangeHandler(_changeVoice);
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    _roomSubscription = widget.room.listen(_onRoomEvent);
    widget.room.messaging.addListener(_onMessagingChanged);
    _bindChatSession();
    _refreshStatus();
    _startWatch();
  }

  @override
  void didUpdateWidget(covariant DatasetChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerKey != widget.composerKey) {
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    }
    if (oldWidget.room != widget.room || oldWidget.controller != widget.controller) {
      _roomSubscription?.cancel();
      oldWidget.room.messaging.removeListener(_onMessagingChanged);
      _roomSubscription = widget.room.listen(_onRoomEvent);
      widget.room.messaging.addListener(_onMessagingChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? ChatThreadController(room: widget.room);
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    }
    if (oldWidget.modelController != widget.modelController) {
      _modelController.unbindChangeHandler();
      if (_ownsModelController) {
        _modelController.dispose();
      }
      _ownsModelController = widget.modelController == null;
      _modelController = widget.modelController ?? DatasetChatModelController();
      _modelController.bindChangeHandler(_changeModel);
      _modelController.bindVoiceChangeHandler(_changeVoice);
    }
    if (oldWidget.path != widget.path || oldWidget.agentName != widget.agentName || oldWidget.room != widget.room) {
      _usage = null;
      _refreshStatus();
      _bindChatSession();
    }
    if (oldWidget.path != widget.path || oldWidget.room != widget.room) {
      _startWatch();
    }
  }

  @override
  void dispose() {
    _tableLoadRetryTimer?.cancel();
    _tableLoadSubscription?.cancel();
    _closeChatSession();
    unawaited(_chatClient?.stop());
    _roomSubscription?.cancel();
    final historyEntry = _imageViewerHistoryEntry;
    _imageViewerHistoryEntry = null;
    historyEntry?.remove();
    widget.room.messaging.removeListener(_onMessagingChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _modelController.unbindChangeHandler();
    if (_ownsModelController) {
      _modelController.dispose();
    }
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  void _startWatch() {
    _tableLoadGeneration += 1;
    _tableLoadRetryTimer?.cancel();
    _tableLoadSubscription?.cancel();
    _rowsByItemId.clear();
    _agentRowsByItemId.clear();
    _bufferedAgentPayloads.clear();
    _liveTextContent.clear();
    _liveReasoningContent.clear();
    _liveFileContent.clear();
    unawaited(_audioPlayer.stopAll());
    _nextAgentSequence = 0;
    _error = null;
    _fatalError = false;
    _ready = false;
    _usage = null;

    if (_isTmpThreadPath(widget.path)) {
      _ready = true;
      _materializePendingMessagesForThread();
      return;
    }

    _loadDatasetRows(generation: _tableLoadGeneration);
  }

  void _loadDatasetRows({required int generation}) {
    _tableLoadRetryTimer?.cancel();
    _tableLoadSubscription?.cancel();
    final loadedRowsByItemId = <String, Map<String, Object?>>{};
    try {
      final ref = _DatasetThreadRef.parse(widget.path);
      _tableLoadSubscription = widget.room.datasets
          .searchStream(table: ref.table, namespace: ref.namespace)
          .listen(
            (batch) {
              if (!mounted || generation != _tableLoadGeneration) {
                return;
              }
              _applyRowsToMap(batch.toRows(), loadedRowsByItemId);
            },
            onError: (Object error, StackTrace stackTrace) {
              _handleTableLoadError(error, stackTrace, generation: generation);
            },
            onDone: () {
              _finishDatasetRowsLoad(loadedRowsByItemId, generation: generation);
            },
          );
    } catch (error) {
      _error = error;
      _fatalError = true;
      _ready = true;
    }
  }

  void _handleTableLoadError(Object error, StackTrace stackTrace, {required int generation}) {
    if (!mounted || generation != _tableLoadGeneration) {
      return;
    }
    setState(() {
      if (_isDatasetTableNotFoundError(error)) {
        _error = null;
        _fatalError = false;
        _ready = false;
        _scheduleDatasetLoadRetry(generation: generation);
      } else {
        _error = error;
        _fatalError = true;
        _ready = true;
      }
    });
  }

  void _scheduleDatasetLoadRetry({required int generation}) {
    _tableLoadRetryTimer?.cancel();
    _tableLoadRetryTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || generation != _tableLoadGeneration) {
        return;
      }
      _loadDatasetRows(generation: generation);
    });
  }

  void _finishDatasetRowsLoad(Map<String, Map<String, Object?>> loadedRowsByItemId, {required int generation}) {
    if (!mounted || generation != _tableLoadGeneration) {
      return;
    }
    _rowsByItemId
      ..clear()
      ..addAll(loadedRowsByItemId);
    _advanceNextAgentSequencePastDatasetRows();

    // Mark the load as ready before draining so any agent events delivered while
    // buffered events are being reconciled apply normally instead of being left
    // behind in the buffer.
    _ready = true;
    while (_bufferedAgentPayloads.isNotEmpty) {
      final bufferedPayloads = List<Map<String, dynamic>>.from(_bufferedAgentPayloads);
      _bufferedAgentPayloads.clear();
      for (final payload in bufferedPayloads) {
        _handleAgentMessagePayload(payload, notify: false, scroll: false);
      }
    }
    _usage = _latestUsageFromRows();
    setState(() {});
    _controller.scrollThreadToBottom(animated: false);
  }

  bool _applyRowsToMap(Iterable<Map<String, Object?>> rows, Map<String, Map<String, Object?>> target) {
    var changed = false;
    for (final row in rows) {
      final normalized = Map<String, Object?>.from(row);
      final rowKey = _datasetRowKey(normalized);
      final itemId = normalized['item_id']?.toString();
      if (rowKey == null || itemId == null || itemId.trim().isEmpty) {
        continue;
      }
      final existing = target[rowKey];
      if (existing == null || !const DeepCollectionEquality().equals(existing, normalized)) {
        target[rowKey] = normalized;
        _removeReconciledAgentRowsForDatasetRow(normalized);
        changed = true;
      }
    }
    if (changed) {
      _advanceNextAgentSequencePastDatasetRows();
      changed = _rebaseAgentRowsAfterDatasetRows() || changed;
    }
    return changed;
  }

  AgentUsageSnapshot? _latestUsageFromRows() {
    final rows = [..._rowsByItemId.values, ..._agentRowsByItemId.values]..sort(_compareDatasetThreadRows);
    AgentUsageSnapshot? latestUsage;
    for (final row in rows) {
      final data = _rowData(row);
      if (data == null) {
        continue;
      }
      final rawType = data['type']?.toString();
      final message = rawType == agentUsageUpdatedType
          ? data
          : data['kind'] == 'usage'
          ? _mapValue(data['message'])
          : null;
      if (message == null) {
        continue;
      }
      final usage = AgentUsageSnapshot.fromPayload(message);
      if (usage == null || usage.threadPath != widget.path) {
        continue;
      }
      if (shouldReplaceAgentUsageSnapshot(latestUsage, usage)) {
        latestUsage = usage;
      }
    }
    return latestUsage;
  }

  void _removeReconciledAgentRowsForDatasetRow(Map<String, Object?> datasetRow) {
    final liveItemIds = _agentRowsByItemId.entries
        .where((entry) {
          return _datasetRowReconcilesLiveRow(datasetRow: datasetRow, liveRow: entry.value);
        })
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final liveItemId in liveItemIds) {
      _agentRowsByItemId.remove(liveItemId);
    }
  }

  void _advanceNextAgentSequencePastDatasetRows() {
    final maxDatasetSequence = _maxDatasetSequence();
    if (maxDatasetSequence >= _nextAgentSequence) {
      _nextAgentSequence = maxDatasetSequence + 1;
    }
  }

  bool _rebaseAgentRowsAfterDatasetRows() {
    final maxDatasetSequence = _maxVisibleDatasetSequence();
    if (maxDatasetSequence < 0 || _agentRowsByItemId.isEmpty) {
      return false;
    }

    var changed = false;
    var nextSequence = maxDatasetSequence + 1;
    final liveRows = _agentRowsByItemId.values.toList(growable: false)..sort(_compareDatasetThreadRows);
    for (final row in liveRows) {
      final itemId = row['item_id']?.toString();
      if (itemId == null || itemId.trim().isEmpty) {
        continue;
      }
      if (_datasetRowsContainItemId(itemId)) {
        continue;
      }
      final sequence = _intValue(row['sequence']);
      if (sequence <= maxDatasetSequence) {
        _agentRowsByItemId[itemId] = {...row, 'sequence': nextSequence};
        changed = true;
        nextSequence += 1;
      } else if (sequence >= nextSequence) {
        nextSequence = sequence + 1;
      }
    }
    if (nextSequence > _nextAgentSequence) {
      _nextAgentSequence = nextSequence;
    }
    return changed;
  }

  int _maxDatasetSequence() {
    var maxSequence = -1;
    for (final row in _rowsByItemId.values) {
      final sequence = _intValue(row['sequence']);
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence;
  }

  int _maxVisibleDatasetSequence() {
    var maxSequence = -1;
    final rows = _rowsByItemId.values.toList(growable: false);
    final turnInputPayloadsById = _turnInputPayloadsById(rows);
    for (final row in rows) {
      final message = _messageForRow(row, turnInputPayloadsById: turnInputPayloadsById);
      if (message == null || !_shouldRenderDatasetThreadMessage(message)) {
        continue;
      }
      final sequence = _intValue(row['sequence']);
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence;
  }

  bool _datasetRowsContainItemId(String itemId) {
    final normalized = itemId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _rowsByItemId.values.any((row) => row['item_id']?.toString() == normalized);
  }

  void _onMessagingChanged() {
    if (!mounted) {
      return;
    }
    _refreshStatus(notify: true);
    _bindChatSession();
  }

  void _bindChatSession() {
    final existingClient = _chatClient;
    if (existingClient == null || existingClient.room != widget.room || existingClient.agentName != widget.agentName) {
      _threadSession?.removeListener(_onThreadSessionChanged);
      _threadSession = null;
      _threadSessionMessageCursor = 0;
      if (existingClient != null) {
        unawaited(existingClient.stop());
      }
      _chatClient = agent_sessions.MessagingChatClient(room: widget.room, agentName: widget.agentName);
      unawaited(_chatClient!.start());
    }

    final currentSession = _threadSession;
    if (currentSession != null && currentSession.threadPath == widget.path) {
      return;
    }

    currentSession?.removeListener(_onThreadSessionChanged);
    _threadSession = _chatClient!.openThread(widget.path);
    _threadSessionMessageCursor = 0;
    _threadSession!.addListener(_onThreadSessionChanged);
    _drainThreadSessionMessages(notify: false, scroll: false);
  }

  void _closeChatSession() {
    final session = _threadSession;
    _threadSession = null;
    _threadSessionMessageCursor = 0;
    session?.removeListener(_onThreadSessionChanged);
    if (session != null) {
      unawaited(session.close());
    }
  }

  void _onThreadSessionChanged() {
    if (!mounted) {
      return;
    }
    _drainThreadSessionMessages();
  }

  void _drainThreadSessionMessages({bool notify = true, bool scroll = true}) {
    final session = _threadSession;
    if (session == null) {
      return;
    }
    final messages = session.messages;
    var changed = false;
    while (_threadSessionMessageCursor < messages.length) {
      final event = messages[_threadSessionMessageCursor];
      _threadSessionMessageCursor += 1;
      final payload = event.payload;
      trackAgentThreadStatusMessage(room: widget.room, message: event.message);
      if (_shouldBufferAgentPayload(payload)) {
        _bufferedAgentPayloads.add(Map<String, dynamic>.from(payload));
      } else {
        _handleAgentMessagePayload(payload, attachment: event.attachment, notify: false, scroll: false);
      }
      changed = true;
    }
    _refreshStatus();
    if (changed && notify && mounted) {
      setState(() {});
      if (scroll) {
        _controller.scrollThreadToBottom(animated: false);
      }
    }
  }

  void _onRoomEvent(RoomEvent event) {
    if (!mounted) {
      return;
    }
    if (event is! RoomMessageEvent) {
      return;
    }
    if (event.message.type == agentRoomMessageType) {
      _refreshStatus(notify: true);
    }
  }

  bool _shouldBufferAgentPayload(Map<String, dynamic> payload) {
    if (_isModelPayload(payload)) {
      return false;
    }
    return !_ready && _agentPayloadBelongsToThread(payload);
  }

  bool _isModelPayload(Map<String, dynamic> payload) {
    final type = payload['type'];
    return type == agentModelsRequestType ||
        type == agentModelsResponseType ||
        type == agentModelChangeType ||
        type == agentModelChangedType;
  }

  bool _agentPayloadBelongsToThread(Map<String, dynamic> payload) {
    final threadId = payload['thread_id'];
    if (threadId is String && threadId.trim() == widget.path) {
      return true;
    }
    final usage = AgentUsageSnapshot.fromPayload(payload);
    return usage != null && usage.threadPath == widget.path;
  }

  void _handleAgentMessagePayload(Map<String, dynamic> payload, {Uint8List? attachment, bool notify = true, bool scroll = true}) {
    if (_handleUsagePayload(payload, notify: notify)) {
      return;
    }
    if (_handleModelPayload(payload)) {
      return;
    }
    final changed = _applyAgentMessagePayload(payload, attachment: attachment);
    try {
      _controller.handleAgentMessage(agent_sessions.AgentMessage.fromJson(payload));
    } catch (_) {}
    if (changed && notify && mounted) {
      setState(() {});
      if (scroll) {
        _controller.scrollThreadToBottom(animated: false);
      }
    }
  }

  bool _handleUsagePayload(Map<String, dynamic> payload, {bool notify = true}) {
    final usage = AgentUsageSnapshot.fromPayload(payload);
    if (usage == null) {
      return false;
    }
    if (usage.threadPath != widget.path) {
      return true;
    }

    final changed = _upsertAgentRow(
      itemId: _payloadItemId(payload),
      turnId: _payloadTurnId(payload),
      timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
      data: {'kind': 'usage', 'status': 'completed', 'message': payload},
    );
    if (!shouldReplaceAgentUsageSnapshot(_usage, usage)) {
      return true;
    }
    _usage = usage;
    if (notify && mounted) {
      setState(() {});
    } else if (changed) {
      return true;
    }
    return true;
  }

  bool _applyAgentMessagePayload(Map<String, dynamic> payload, {Uint8List? attachment}) {
    if (payload['thread_id'] != widget.path) {
      return false;
    }

    final type = payload['type'];
    if (type is! String) {
      return false;
    }
    if (type == agentTurnStartRejectedType || type == agentTurnSteerRejectedType) {
      return false;
    }

    var changed = false;

    switch (type) {
      case agentTurnStartType:
      case agentTurnSteerType:
      case agentTurnInterruptType:
        unawaited(_audioPlayer.stopAll());
        break;
      case agentModelsRequestType:
      case agentModelsResponseType:
      case agentModelChangeType:
      case agentModelChangedType:
        break;
      case agentTurnStartAcceptedType:
      case agentTurnSteerAcceptedType:
        final sourceMessageId = payload['source_message_id']?.toString().trim();
        final turnId = _payloadTurnId(payload);
        if (sourceMessageId != null && sourceMessageId.isNotEmpty && turnId != null && turnId.trim().isNotEmpty) {
          _realtimeAudioCommitItemIdsByTurnId[turnId.trim()] = sourceMessageId;
          final sourceRow = _agentRowsByItemId[sourceMessageId];
          final sourceData = _mapValue(sourceRow?['data']);
          if (sourceData?['message'] is Map || sourceData?['status'] == 'in_progress') {
            if (sourceRow != null && sourceRow['turn_id'] != turnId) {
              _agentRowsByItemId[sourceMessageId] = {...sourceRow, 'turn_id': turnId};
              changed = true;
            }
          }
        }
        break;
      case agentTurnStartedType:
        changed =
            _upsertAgentRow(
              itemId: _turnApplicationItemId(payload, 'started'),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: payload,
            ) ||
            changed;
        changed = _materializePendingMessage(payload['source_message_id']?.toString()) || changed;
        break;
      case agentTurnInterruptAcceptedType:
      case agentTurnInterruptedType:
      case agentAudioInputSpeechStartedType:
        unawaited(_audioPlayer.stopAll());
        break;
      case agentTurnSteeredType:
        changed =
            _upsertAgentRow(
              itemId: _turnApplicationItemId(payload, 'steered'),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: payload,
            ) ||
            changed;
        changed = _materializePendingMessage(payload['source_message_id']?.toString()) || changed;
        break;
      case agentRealtimeAudioCommitType:
        final turnId = _payloadTurnId(payload);
        final itemId = _payloadItemId(payload);
        if (turnId != null && turnId.trim().isNotEmpty) {
          _realtimeAudioCommitItemIdsByTurnId[turnId.trim()] = itemId;
        }
        changed =
            _upsertAgentRow(
              itemId: itemId,
              turnId: turnId,
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: {
                'kind': 'message',
                'role': 'user',
                'status': 'in_progress',
                'text': '',
                'sender_name': _senderNameFromPayload(payload),
                'message': payload,
              },
            ) ||
            changed;
        break;
      case agentTextContentStartedType:
      case agentAudioTranscriptionStartedType:
        _liveTextContent.upsert(itemId: _transcriptionItemId(payload), turnId: _payloadTurnId(payload), phase: _agentMessagePhase(payload));
        break;
      case agentTextContentDeltaType:
      case agentAudioTranscriptionDeltaType:
        final contentRole = _textContentRoleFromPayload(payload);
        changed =
            _appendAgentRowText(
              itemId: _transcriptionItemId(payload),
              turnId: _payloadTurnId(payload),
              kind: 'message',
              role: contentRole,
              delta: payload['text']?.toString() ?? '',
              senderName: _senderNameFromPayload(payload),
              phase: _agentMessagePhase(payload),
            ) ||
            changed;
        break;
      case agentTextContentEndedType:
      case agentAudioTranscriptionCompletedType:
        final contentRole = _textContentRoleFromPayload(payload);
        final itemId = _transcriptionItemId(payload);
        final accumulatedText = _liveTextContent.complete(itemId);
        _liveTextContent.remove(itemId);
        final phase = _agentMessagePhase(payload) ?? accumulatedText?.phase;
        changed =
            _upsertAgentRow(
              itemId: itemId,
              turnId: _payloadTurnId(payload),
              data: {
                'kind': 'message',
                'role': contentRole,
                'status': accumulatedText?.status ?? 'completed',
                'text': payload['text']?.toString() ?? accumulatedText?.text ?? _agentRowText(itemId),
                'sender_name': _senderNameFromPayload(payload) ?? accumulatedText?.senderName ?? _agentRowSenderName(itemId),
                'phase': ?phase,
              },
            ) ||
            changed;
        break;
      case agentAudioTranscriptionFailedType:
        _liveTextContent.remove(_transcriptionItemId(payload));
        break;
      case agentAudioGenerationStartedType:
        unawaited(_audioPlayer.start(_audioPlaybackStreamItemId(payload)));
        break;
      case agentAudioGenerationDeltaType:
        unawaited(
          _audioPlayer.append(
            itemId: _audioPlaybackStreamItemId(payload),
            messageId: payload['message_id']?.toString(),
            data: attachment,
            mimeType: payload['mime_type']?.toString(),
          ),
        );
        break;
      case agentAudioGenerationCompletedType:
        unawaited(_audioPlayer.complete(_audioPlaybackStreamItemId(payload)));
        break;
      case agentAudioGenerationFailedType:
        unawaited(_audioPlayer.stop(_audioPlaybackStreamItemId(payload)));
        break;
      case agentReasoningContentStartedType:
        _liveReasoningContent.upsert(itemId: _payloadItemId(payload), turnId: _payloadTurnId(payload));
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: const {'kind': 'reasoning', 'role': 'assistant', 'status': 'in_progress', 'text': ''},
            ) ||
            changed;
        break;
      case agentReasoningContentDeltaType:
        changed =
            _appendAgentRowText(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              kind: 'reasoning',
              role: 'assistant',
              delta: payload['text']?.toString() ?? '',
              phase: null,
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case agentReasoningContentEndedType:
        final accumulatedReasoning = _liveReasoningContent.complete(_payloadItemId(payload));
        _liveReasoningContent.remove(_payloadItemId(payload));
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: {
                'kind': 'reasoning',
                'role': 'assistant',
                'status': accumulatedReasoning?.status ?? 'completed',
                'text': payload['text']?.toString() ?? accumulatedReasoning?.text ?? _agentRowText(_payloadItemId(payload)),
                'sender_name':
                    _senderNameFromPayload(payload) ?? accumulatedReasoning?.senderName ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
      case agentFileContentStartedType:
        _liveFileContent.upsert(itemId: _payloadItemId(payload), turnId: _payloadTurnId(payload));
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: const {'kind': 'file', 'role': 'assistant', 'status': 'in_progress', 'urls': <String>[]},
            ) ||
            changed;
        break;
      case agentFileContentDeltaType:
        changed =
            _appendAgentRowUrl(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              url: payload['url']?.toString(),
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case agentFileContentEndedType:
        final endUrl = payload['url']?.toString();
        if (endUrl != null && endUrl.trim().isNotEmpty) {
          _liveFileContent.appendUrl(
            itemId: _payloadItemId(payload),
            turnId: _payloadTurnId(payload),
            url: endUrl,
            senderName: _senderNameFromPayload(payload),
          );
        }
        final accumulatedFile = _liveFileContent.complete(_payloadItemId(payload));
        _liveFileContent.remove(_payloadItemId(payload));
        final existingData = _mapValue(_agentRowsByItemId[_payloadItemId(payload)]?['data']);
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: {
                'kind': 'file',
                'role': 'assistant',
                'status': accumulatedFile?.status ?? 'completed',
                'urls': accumulatedFile?.urls ?? _stringList(existingData?['urls']),
                'sender_name': _senderNameFromPayload(payload) ?? accumulatedFile?.senderName ?? existingData?['sender_name']?.toString(),
              },
            ) ||
            changed;
        break;
      case agentToolCallPendingType:
      case agentToolCallInProgressType:
      case agentToolCallStartedType:
      case agentToolCallEndedType:
        final itemId = _payloadItemId(payload);
        final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
        final tool = payload['tool']?.toString() ?? payload['tool_name']?.toString() ?? payload['name']?.toString() ?? '';
        final resolvedTool = tool.trim().isEmpty ? (existingData?['tool']?.toString() ?? '') : tool;
        final toolkit = payload['toolkit']?.toString() ?? payload['toolkit_name']?.toString() ?? existingData?['toolkit']?.toString() ?? '';
        final payloadArguments = _mapValue(payload['arguments']);
        final existingArgumentDeltaText = existingData?['argument_delta_text']?.toString() ?? '';
        final arguments =
            _toolArgumentsFromDeltaText(
              tool: resolvedTool,
              current: payloadArguments ?? _mapValue(existingData?['arguments']),
              text: existingArgumentDeltaText,
            ) ??
            payloadArguments ??
            _mapValue(existingData?['arguments']);
        final errorMessage = _agentToolCallErrorMessage(payload['error']);
        final errorData = errorMessage == null ? const <String, Object?>{} : <String, Object?>{'error_message': errorMessage};
        final logs = _stringList(existingData?['logs']);
        final isImageGeneration = tool.trim().toLowerCase() == 'image_generation';
        final status = type == agentToolCallEndedType
            ? (errorMessage == null ? 'completed' : 'failed')
            : (type == agentToolCallPendingType ? 'pending' : 'running');
        if (isImageGeneration && type == agentToolCallEndedType && payload['error'] == null) {
          break;
        }
        changed =
            _upsertAgentRow(
              itemId: itemId,
              turnId: _payloadTurnId(payload),
              data: isImageGeneration
                  ? {
                      'kind': 'image_generation',
                      'role': 'assistant',
                      'status': payload['error'] == null ? 'in_progress' : 'failed',
                      'call_id': payload['call_id']?.toString(),
                      'arguments': _mapValue(payload['arguments']),
                      'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
                    }
                  : {
                      'kind': 'tool_call',
                      'role': 'assistant',
                      'toolkit': toolkit,
                      'tool': resolvedTool,
                      'status': status,
                      'arguments': arguments,
                      'logs': logs,
                      if (_intValue(existingData?['argument_delta_bytes']) > 0)
                        'argument_delta_bytes': _intValue(existingData?['argument_delta_bytes']),
                      if (existingArgumentDeltaText.isNotEmpty) 'argument_delta_text': existingArgumentDeltaText,
                      ...errorData,
                      'text': formatToolCallEntryText(
                        toolkit: toolkit,
                        tool: resolvedTool,
                        arguments: arguments,
                        logs: logs,
                        errorMessage: errorMessage,
                        completed: type == agentToolCallEndedType,
                        pending: _toolCallStatusIsPending(status),
                        argumentDeltaBytes: _intValue(existingData?['argument_delta_bytes']),
                      ),
                      'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(itemId),
                    },
            ) ||
            changed;
        break;
      case agentToolCallArgumentsDeltaType:
        changed =
            _appendAgentToolArgumentDelta(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              delta: payload['delta']?.toString() ?? '',
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case agentToolCallLogDeltaType:
        changed =
            _appendAgentToolLogs(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              lines: _agentToolCallLogLines(payload['lines']),
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case agentImageGenerationStartedType:
      case agentImageGenerationPartialType:
      case agentImageGenerationCompletedType:
      case agentImageGenerationFailedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: {
                'kind': 'image_generation',
                'role': 'assistant',
                'status': _imageGenerationStatusFromType(type),
                'call_id': payload['call_id']?.toString(),
                'arguments': _mapValue(payload['arguments']),
                'message': payload,
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
      case agentContextCompactedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: {
                'kind': 'compaction',
                'role': 'assistant',
                'status': 'completed',
                'message': payload,
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
      case agentTurnEndedType:
        final errorMessage = agentTurnEndedErrorMessage(payload);
        if (errorMessage == null) {
          break;
        }
        changed =
            _upsertAgentRow(
              itemId: _turnApplicationItemId(payload, 'error'),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: {
                'kind': 'error',
                'role': 'assistant',
                'status': 'failed',
                'text': errorMessage,
                'message': payload,
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
    }
    return changed;
  }

  bool _materializePendingMessagesForThread() {
    var changed = false;
    for (final pending in _pendingAgentMessagesForThread()) {
      changed = _materializePendingMessage(pending.messageId) || changed;
    }
    return changed;
  }

  List<PendingAgentMessage> _pendingAgentMessagesForThread() {
    final combined = <String, PendingAgentMessage>{};
    for (final pending in _status.pendingMessages) {
      combined[pending.messageId] = pending;
    }
    final currentStatus = resolveChatThreadStatus(room: widget.room, path: widget.path, agentName: widget.agentName, previous: _status);
    for (final pending in currentStatus.pendingMessages) {
      combined[pending.messageId] = pending;
    }
    for (final pending in _controller.pendingAgentMessagesForPath(widget.path)) {
      combined[pending.messageId] = pending;
    }
    return combined.values.toList(growable: false);
  }

  bool _materializePendingMessage(String? messageId) {
    if (messageId == null || messageId.trim().isEmpty || _agentRowsByItemId.containsKey(messageId)) {
      return false;
    }
    PendingAgentMessage? pending;
    for (final candidate in _pendingAgentMessagesForThread()) {
      if (candidate.messageId == messageId) {
        pending = candidate;
        break;
      }
    }
    if (pending == null) {
      return false;
    }
    final attachments = pending.attachments.map(_normalizeAgentAttachmentUrl).whereType<String>().toList(growable: false);
    return _upsertAgentRow(
      itemId: pending.messageId,
      turnId: null,
      timestamp: pending.createdAt ?? DateTime.now().toUtc(),
      data: {'kind': 'message', 'role': 'user', 'text': pending.text, 'sender_name': pending.senderName, 'attachments': attachments},
    );
  }

  String _transcriptionItemId(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type != agentAudioTranscriptionStartedType &&
        type != agentAudioTranscriptionDeltaType &&
        type != agentAudioTranscriptionCompletedType &&
        type != agentAudioTranscriptionFailedType) {
      return _payloadItemId(payload);
    }
    if (_textContentRoleFromPayload(payload) != 'user') {
      return _payloadItemId(payload);
    }
    final turnId = _payloadTurnId(payload);
    if (turnId == null || turnId.trim().isEmpty) {
      return _payloadItemId(payload);
    }
    return _realtimeAudioCommitItemIdsByTurnId[turnId.trim()] ?? _payloadItemId(payload);
  }

  String _audioPlaybackStreamItemId(Map<String, dynamic> payload) {
    final turnId = _payloadTurnId(payload);
    if (turnId != null && turnId.trim().isNotEmpty) {
      return 'turn:${turnId.trim()}:audio_generation';
    }
    return _payloadItemId(payload);
  }

  bool _upsertAgentRow({required String itemId, required String? turnId, required Map<String, Object?> data, DateTime? timestamp}) {
    if (itemId.trim().isEmpty) {
      return false;
    }
    final candidateRow = <String, Object?>{'turn_id': turnId, 'item_id': itemId, 'data': data};
    if (_isReconciledByDatasetRows(candidateRow)) {
      return false;
    }
    final dataKind = data['kind']?.toString();
    final dataRole = data['role']?.toString();
    final canOverlayDatasetLifecycleRow = dataKind == 'file' || dataKind == 'image_generation' || dataRole == 'assistant';
    if (_datasetRowsContainItemId(itemId) && !canOverlayDatasetLifecycleRow) {
      return false;
    }
    final existing = _agentRowsByItemId[itemId];
    final row = <String, Object?>{
      'turn_id': turnId ?? existing?['turn_id'],
      'item_id': itemId,
      'sequence': existing?['sequence'] ?? _nextAgentSequence++,
      'timestamp': timestamp ?? existing?['timestamp'] ?? DateTime.now().toUtc(),
      'data': data,
    };
    if (existing != null && const DeepCollectionEquality().equals(existing, row)) {
      return false;
    }
    _agentRowsByItemId[itemId] = row;
    return true;
  }

  bool _isReconciledByDatasetRows(Map<String, Object?> liveRow) {
    for (final datasetRow in _rowsByItemId.values) {
      if (_datasetRowReconcilesLiveRow(datasetRow: datasetRow, liveRow: liveRow)) {
        return true;
      }
    }
    return false;
  }

  bool _datasetRowReconcilesLiveRow({required Map<String, Object?> datasetRow, required Map<String, Object?> liveRow}) {
    if (_isImageGenerationRow(liveRow) || _isImageGenerationRow(datasetRow)) {
      if (!_imageGenerationRowsReconcile(datasetRow: datasetRow, liveRow: liveRow)) {
        return false;
      }
      final liveMessage = _messageForRow(liveRow);
      final datasetMessage = _messageForRow(datasetRow);
      if (liveMessage?.image == null || datasetMessage?.image == null) {
        return true;
      }
      return _datasetThreadMessageReconcilesLiveMessage(datasetMessage: datasetMessage!, liveMessage: liveMessage!);
    }

    final liveMessage = _messageForRow(liveRow);
    final turnInputPayloadsById = _turnInputPayloadsById([..._rowsByItemId.values, datasetRow]);
    final datasetMessage = _messageForRow(datasetRow, turnInputPayloadsById: turnInputPayloadsById);
    if (liveMessage == null || datasetMessage == null) {
      return false;
    }
    return _datasetThreadMessageReconcilesLiveMessage(datasetMessage: datasetMessage, liveMessage: liveMessage);
  }

  bool _appendAgentRowText({
    required String itemId,
    required String? turnId,
    required String kind,
    required String role,
    required String delta,
    required String? senderName,
    required String? phase,
  }) {
    if (delta.isEmpty) {
      return false;
    }
    final accumulated = kind == 'reasoning'
        ? _liveReasoningContent.appendDelta(itemId: itemId, delta: delta, turnId: turnId, senderName: senderName)
        : _liveTextContent.appendDelta(itemId: itemId, delta: delta, turnId: turnId, senderName: senderName, phase: phase);
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {
        'kind': kind,
        'role': role,
        'status': accumulated.status,
        'text': accumulated.text,
        'sender_name': accumulated.senderName ?? existingData?['sender_name']?.toString(),
        if (accumulated.phase != null) 'phase': accumulated.phase else if (existingData?['phase'] != null) 'phase': existingData?['phase'],
      },
    );
  }

  bool _appendAgentRowUrl({required String itemId, required String? turnId, required String? url, required String? senderName}) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return false;
    }
    final accumulated = _liveFileContent.appendUrl(itemId: itemId, url: normalizedUrl, turnId: turnId, senderName: senderName);
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {
        'kind': 'file',
        'role': 'assistant',
        'status': accumulated.status,
        'urls': accumulated.urls,
        'sender_name': accumulated.senderName ?? existingData?['sender_name']?.toString(),
      },
    );
  }

  bool _appendAgentToolLogs({required String itemId, required String? turnId, required List<String> lines, required String? senderName}) {
    if (itemId.trim().isEmpty || lines.isEmpty) {
      return false;
    }
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final logs = _stringList(existingData?['logs']).toList(growable: true)..addAll(lines);
    final toolkit = existingData?['toolkit']?.toString() ?? '';
    final tool = existingData?['tool']?.toString() ?? 'tool';
    final arguments = _mapValue(existingData?['arguments']);
    final status = existingData?['status']?.toString() ?? 'running';
    final errorMessage = existingData?['error_message']?.toString();
    final argumentDeltaBytes = _intValue(existingData?['argument_delta_bytes']);
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {
        'kind': 'tool_call',
        'role': 'assistant',
        'toolkit': toolkit,
        'tool': tool,
        'status': status,
        'arguments': arguments,
        'logs': logs,
        if (argumentDeltaBytes > 0) 'argument_delta_bytes': argumentDeltaBytes,
        if (errorMessage != null && errorMessage.trim().isNotEmpty) 'error_message': errorMessage,
        'text': formatToolCallEntryText(
          toolkit: toolkit,
          tool: tool,
          arguments: arguments,
          logs: logs,
          errorMessage: errorMessage,
          completed: !_toolCallStatusIsRunning(status),
          pending: _toolCallStatusIsPending(status),
          argumentDeltaBytes: argumentDeltaBytes,
        ),
        'sender_name': senderName ?? existingData?['sender_name']?.toString(),
      },
    );
  }

  bool _appendAgentToolArgumentDelta({
    required String itemId,
    required String? turnId,
    required String delta,
    required String? senderName,
  }) {
    if (itemId.trim().isEmpty || delta.isEmpty) {
      return false;
    }
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final totalDeltaBytes = _intValue(existingData?['argument_delta_bytes']) + utf8.encode(delta).length;
    final toolkit = existingData?['toolkit']?.toString() ?? '';
    final tool = existingData?['tool']?.toString() ?? 'tool';
    final existingArguments = _mapValue(existingData?['arguments']);
    final argumentDeltaText = '${existingData?['argument_delta_text']?.toString() ?? ''}$delta';
    final arguments = _toolArgumentsFromDeltaText(tool: tool, current: existingArguments, text: argumentDeltaText) ?? existingArguments;
    final logs = _stringList(existingData?['logs']);
    final status = existingData?['status']?.toString() ?? 'running';
    final errorMessage = existingData?['error_message']?.toString();
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {
        'kind': 'tool_call',
        'role': 'assistant',
        'toolkit': toolkit,
        'tool': tool,
        'status': status,
        'arguments': arguments,
        'logs': logs,
        'argument_delta_bytes': totalDeltaBytes,
        'argument_delta_text': argumentDeltaText,
        if (errorMessage != null && errorMessage.trim().isNotEmpty) 'error_message': errorMessage,
        'text': formatToolCallEntryText(
          toolkit: toolkit,
          tool: tool,
          arguments: arguments,
          logs: logs,
          errorMessage: errorMessage,
          completed: !_toolCallStatusIsRunning(status),
          pending: _toolCallStatusIsPending(status),
          argumentDeltaBytes: totalDeltaBytes,
        ),
        'sender_name': senderName ?? existingData?['sender_name']?.toString(),
      },
    );
  }

  String _agentRowText(String itemId) {
    return _mapValue(_agentRowsByItemId[itemId]?['data'])?['text']?.toString() ?? '';
  }

  String? _agentRowSenderName(String itemId) {
    final senderName = _mapValue(_agentRowsByItemId[itemId]?['data'])?['sender_name'];
    return senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null;
  }

  void _refreshStatus({bool notify = false}) {
    final next = resolveChatThreadStatus(room: widget.room, path: widget.path, agentName: widget.agentName, previous: _status);
    _status = next;
    _modelController.setLocked(next.turnId != null);
    if (notify && mounted) {
      setState(() {});
    }
  }

  RemoteParticipant? _agentParticipant() {
    return _chatClient?.agentParticipant();
  }

  Future<void> _changeModel(DatasetChatModelOption option) async {
    final session = _threadSession;
    if (session == null || _agentParticipant() == null) {
      throw StateError('No online agent supports agent messages for this thread.');
    }
    await session.changeModel(provider: option.provider, model: option.model);
  }

  Future<void> _changeVoice(String voice) async {
    final session = _threadSession;
    final activeModel = _modelController.activeModel;
    if (session == null || _agentParticipant() == null) {
      throw StateError('No online agent supports agent messages for this thread.');
    }
    if (activeModel == null) {
      throw StateError('No model selected for this thread.');
    }
    await session.changeModel(provider: activeModel.provider, model: activeModel.model, voice: voice);
  }

  bool _handleModelPayload(Map<String, dynamic> payload) {
    final type = payload['type'];
    if (type == agentModelsResponseType) {
      _modelController.applyModelsResponse(payload);
      return true;
    }
    if (payload['thread_id'] != widget.path) {
      return false;
    }
    if (type == agentModelChangedType) {
      _modelController.applyModelChanged(payload);
      return true;
    } else if (type == agentModelsRequestType || type == agentModelChangeType) {
      return true;
    }
    return false;
  }

  List<_DatasetThreadMessage> _messages() {
    final mergedRowsByItemId = <String, Map<String, Object?>>{};
    mergedRowsByItemId.addAll(_agentRowsByItemId);
    for (final entry in _rowsByItemId.entries) {
      final liveRow = mergedRowsByItemId[entry.key];
      mergedRowsByItemId[entry.key] = liveRow == null ? entry.value : _mergeDatasetAndLiveRow(datasetRow: entry.value, liveRow: liveRow);
    }
    final rows = mergedRowsByItemId.values.toList(growable: false)..sort(_compareDatasetThreadRows);
    final turnInputPayloadsById = _turnInputPayloadsById(rows);
    final messagesById = <String, _DatasetThreadMessage>{};
    for (final parsed in _messagesForRows(rows, turnInputPayloadsById: turnInputPayloadsById)) {
      final row = parsed.row;
      final message = parsed.message;
      if (message != null && _shouldRenderDatasetThreadMessage(message)) {
        final messageKey = _datasetThreadMessageDedupeKey(row: row, message: message);
        final existing = messagesById[messageKey];
        messagesById[messageKey] = existing == null ? message : _mergeDuplicateDatasetThreadMessage(existing, message);
      }
    }
    return messagesById.values.toList(growable: false);
  }

  List<({Map<String, Object?> row, _DatasetThreadMessage? message})> _messagesForRows(
    List<Map<String, Object?>> rows, {
    required Map<String, Map<String, Object?>> turnInputPayloadsById,
  }) {
    final messages = <({Map<String, Object?> row, _DatasetThreadMessage? message})>[];
    final toolCallsByItemId = <String, _DatasetToolCallState>{};
    final toolArgumentDeltaBytesByItemId = <String, int>{};
    final toolArgumentDeltaTextByItemId = <String, String>{};
    final textContentByItemId = <String, _DatasetTextContentState>{};
    final reasoningContentByItemId = <String, _DatasetTextContentState>{};
    for (final row in rows) {
      final data = _rowData(row);
      final type = data?['type']?.toString();
      final itemId = _datasetThreadContentItemId(row: row, payload: data, type: type);
      if (type == agentTextContentStartedType || type == agentAudioTranscriptionStartedType || type == agentReasoningContentStartedType) {
        if (data != null) {
          final statesByItemId = type == agentReasoningContentStartedType ? reasoningContentByItemId : textContentByItemId;
          statesByItemId[itemId] = _DatasetTextContentState.fromPayload(
            row: row,
            payload: data,
            kind: type == agentReasoningContentStartedType ? 'reasoning' : 'message',
            role: type == agentAudioTranscriptionStartedType ? _textContentRoleFromPayload(data) : 'assistant',
          );
        }
        continue;
      }
      if (type == agentTextContentDeltaType || type == agentAudioTranscriptionDeltaType || type == agentReasoningContentDeltaType) {
        final statesByItemId = type == agentReasoningContentDeltaType ? reasoningContentByItemId : textContentByItemId;
        final state = statesByItemId.putIfAbsent(
          itemId,
          () => _DatasetTextContentState.fromPayload(
            row: row,
            payload: data ?? const <String, Object?>{},
            kind: type == agentReasoningContentDeltaType ? 'reasoning' : 'message',
            role: type == agentAudioTranscriptionDeltaType ? _textContentRoleFromPayload(data) : 'assistant',
          ),
        );
        state.appendDelta(row: row, payload: data ?? const <String, Object?>{});
        continue;
      }
      if (type == agentTextContentEndedType || type == agentAudioTranscriptionCompletedType || type == agentReasoningContentEndedType) {
        final statesByItemId = type == agentReasoningContentEndedType ? reasoningContentByItemId : textContentByItemId;
        final state = statesByItemId.remove(itemId);
        final message =
            state?.complete(row: row, payload: data ?? const <String, Object?>{}) ??
            (type == agentAudioTranscriptionCompletedType && data != null
                ? _DatasetTextContentState.fromPayload(
                    row: row,
                    payload: data,
                    kind: 'message',
                    role: _textContentRoleFromPayload(data),
                  ).complete(row: row, payload: data)
                : null);
        messages.add((row: row, message: message));
        continue;
      }
      if (_isDatasetToolCallStartType(type)) {
        toolCallsByItemId[itemId] = _DatasetToolCallState.fromPayload(row: row, payload: data!);
        final pendingArgumentDeltaBytes = toolArgumentDeltaBytesByItemId[itemId];
        if (pendingArgumentDeltaBytes != null) {
          toolCallsByItemId[itemId]!.argumentDeltaBytes += pendingArgumentDeltaBytes;
        }
        final pendingArgumentDeltaText = toolArgumentDeltaTextByItemId[itemId];
        if (pendingArgumentDeltaText != null && pendingArgumentDeltaText.isNotEmpty) {
          toolCallsByItemId[itemId]!.appendArgumentDelta(pendingArgumentDeltaText);
        }
        continue;
      }
      if (type == agentToolCallLogDeltaType) {
        final state = toolCallsByItemId[itemId];
        if (state != null) {
          state.logs.addAll(_agentToolCallLogLines(data?['lines']));
        }
        continue;
      }
      if (type == agentToolCallArgumentsDeltaType) {
        final delta = data?['delta']?.toString() ?? '';
        final deltaBytes = utf8.encode(delta).length;
        final state = toolCallsByItemId[itemId];
        if (state != null) {
          state.argumentDeltaBytes += deltaBytes;
          state.appendArgumentDelta(delta);
        } else {
          toolArgumentDeltaBytesByItemId[itemId] = (toolArgumentDeltaBytesByItemId[itemId] ?? 0) + deltaBytes;
          toolArgumentDeltaTextByItemId[itemId] = '${toolArgumentDeltaTextByItemId[itemId] ?? ''}$delta';
        }
        continue;
      }
      if (type == agentToolCallEndedType) {
        final state = toolCallsByItemId.remove(itemId);
        final message = _messageForToolCallEndRow(row: row, payload: data, state: state);
        messages.add((row: row, message: message));
        continue;
      }
      final message = _messageForRow(row, turnInputPayloadsById: turnInputPayloadsById);
      messages.add((row: row, message: message));
    }
    for (final state in [...textContentByItemId.values, ...reasoningContentByItemId.values]) {
      messages.add((row: state.latestRow, message: state.toMessage(row: state.latestRow)));
    }
    return messages;
  }

  Map<String, Map<String, Object?>> _turnInputPayloadsById(Iterable<Map<String, Object?>> rows) {
    final payloadsById = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final data = _rowData(row);
      final type = data?['type']?.toString();
      if (type != agentTurnStartType && type != agentTurnSteerType) {
        continue;
      }
      final messageId = data?['message_id']?.toString().trim();
      final rowItemId = row['item_id']?.toString().trim();
      final inputId = messageId != null && messageId.isNotEmpty ? messageId : rowItemId;
      if (inputId != null && inputId.isNotEmpty && data != null) {
        payloadsById[inputId] = data;
      }
    }
    return payloadsById;
  }

  bool _hasWireBackedContent() {
    return _agentRowsByItemId.values.any((row) {
          final kind = _rowData(row)?['kind'];
          return kind != 'usage';
        }) ||
        _status.pendingMessages.isNotEmpty ||
        _controller.pendingAgentMessagesForPath(widget.path).isNotEmpty;
  }

  bool _shouldRenderDatasetThreadMessage(_DatasetThreadMessage message) {
    final image = message.image;
    if (image != null) {
      final hasImageReference = _stringValue(image.imageId) != null || _stringValue(image.uri) != null;
      if (!hasImageReference && !_isImageGenerationPendingStatus(image.status) && !_isImageGenerationFailedStatus(image.status)) {
        return false;
      }
    }
    return true;
  }

  List<PendingAgentMessage> _combinedPendingMessages(List<_DatasetThreadMessage> messages) {
    final combined = <String, PendingAgentMessage>{};
    for (final pending in _status.pendingMessages) {
      combined[pending.messageId] = pending;
    }
    for (final pending in _controller.pendingAgentMessagesForPath(widget.path)) {
      combined[pending.messageId] = pending;
    }
    for (final pending in _pendingSteeringMessagesFromDatasetRows()) {
      combined[pending.messageId] = pending;
    }
    final values = combined.values.where((pending) {
      return !messages.any((message) => _datasetThreadMessageMatchesPendingAgentMessage(message, pending));
    }).toList();
    return [...values.where((message) => !message.awaitingAcceptance), ...values.where((message) => message.awaitingAcceptance)];
  }

  List<PendingAgentMessage> _pendingSteeringMessagesFromDatasetRows() {
    final pendingByMessageId = <String, PendingAgentMessage>{};
    final rows = [..._rowsByItemId.values, ..._agentRowsByItemId.values]..sort(_compareDatasetThreadRows);
    for (final row in rows) {
      final data = _rowData(row);
      final type = data?['type']?.toString();
      if (type == agentTurnSteeredType || type == agentTurnSteerRejectedType) {
        final sourceMessageId = data?['source_message_id']?.toString();
        if (sourceMessageId != null && sourceMessageId.trim().isNotEmpty) {
          pendingByMessageId.remove(sourceMessageId.trim());
        }
        continue;
      }
      if (type == agentTurnSteerAcceptedType) {
        final sourceMessageId = data?['source_message_id']?.toString();
        final existing = sourceMessageId == null ? null : pendingByMessageId[sourceMessageId.trim()];
        if (existing != null && existing.awaitingAcceptance) {
          pendingByMessageId[existing.messageId] = PendingAgentMessage(
            messageId: existing.messageId,
            messageType: existing.messageType,
            threadPath: existing.threadPath,
            text: existing.text,
            attachments: existing.attachments,
            senderName: existing.senderName,
            createdAt: existing.createdAt,
            awaitingAcceptance: false,
            awaitingApplication: existing.awaitingApplication,
          );
        }
        continue;
      }
      if (type != agentTurnSteerType || data == null) {
        continue;
      }
      final sourceMessageId = data['message_id']?.toString() ?? row['item_id']?.toString();
      if (sourceMessageId == null || sourceMessageId.trim().isEmpty) {
        continue;
      }
      final content = data['content'];
      if (content is! List) {
        continue;
      }
      final extracted = _agentInputContentParts(content);
      if (extracted.text.trim().isEmpty && extracted.attachments.isEmpty) {
        continue;
      }
      pendingByMessageId[sourceMessageId.trim()] = PendingAgentMessage(
        messageId: sourceMessageId.trim(),
        messageType: agentTurnSteerType,
        threadPath: widget.path,
        text: extracted.text,
        attachments: extracted.attachments,
        senderName: data['sender_name']?.toString(),
        createdAt: _rowTimestamp(row),
        awaitingAcceptance: true,
        awaitingApplication: true,
      );
    }
    return pendingByMessageId.values.toList(growable: false);
  }

  bool _canInterruptActiveTurn() {
    final turnId = _status.turnId;
    return _status.supportsAgentMessages && turnId != null && turnId.trim().isNotEmpty;
  }

  Future<void> _cancelTurn() async {
    final turnId = _status.turnId;
    if (turnId == null || turnId.trim().isEmpty) {
      return;
    }
    await _audioPlayer.stopAll();
    final session = _threadSession;
    if (session == null || _agentParticipant() == null) {
      return;
    }
    await session.interruptTurn(turnId);
  }

  Future<void> _sendRealtimeAudioChunk(Uint8List chunk, {required bool finalChunk}) async {
    final activeModel = _modelController.activeModel;
    final activeVoice = _modelController.activeVoice;
    final inputFormat = _modelController.activeInputFormat;
    if (finalChunk) {
      if (_modelController.activeTurnDetection == 'automatic') {
        return;
      }
      final turnId = const Uuid().v4();
      final session = _threadSession;
      if (session == null) {
        throw StateError('No thread session is open.');
      }
      await session.commitRealtimeAudio(
        turnId: turnId,
        provider: activeModel?.provider,
        model: activeModel?.model,
        voice: activeVoice,
        outputModalities: [_modelController.activeModality],
      );
      return;
    }
    final session = _threadSession;
    if (session == null) {
      throw StateError('No thread session is open.');
    }
    await session.sendRealtimeAudioChunk(chunk: chunk, format: inputFormat.toJson());
  }

  Future<void> _send(String value, List<FileAttachment> attachments) async {
    final threadPath = widget.path;
    final isSteer = _status.mode == 'steerable' && _status.turnId != null;
    final messageId = const Uuid().v4();
    final attachmentPaths = attachments.map((attachment) => attachment.path).toList(growable: false);
    final senderName = widget.room.localParticipant?.getAttribute('name');
    _controller.markPendingAgentMessage(
      PendingAgentMessage(
        messageId: messageId,
        messageType: isSteer ? agentTurnSteerType : agentTurnStartType,
        threadPath: threadPath,
        text: value,
        attachments: attachmentPaths,
        senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
        createdAt: DateTime.now(),
        awaitingAcceptance: true,
      ),
    );
    _controller.outboundStatus.markSending(messageId);

    try {
      final activeModel = _modelController.activeModel;
      final session = _threadSession;
      if (session == null) {
        throw StateError('No thread session is open.');
      }
      await session.sendText(
        messageId: messageId,
        text: value,
        attachments: attachmentPaths,
        steer: isSteer,
        turnId: _status.turnId,
        provider: activeModel?.provider,
        model: activeModel?.model,
        outputModalities: isSteer ? null : [_modelController.activeModality],
        senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
      );
      _controller.outboundStatus.markDelivered(messageId);
      _controller.clear();
    } on ChatSendCancelledException {
      _controller.outboundStatus.clear(messageId);
      _controller.clearPendingAgentMessagesForThread(threadPath);
    } catch (error, stackTrace) {
      _controller.outboundStatus.markFailed(messageId, error, stackTrace);
      _controller.clearPendingAgentMessagesForThread(threadPath);
      rethrow;
    }
  }

  ChatThreadSnapshot _snapshot(List<_DatasetThreadMessage> messages, List<PendingAgentMessage> pendingMessages) {
    final agent = _agentParticipant();
    final localParticipant = widget.room.localParticipant;
    final online = <Participant>[?localParticipant, ?agent];
    return ChatThreadSnapshot(
      messages: const [],
      online: online,
      offline: const [],
      typing: const [],
      listening: const [],
      agentOnline: agent != null,
      threadStatus: _status.text,
      threadStatusStartedAt: _status.startedAt,
      threadStatusMode: _status.mode,
      threadStatusTotalBytes: _status.totalBytes,
      threadStatusLinesAdded: _status.linesAdded,
      threadStatusLinesRemoved: _status.linesRemoved,
      supportsAgentMessages: agent != null,
      supportsMcp: agent?.getAttribute('supports_mcp') == true,
      toolkits: const <String, ToolkitCapabilities>{},
      threadTurnId: _status.turnId,
      pendingMessages: pendingMessages,
      pendingItemId: _status.pendingItemId,
      usage: _usage,
    );
  }

  Widget? _buildUsageFooter(BuildContext context, AgentUsageSnapshot? usage) {
    if (!widget.showUsageFooter) {
      return null;
    }

    final theme = ShadTheme.of(context);
    final label = usage == null ? '' : _formatUsageFooter(usage);
    final text = Text(
      label,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.small.copyWith(color: theme.colorScheme.mutedForeground, fontSize: 11),
    );
    if (usage == null) {
      return text;
    }
    return UsageFooterTooltip(
      tooltip: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Text(_formatUsageTooltip(usage), style: ShadTheme.of(context).textTheme.small),
      ),
      child: text,
    );
  }

  Widget _buildComposerWithUsageFooter(BuildContext context, {required Widget input, required AgentUsageSnapshot? usage}) {
    final usageFooter = _buildUsageFooter(context, usage);
    if (usageFooter == null) {
      return input;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, right: 8),
          child: Align(alignment: Alignment.centerRight, child: usageFooter),
        ),
      ],
    );
  }

  String _formatUsageFooter(AgentUsageSnapshot usage) {
    var contextLabel = _formatTokenCount(usage.contextUsedTokens);
    final contextLimitTokens = usage.compactionThreshold ?? usage.contextTotalTokens;
    if (contextLimitTokens != null) {
      contextLabel = '$contextLabel/${_formatTokenCount(contextLimitTokens)}';
    }
    return 'context $contextLabel';
  }

  String _formatUsageTooltip(AgentUsageSnapshot usage) {
    final entries = usage.usage.entries.toList()..sort((left, right) => left.key.compareTo(right.key));
    final lines = <String>['context used: ${_formatTokenCount(usage.contextUsedTokens)}'];
    final compactionMode = usage.compactionMode;
    if (compactionMode != null) {
      lines.add('context management: $compactionMode');
      final threshold = usage.compactionThreshold;
      if (threshold != null) {
        lines.add('context threshold: ${_formatTokenCount(threshold)}');
      }
    }
    final contextTotalTokens = usage.contextTotalTokens;
    if (usage.compactionThreshold != null && contextTotalTokens != null) {
      lines.add('model window: ${_formatTokenCount(contextTotalTokens)}');
    }
    lines.addAll(entries.map((entry) => '${entry.key}: ${_formatTokenCount(entry.value)}'));
    return lines.join('\n');
  }

  String _formatTokenCount(num value) {
    final count = value.toDouble();
    final magnitude = count.abs();
    if (magnitude >= 1000000) {
      return '${_trimFixed(count / 1000000)}M';
    }
    if (magnitude >= 1000) {
      return '${_trimFixed(count / 1000)}K';
    }
    return count.round().toString();
  }

  String _trimFixed(double value) {
    final fixed = value.toStringAsFixed(1);
    if (fixed.endsWith('.0')) {
      return fixed.substring(0, fixed.length - 2);
    }
    return fixed;
  }

  void _hideThreadImageViewer() {
    _imageViewerController.hide();
    if (mounted) {
      setState(() {});
    }
  }

  void _closeThreadImageViewer() {
    final historyEntry = _imageViewerHistoryEntry;
    if (historyEntry != null) {
      _imageViewerHistoryEntry = null;
      historyEntry.remove();
      return;
    }
    _hideThreadImageViewer();
  }

  void _openThreadImageViewer(BuildContext context, {required List<ChatThreadFeedImage> images, required int initialIndex}) {
    if (images.isEmpty) {
      return;
    }

    final route = ModalRoute.of(context);
    if (_imageViewerHistoryEntry == null && route != null) {
      final historyEntry = LocalHistoryEntry(
        onRemove: () {
          _imageViewerHistoryEntry = null;
          _hideThreadImageViewer();
        },
      );
      _imageViewerHistoryEntry = historyEntry;
      route.addLocalHistoryEntry(historyEntry);
    }

    final clampedInitialIndex = initialIndex.clamp(0, images.length - 1);
    setState(() {
      _overlayImages = List<ChatThreadFeedImage>.unmodifiable(images);
      _overlayInitialIndex = clampedInitialIndex;
    });
    _imageViewerController.show();
  }

  List<ChatThreadFeedImage> _collectThreadImages(List<_DatasetThreadMessage> messages) {
    final imagesInThread = <ChatThreadFeedImage>[];
    for (final message in messages) {
      final image = message.image;
      if (image == null) {
        continue;
      }

      final imageId = image.imageId?.trim() ?? "";
      final imageUri = image.uri?.trim();
      if (imageId.isEmpty && (imageUri == null || imageUri.isEmpty)) {
        continue;
      }

      imagesInThread.add(
        ChatThreadFeedImage(
          attachmentElementId: message.id,
          imageId: imageId,
          imageUri: imageUri,
          mimeType: image.mimeType,
          status: image.status,
          statusDetail: image.statusDetail,
          widthPx: image.width,
          heightPx: image.height,
        ),
      );
    }
    return imagesInThread;
  }

  Widget _buildInput(BuildContext context, ChatThreadSnapshot snapshot, List<PendingAgentMessage> pendingMessages) {
    PendingAgentMessage? waitingForOnlineMessage;
    for (final pending in pendingMessages) {
      if (pending.awaitingOnline) {
        waitingForOnlineMessage = pending;
        break;
      }
    }
    final toolArea = resolveChatThreadToolArea(widget.toolsBuilder == null ? null : widget.toolsBuilder!(context, _controller, snapshot));
    return AnimatedBuilder(
      animation: _modelController,
      builder: (context, _) => ChatThreadInput(
        key: _composerInputKey,
        focusTrigger: _controller,
        sendEnabled: waitingForOnlineMessage == null,
        sendDisabledReason: waitingForOnlineMessage == null
            ? null
            : 'Waiting for ${_displayAgentName(widget.agentName ?? "agent")} to come online.',
        onCancelSend: null,
        onInterrupt: _canInterruptActiveTurn() ? _cancelTurn : null,
        sendPendingText: waitingForOnlineMessage == null
            ? null
            : 'Waiting for ${_displayAgentName(widget.agentName ?? "agent")} to come online.',
        placeholder: widget.inputPlaceholder,
        leading: toolArea.leading,
        footer: toolArea.footer,
        audioInputEnabled: _modelController.supportsAudioInput,
        automaticAudioTurnDetection: _modelController.activeTurnDetection == 'automatic',
        onAudioChunk: _sendRealtimeAudioChunk,
        room: widget.room,
        controller: _controller,
        attachmentBuilder: widget.attachmentBuilder,
        contextMenuBuilder: widget.inputContextMenuBuilder,
        onPressedOutside: widget.inputOnPressedOutside,
        onSend: _send,
      ),
    );
  }

  Widget _buildMessage(
    BuildContext context,
    _DatasetThreadMessage message, {
    required List<ChatThreadFeedImage> feedImages,
    required bool shouldShowParticipantHeader,
  }) {
    final theme = ShadTheme.of(context);
    if (message.kind != 'message') {
      if (message.kind == 'tool_call') {
        final expanded = _expandedToolCallIds.contains(message.id);
        final toolCallEntry = message.toolCallEntry ?? _toolCallEntryFromText(message.text);
        final expandedToolCallEntry = message.expandedToolCallEntry;
        final diffPreviewBlocks = message.diffPreviewBlocks;
        final canExpand = expandedToolCallEntry != null && expandedToolCallEntry.text != toolCallEntry.text;
        return Padding(
          padding: const EdgeInsets.only(left: 42, right: 18),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToolCallSummaryText(
                  context,
                  expanded && expandedToolCallEntry != null ? expandedToolCallEntry : toolCallEntry,
                  canExpand: canExpand,
                  onTapDetails: () {
                    if (!canExpand) {
                      return;
                    }
                    setState(() {
                      if (!_expandedToolCallIds.add(message.id)) {
                        _expandedToolCallIds.remove(message.id);
                      }
                    });
                  },
                ),
                if (diffPreviewBlocks.isNotEmpty || expanded)
                  for (final block in diffPreviewBlocks) _buildDatasetDiffPreviewBlock(context, block: block),
              ],
            ),
          ),
        );
      }
      if (message.kind == 'error') {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.center,
              child: SelectableText(
                message.text,
                style: theme.textTheme.muted.copyWith(color: theme.colorScheme.destructive),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.center,
            child: Text(
              message.text,
              style: theme.textTheme.muted.copyWith(color: theme.colorScheme.mutedForeground),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final localParticipantName = widget.room.localParticipant?.getAttribute('name');
    final isAgentMessage = message.role == 'agent';
    final rawAuthorName = message.authorName;
    final authorName = rawAuthorName == null || rawAuthorName.trim().isEmpty ? null : rawAuthorName;
    final mine =
        !isAgentMessage &&
        (rawAuthorName == localParticipantName || ((rawAuthorName == null || rawAuthorName.trim().isEmpty) && message.role == 'user'));
    final imageAttachmentId = message.id;
    final imageInitialIndex = feedImages.indexWhere((entry) => entry.attachmentElementId == imageAttachmentId);

    return ChatThreadMessageView(
      key: ValueKey(message.id),
      room: widget.room,
      mine: mine,
      isAgentMessage: isAgentMessage,
      text: message.text,
      authorName: authorName ?? '',
      createdAt: message.createdAt,
      shouldShowHeader: shouldShowParticipantHeader,
      attachmentWidgets: [
        for (final attachment in message.attachments)
          GestureDetector(
            onTap: widget.openFile == null ? null : () => widget.openFile!(_previewPath(attachment)),
            child: ChatThreadPreview(room: widget.room, path: _previewPath(attachment)),
          ),
        if (message.image != null)
          ChatThreadImageAttachment(
            room: widget.room,
            imageId: message.image!.imageId,
            imageUri: message.image!.uri,
            fallbackMimeType: message.image!.mimeType,
            status: message.image!.status,
            statusDetail: message.image!.statusDetail,
            widthPx: message.image!.width,
            heightPx: message.image!.height,
            roundedCorners: false,
            onOpenFullscreen: imageInitialIndex == -1
                ? null
                : () => _openThreadImageViewer(context, images: feedImages, initialIndex: imageInitialIndex),
          ),
      ],
    );
  }

  String? _datasetMessageParticipantKey(_DatasetThreadMessage message) {
    if (message.kind == 'compaction') {
      return null;
    }
    final authorName = message.authorName?.trim();
    if (authorName != null && authorName.isNotEmpty) {
      return '${message.role}:$authorName';
    }
    if (message.role == 'agent') {
      final agentName = widget.agentName?.trim();
      if (agentName != null && agentName.isNotEmpty) {
        return '${message.role}:$agentName';
      }
    }
    return message.role;
  }

  List<Widget> _buildMessageWidgets(
    BuildContext context,
    List<_DatasetThreadMessage> messages,
    List<PendingAgentMessage> pendingMessages, {
    required List<ChatThreadFeedImage> feedImages,
  }) {
    final messageWidgets = <Widget>[];
    final feedItems = _buildFeedItems(messages);
    for (final item in feedItems.indexed) {
      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(0, SizedBox(height: _datasetThreadFeedItemSpacing(feedItems[item.$1 - 1], item.$2)));
      }
      final feedItem = item.$2;
      switch (feedItem) {
        case _DatasetThreadMessageFeedItem():
          messageWidgets.insert(
            0,
            Container(
              key: ValueKey(feedItem.message.id),
              child: _buildMessage(
                context,
                feedItem.message,
                feedImages: feedImages,
                shouldShowParticipantHeader: _shouldShowParticipantHeaderForFeedItem(feedItems, item.$1),
              ),
            ),
          );
        case _DatasetThreadDetailGroupFeedItem():
          messageWidgets.insert(
            0,
            _DatasetDetailLine(
              key: ValueKey(feedItem.id),
              text: feedItem.collapsedText,
              authorName: feedItem.authorName,
              createdAt: feedItem.createdAt,
              onTap: () {
                setState(() {
                  _expandedDetailGroupIds.add(feedItem.id);
                });
              },
            ),
          );
      }
    }
    final pendingFeedMessages = pendingMessages.where((pending) {
      if (pending.messageType == agentTurnSteerType || pending.matchByContentOnly) {
        return false;
      }
      return pending.awaitingApplication || !messages.any((message) => message.id == pending.messageId);
    });
    for (final pending in pendingFeedMessages) {
      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(0, const SizedBox(height: ChatThreadMessageView.chatMessageStackSpacing));
      }
      messageWidgets.insert(0, PendingChatThreadMessage(room: widget.room, message: pending));
    }
    return messageWidgets;
  }

  List<_DatasetThreadFeedItem> _buildFeedItems(List<_DatasetThreadMessage> messages) {
    final items = <_DatasetThreadFeedItem>[];
    var index = 0;
    while (index < messages.length) {
      final segmentEnd = _nextUserMessageIndex(messages, index + 1) ?? messages.length;
      final detailIndexes = <int>{};
      _addDatasetThreadDetailIndexesForSegment(messages, index, segmentEnd, detailIndexes);
      final detailMessages = detailIndexes.toList(growable: false)..sort();
      final groupedMessages = detailMessages.map((detailIndex) => messages[detailIndex]).toList(growable: false);
      var insertedDetailGroup = false;
      for (var segmentIndex = index; segmentIndex < segmentEnd; segmentIndex += 1) {
        if (!detailIndexes.contains(segmentIndex)) {
          items.add(_DatasetThreadMessageFeedItem(messages[segmentIndex]));
          continue;
        }
        if (insertedDetailGroup || groupedMessages.isEmpty) {
          continue;
        }
        final group = _detailGroupForMessages(
          groupedMessages,
          nextMessage: _nextNonDetailMessage(messages, detailIndexes, segmentIndex + 1, segmentEnd),
        );
        if (_expandedDetailGroupIds.contains(group.id)) {
          items.addAll(group.messages.map(_DatasetThreadMessageFeedItem.new));
        } else {
          items.add(group);
        }
        insertedDetailGroup = true;
      }
      index = segmentEnd;
    }
    return items;
  }

  _DatasetThreadMessage? _nextNonDetailMessage(List<_DatasetThreadMessage> messages, Set<int> detailIndexes, int start, int end) {
    for (var index = start; index < end; index += 1) {
      if (!detailIndexes.contains(index)) {
        return messages[index];
      }
    }
    return null;
  }

  int? _nextUserMessageIndex(List<_DatasetThreadMessage> messages, int start) {
    for (var index = start; index < messages.length; index += 1) {
      final message = messages[index];
      if (message.kind == 'message' && message.role == 'user') {
        return index;
      }
    }
    return null;
  }

  void _addDatasetThreadDetailIndexesForSegment(List<_DatasetThreadMessage> messages, int start, int end, Set<int> detailIndexes) {
    final finalAgentMessageIndex = _finalAgentMessageIndexForSegment(messages, start, end);
    for (var index = start; index < end; index += 1) {
      final message = messages[index];
      if (_datasetThreadMessageIsIntrinsicDetail(message)) {
        detailIndexes.add(index);
        continue;
      }
      if (index != finalAgentMessageIndex && _datasetThreadMessageCanCollapseAsCommentary(message)) {
        detailIndexes.add(index);
      }
    }
  }

  int _finalAgentMessageIndexForSegment(List<_DatasetThreadMessage> messages, int start, int end) {
    var explicitFinalIndex = -1;
    for (var index = start; index < end; index += 1) {
      final message = messages[index];
      if (_datasetThreadMessageCanRenderAsFinalAnswer(message) && message.phase == 'final_answer') {
        explicitFinalIndex = index;
      }
    }
    if (explicitFinalIndex != -1) {
      return explicitFinalIndex;
    }

    var inferredFinalIndex = -1;
    for (var index = start; index < end; index += 1) {
      final message = messages[index];
      if (_datasetThreadMessageCanRenderAsFinalAnswer(message)) {
        inferredFinalIndex = index;
      }
    }
    return inferredFinalIndex;
  }

  _DatasetThreadDetailGroupFeedItem _detailGroupForMessages(List<_DatasetThreadMessage> messages, {_DatasetThreadMessage? nextMessage}) {
    final first = messages.first;
    final collapsedMessage = _detailGroupCollapsedMessage(messages);
    final id = ['details', first.turnId ?? '', first.id, first.createdAt.microsecondsSinceEpoch].join(':');
    return _DatasetThreadDetailGroupFeedItem(
      id: id,
      messages: List<_DatasetThreadMessage>.unmodifiable(messages),
      collapsedText: _detailGroupCollapsedText(messages, nextMessage: nextMessage),
      authorName: _detailGroupAuthorName(collapsedMessage ?? first),
      createdAt: collapsedMessage?.createdAt ?? first.createdAt,
    );
  }

  String _detailGroupCollapsedText(List<_DatasetThreadMessage> messages, {_DatasetThreadMessage? nextMessage}) {
    final first = messages.first;
    if (_detailGroupHasFinalResponse(messages, nextMessage: nextMessage)) {
      final finalMessage = nextMessage!;
      final end = _status.turnId != null && first.turnId == _status.turnId ? DateTime.now() : finalMessage.createdAt;
      return 'Worked for ${_formatDetailGroupDuration(end.difference(first.createdAt))}';
    }
    return _firstNonEmptyLine(_detailGroupCollapsedMessage(messages)?.text ?? '') ?? 'Working';
  }

  _DatasetThreadMessage? _detailGroupCollapsedMessage(List<_DatasetThreadMessage> messages) {
    for (final message in messages.reversed) {
      if (_datasetThreadMessageCanCollapseAsCommentary(message) && message.text.trim().isNotEmpty) {
        return message;
      }
    }
    for (final message in messages.reversed) {
      if (message.kind == 'reasoning' && message.text.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  String _detailGroupAuthorName(_DatasetThreadMessage message) {
    final authorName = message.authorName?.trim();
    if (authorName != null && authorName.isNotEmpty) {
      return authorName;
    }
    if (message.role == 'agent') {
      final agentName = widget.agentName?.trim();
      if (agentName != null && agentName.isNotEmpty) {
        return agentName;
      }
    }
    return '';
  }

  bool _detailGroupHasFinalResponse(List<_DatasetThreadMessage> messages, {_DatasetThreadMessage? nextMessage}) {
    return _datasetThreadMessageIsFinalAgentMessage(nextMessage) && _messagesShareTurn(messages.first, nextMessage!);
  }

  bool _datasetThreadMessageIsIntrinsicDetail(_DatasetThreadMessage message) {
    if (message.kind == 'tool_call' || message.kind == 'reasoning') {
      return true;
    }
    return _datasetThreadMessageCanCollapseAsCommentary(message) && message.phase == 'commentary';
  }

  bool _datasetThreadMessageCanCollapseAsCommentary(_DatasetThreadMessage message) {
    if (message.phase == 'final_answer') {
      return false;
    }
    return message.kind == 'message' && message.role == 'agent' && message.attachments.isEmpty && message.image == null;
  }

  bool _datasetThreadMessageCanRenderAsFinalAnswer(_DatasetThreadMessage message) {
    if (message.kind != 'message' || message.role != 'agent' || message.phase == 'commentary') {
      return false;
    }
    return message.text.trim().isNotEmpty || message.attachments.isNotEmpty || message.image != null;
  }

  bool _datasetThreadMessageIsFinalAgentMessage(_DatasetThreadMessage? message) {
    return message != null && _datasetThreadMessageCanRenderAsFinalAnswer(message);
  }

  bool _messagesShareTurn(_DatasetThreadMessage left, _DatasetThreadMessage right) {
    if (left.turnId == null || left.turnId!.trim().isEmpty || right.turnId == null || right.turnId!.trim().isEmpty) {
      return true;
    }
    return left.turnId == right.turnId;
  }

  String? _firstNonEmptyLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  String _formatDetailGroupDuration(Duration duration) {
    final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds == 0 ? '${minutes}m' : '${minutes}m ${remainingSeconds}s';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
  }

  bool _shouldShowParticipantHeaderForFeedItem(List<_DatasetThreadFeedItem> items, int index) {
    final item = items[index];
    if (item is! _DatasetThreadMessageFeedItem) {
      return false;
    }
    final message = item.message;
    if (message.kind != 'message') {
      return false;
    }
    final authorName = message.authorName?.trim();
    if (message.role == 'agent' && (authorName == null || authorName.isEmpty)) {
      return false;
    }
    if (index == 0) {
      return true;
    }
    for (final previous in items.take(index).toList().reversed) {
      if (previous is! _DatasetThreadMessageFeedItem) {
        return true;
      }
      final previousKey = _datasetMessageParticipantKey(previous.message);
      if (previousKey == null) {
        continue;
      }
      return previousKey != _datasetMessageParticipantKey(message);
    }
    return true;
  }

  double _datasetThreadMessageSpacing(_DatasetThreadMessage previous, _DatasetThreadMessage next) {
    if (previous.kind == 'tool_call' || next.kind == 'tool_call') {
      return 10;
    }
    return ChatThreadMessageView.chatMessageStackSpacing;
  }

  double _datasetThreadFeedItemSpacing(_DatasetThreadFeedItem previous, _DatasetThreadFeedItem next) {
    final previousMessage = previous is _DatasetThreadMessageFeedItem ? previous.message : null;
    final nextMessage = next is _DatasetThreadMessageFeedItem ? next.message : null;
    if (previousMessage == null || nextMessage == null) {
      return 10;
    }
    return _datasetThreadMessageSpacing(previousMessage, nextMessage);
  }

  Widget _buildToolCallSummaryText(
    BuildContext context,
    ToolCallEntryDisplay display, {
    required bool canExpand,
    required VoidCallback onTapDetails,
  }) {
    final theme = ShadTheme.of(context);
    final baseStyle = theme.textTheme.muted.copyWith(color: theme.colorScheme.mutedForeground);
    final highlightStyle = baseStyle.copyWith(color: theme.colorScheme.foreground, fontWeight: FontWeight.w700);
    final detailLines = display.detailLines;
    final headlineRest = display.headline.rest;
    final lineCountStyle = baseStyle.copyWith(fontWeight: FontWeight.w700);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in detailLines.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: _buildToolCallDetailGutter(display, entry.$1, baseStyle, canExpand: canExpand, onTapDetails: onTapDetails),
              ),
              Expanded(
                child: _buildToolCallDetailText(
                  context,
                  entry.$2,
                  style: baseStyle,
                  languageOrFilename: display.headline.detailLanguageOrFilename,
                ),
              ),
            ],
          ),
      ],
    );
    final header = SelectionArea(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(text: display.headline.action, style: highlightStyle),
                  if (headlineRest.trim().isNotEmpty) TextSpan(text: ' $headlineRest'),
                ],
              ),
              style: baseStyle,
              textAlign: TextAlign.left,
            ),
          ),
          if (display.headline.linesAdded != null || display.headline.linesRemoved != null) const SizedBox(width: 8),
          if (display.headline.linesAdded != null)
            StatusSignedCounter(value: display.headline.linesAdded!, prefix: '+', style: lineCountStyle, color: Colors.green.shade500),
          if (display.headline.linesAdded != null && display.headline.linesRemoved != null) const SizedBox(width: 6),
          if (display.headline.linesRemoved != null)
            StatusSignedCounter(value: display.headline.linesRemoved!, prefix: '-', style: lineCountStyle, color: Colors.red.shade500),
        ],
      ),
    );
    final headerWidget = canExpand
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTapDetails, child: header),
          )
        : header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [headerWidget, if (detailLines.isNotEmpty) details],
    );
  }

  Widget? _buildToolCallDetailGutter(
    ToolCallEntryDisplay display,
    int index,
    TextStyle style, {
    required bool canExpand,
    required VoidCallback onTapDetails,
  }) {
    if (display.detailsTruncated && index == 0) {
      final marker = Text('…', style: style);
      if (!canExpand) {
        return marker;
      }
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SelectionContainer.disabled(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTapDetails, child: marker),
        ),
      );
    }
    if (index == 0) {
      return Text('└', style: style);
    }
    return null;
  }

  Widget _buildToolCallDetailText(BuildContext context, String text, {required TextStyle style, required String? languageOrFilename}) {
    if (languageOrFilename == null) {
      return SelectableText(text, style: style, textAlign: TextAlign.left);
    }
    final codeStyle = GoogleFonts.sourceCodePro(textStyle: style);
    return SelectableText.rich(
      highlightCodeSpanWithReHighlight(context: context, code: text, languageOrFilename: languageOrFilename, textStyle: codeStyle),
      textAlign: TextAlign.left,
    );
  }

  Widget _buildDatasetDiffPreviewBlock(BuildContext context, {required _DatasetDiffPreviewBlock block}) {
    final normalizedCode = block.code.replaceAll('\r\n', '\n').trimRight();
    if (normalizedCode.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = ShadTheme.of(context);
    final codeTextStyle = GoogleFonts.sourceCodePro(fontSize: 12, color: const Color(0xFFE5E7EB), height: 1.3);
    final headerTextStyle = GoogleFonts.sourceCodePro(fontSize: 11, color: theme.colorScheme.mutedForeground);
    final headerCounterStyle = headerTextStyle.copyWith(fontWeight: FontWeight.w700);
    final lines = normalizedCode.split('\n');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: _datasetDiffPreviewHorizontalPadding, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: SelectionArea(
              child: Row(
                children: [
                  Flexible(
                    child: Text(block.header, style: headerTextStyle, overflow: TextOverflow.ellipsis),
                  ),
                  if (block.linesAdded != null || block.linesRemoved != null) const SizedBox(width: 8),
                  if (block.linesAdded != null)
                    StatusSignedCounter(value: block.linesAdded!, prefix: '+', style: headerCounterStyle, color: Colors.green.shade500),
                  if (block.linesAdded != null && block.linesRemoved != null) const SizedBox(width: 6),
                  if (block.linesRemoved != null)
                    StatusSignedCounter(value: block.linesRemoved!, prefix: '-', style: headerCounterStyle, color: Colors.red.shade500),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: _datasetDiffPreviewHorizontalPadding, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines.indexed)
                  Padding(
                    padding: EdgeInsets.only(bottom: line.$1 < lines.length - 1 ? 2 : 0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: diffLineBackgroundColor(context, line.$2), borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: SelectableText.rich(
                        highlightCodeSpanWithReHighlight(
                          context: context,
                          code: line.$2,
                          languageOrFilename: 'diff',
                          textStyle: codeTextStyle,
                          theme: monokaiSublimeTheme,
                          fallbackLanguageId: 'diff',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ToolCallEntryDisplay _toolCallEntryFromText(String text) {
    final lines = text.split('\n');
    return ToolCallEntryDisplay(
      headline: ToolCallHeadline(action: lines.first),
      detailLines: lines.skip(1).toList(growable: false),
    );
  }

  Widget? _buildQueuedPendingMessages(
    BuildContext context,
    List<_DatasetThreadMessage> messages,
    List<PendingAgentMessage> pendingMessages,
  ) {
    final queuedPendingMessages = pendingMessages
        .where(
          (pending) =>
              (pending.messageType == agentTurnStartType || pending.messageType == agentTurnSteerType) &&
              !_pendingDatasetMessageIsOptimisticallyRendered(pending: pending, messages: messages),
        )
        .toList(growable: false);
    if (queuedPendingMessages.isEmpty) {
      return null;
    }
    final textStyle = TextStyle(fontSize: 13, color: ShadTheme.of(context).colorScheme.mutedForeground);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 10),
          const SizedBox(width: 24, height: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pending messages:', style: textStyle),
                const SizedBox(height: 4),
                for (final pending in queuedPendingMessages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      [
                        if (pending.senderName != null) '${_displayAgentName(pending.senderName!)}:',
                        if (pending.text.trim().isNotEmpty) pending.text.trim(),
                        if (pending.attachments.isNotEmpty)
                          '${pending.attachments.length} attachment${pending.attachments.length == 1 ? "" : "s"}',
                      ].join(' '),
                      style: textStyle,
                    ),
                  ),
                if (_canInterruptActiveTurn())
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Messages will be processed shortly. Press Esc to interrupt and send now.', style: textStyle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadViewport(
    BuildContext context,
    List<_DatasetThreadMessage> messages,
    List<PendingAgentMessage> pendingMessages, {
    bool loading = false,
  }) {
    final showStatus = shouldShowChatThreadStatus(_status);
    final feedImages = _collectThreadImages(messages);
    const loadingContent = CircularProgressIndicator();
    final threadView = ChatThreadViewportBody(
      scrollController: _controller.threadScrollController,
      bottomAlign: true,
      centerContent: loading ? loadingContent : null,
      bottomSpacer: showStatus ? 20 : 0,
      overlays: [
        if (showStatus)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.symmetric(horizontal: chatThreadStatusHorizontalPadding(constraints.maxWidth)),
                child: ChatThreadProcessingStatusRow(
                  text: _status.text!,
                  startedAt: _status.startedAt,
                  totalBytes: _status.totalBytes,
                  linesAdded: _status.linesAdded,
                  linesRemoved: _status.linesRemoved,
                  onCancel: _canInterruptActiveTurn() ? _cancelTurn : null,
                  showCancelButton: _status.mode != null,
                  cancelEnabled: _canInterruptActiveTurn(),
                ),
              ),
            ),
          ),
      ],
      children: loading && pendingMessages.isEmpty
          ? const <Widget>[]
          : _buildMessageWidgets(context, messages, pendingMessages, feedImages: feedImages),
    );

    return OverlayPortal(
      controller: _imageViewerController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) {
        if (_overlayImages.isEmpty) {
          return const SizedBox.shrink();
        }
        return ChatThreadImageGalleryPage(
          room: widget.room,
          images: _overlayImages,
          initialIndex: _overlayInitialIndex,
          onClose: _closeThreadImageViewer,
        );
      },
      child: threadView,
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final hasWireBackedContent = _hasWireBackedContent();
    if (_fatalError && error != null && !hasWireBackedContent) {
      return Center(
        child: Text(error.toString(), style: ShadTheme.of(context).textTheme.muted, textAlign: TextAlign.center),
      );
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final loading = !_ready;
        final messages = loading ? const <_DatasetThreadMessage>[] : _messages();
        final pendingMessages = loading ? _pendingAgentMessagesForThread() : _combinedPendingMessages(messages);
        final snapshot = _snapshot(messages, pendingMessages);
        return FileDropArea(
          onFileDrop: (name, dataStream, size) async {
            await _controller.uploadFile(name, dataStream, size ?? 0);
          },
          child: Column(
            children: [
              Expanded(child: _buildThreadViewport(context, messages, pendingMessages, loading: loading)),
              ChatThreadInputFrame(
                hasFooter: widget.showUsageFooter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?_buildQueuedPendingMessages(context, messages, pendingMessages),
                    _buildComposerWithUsageFooter(context, input: _buildInput(context, snapshot, pendingMessages), usage: snapshot.usage),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DatasetThreadMessage {
  const _DatasetThreadMessage({
    required this.id,
    required this.kind,
    required this.role,
    required this.text,
    required this.attachments,
    required this.createdAt,
    this.image,
    this.toolCallEntry,
    this.expandedToolCallEntry,
    this.diffPreviewBlocks = const <_DatasetDiffPreviewBlock>[],
    this.authorName,
    this.phase,
    this.turnId,
  });

  final String id;
  final String kind;
  final String role;
  final String text;
  final List<String> attachments;
  final DateTime createdAt;
  final _DatasetThreadImage? image;
  final ToolCallEntryDisplay? toolCallEntry;
  final ToolCallEntryDisplay? expandedToolCallEntry;
  final List<_DatasetDiffPreviewBlock> diffPreviewBlocks;
  final String? authorName;
  final String? phase;
  final String? turnId;
}

class _DatasetDiffPreviewBlock {
  const _DatasetDiffPreviewBlock({required this.header, required this.code, this.linesAdded, this.linesRemoved});

  final String header;
  final String code;
  final int? linesAdded;
  final int? linesRemoved;
}

sealed class _DatasetThreadFeedItem {
  const _DatasetThreadFeedItem();
}

class _DatasetThreadMessageFeedItem extends _DatasetThreadFeedItem {
  const _DatasetThreadMessageFeedItem(this.message);

  final _DatasetThreadMessage message;
}

class _DatasetThreadDetailGroupFeedItem extends _DatasetThreadFeedItem {
  const _DatasetThreadDetailGroupFeedItem({
    required this.id,
    required this.messages,
    required this.collapsedText,
    required this.authorName,
    required this.createdAt,
  });

  final String id;
  final List<_DatasetThreadMessage> messages;
  final String collapsedText;
  final String authorName;
  final DateTime createdAt;
}

class _DatasetDetailLine extends StatelessWidget {
  const _DatasetDetailLine({super.key, required this.text, required this.authorName, required this.createdAt, required this.onTap});

  final String text;
  final String authorName;
  final DateTime createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ChatThreadMessageView(
          mine: false,
          isAgentMessage: true,
          text: text,
          authorName: authorName,
          createdAt: createdAt,
          bubbleColor: Colors.transparent,
          textColor: theme.colorScheme.mutedForeground,
          selectable: false,
          showBubbleActions: false,
          onTap: onTap,
          header: ChatThreadAuthorHeader(authorName: authorName, createdAt: createdAt, text: text),
        ),
      ),
    );
  }
}

class _DatasetToolCallState {
  _DatasetToolCallState({
    required this.itemId,
    required this.toolkit,
    required this.tool,
    required this.arguments,
    required this.logs,
    required this.argumentDeltaBytes,
    required this.argumentDeltaText,
    required this.authorName,
    required this.createdAt,
  });

  factory _DatasetToolCallState.fromPayload({required Map<String, Object?> row, required Map<String, Object?> payload}) {
    final tool = payload['tool']?.toString() ?? payload['tool_name']?.toString() ?? payload['name']?.toString() ?? 'tool';
    return _DatasetToolCallState(
      itemId: row['item_id']?.toString() ?? _payloadItemId(Map<String, dynamic>.from(payload)),
      toolkit: payload['toolkit']?.toString() ?? payload['toolkit_name']?.toString() ?? '',
      tool: tool.trim().isEmpty ? 'tool' : tool,
      arguments: _mapValue(payload['arguments']),
      logs: <String>[],
      argumentDeltaBytes: _intValue(payload['argument_delta_bytes']),
      argumentDeltaText: payload['argument_delta_text']?.toString() ?? '',
      authorName: payload['sender_name']?.toString(),
      createdAt: _rowTimestamp(row),
    );
  }

  final String itemId;
  String toolkit;
  String tool;
  Map<String, Object?>? arguments;
  final List<String> logs;
  int argumentDeltaBytes;
  String argumentDeltaText;
  String? authorName;
  final DateTime createdAt;

  void appendArgumentDelta(String delta) {
    if (delta.isEmpty) {
      return;
    }
    argumentDeltaText = '$argumentDeltaText$delta';
    arguments = _toolArgumentsFromDeltaText(tool: tool, current: arguments, text: argumentDeltaText) ?? arguments;
  }
}

class _DatasetTextContentState {
  _DatasetTextContentState({
    required this.itemId,
    required this.kind,
    required this.role,
    required this.createdAt,
    required this.latestRow,
    this.text = '',
    this.authorName,
    this.phase,
    this.turnId,
  });

  factory _DatasetTextContentState.fromPayload({
    required Map<String, Object?> row,
    required Map<String, Object?> payload,
    required String kind,
    required String role,
  }) {
    final itemId = _datasetThreadContentItemId(row: row, payload: payload, type: payload['type']?.toString());
    return _DatasetTextContentState(
      itemId: itemId,
      kind: kind,
      role: role,
      text: payload['text']?.toString() ?? '',
      authorName: payload['sender_name']?.toString(),
      phase: _agentMessagePhase(payload),
      turnId: row['turn_id']?.toString() ?? payload['turn_id']?.toString(),
      createdAt: _rowTimestamp(row),
      latestRow: row,
    );
  }

  final String itemId;
  final String kind;
  final String role;
  final DateTime createdAt;
  String text;
  String? authorName;
  String? phase;
  String? turnId;
  Map<String, Object?> latestRow;

  void appendDelta({required Map<String, Object?> row, required Map<String, Object?> payload}) {
    text = accumulateTextStreamDelta(text, payload['text']?.toString() ?? '');
    authorName ??= payload['sender_name']?.toString();
    phase ??= _agentMessagePhase(payload);
    turnId ??= row['turn_id']?.toString() ?? payload['turn_id']?.toString();
    latestRow = row;
  }

  _DatasetThreadMessage? complete({required Map<String, Object?> row, required Map<String, Object?> payload}) {
    final endedText = payload['text']?.toString() ?? '';
    if (endedText.isNotEmpty) {
      text = accumulateTextStreamDelta(text, endedText);
    }
    authorName ??= payload['sender_name']?.toString();
    phase ??= _agentMessagePhase(payload);
    turnId ??= row['turn_id']?.toString() ?? payload['turn_id']?.toString();
    latestRow = row;
    return toMessage(row: row);
  }

  _DatasetThreadMessage? toMessage({required Map<String, Object?> row}) {
    if (text.trim().isEmpty) {
      return null;
    }
    return _DatasetThreadMessage(
      id: itemId,
      kind: kind,
      role: role == 'assistant' ? 'agent' : role,
      text: text,
      authorName: authorName,
      attachments: const [],
      createdAt: createdAt,
      phase: phase,
      turnId: turnId,
    );
  }
}

Map<String, Object?> _mergeDatasetAndLiveRow({required Map<String, Object?> datasetRow, required Map<String, Object?> liveRow}) {
  final datasetData = _rowData(datasetRow);
  final liveData = _rowData(liveRow);
  if (datasetData == null || liveData == null) {
    return datasetRow;
  }

  final datasetKind = datasetData['kind']?.toString();
  final liveKind = liveData['kind']?.toString();
  final datasetType = datasetData['type']?.toString();
  final liveType = liveData['type']?.toString();
  final isToolCall =
      datasetKind == 'tool_call' ||
      liveKind == 'tool_call' ||
      datasetType?.startsWith('meshagent.agent.tool_call.') == true ||
      liveType?.startsWith('meshagent.agent.tool_call.') == true;
  if (!isToolCall) {
    return datasetRow;
  }

  final datasetArguments = _mapValue(datasetData['arguments']);
  final liveArguments = _mapValue(liveData['arguments']);
  final mergedData = <String, Object?>{...liveData, ...datasetData};
  if ((datasetArguments == null || datasetArguments.isEmpty) && liveArguments != null && liveArguments.isNotEmpty) {
    mergedData['arguments'] = liveArguments;
  }

  final liveArgumentDeltaText = liveData['argument_delta_text']?.toString() ?? '';
  final datasetArgumentDeltaText = datasetData['argument_delta_text']?.toString() ?? '';
  if (datasetArgumentDeltaText.isEmpty && liveArgumentDeltaText.isNotEmpty) {
    mergedData['argument_delta_text'] = liveArgumentDeltaText;
    final tool = mergedData['tool']?.toString() ?? mergedData['tool_name']?.toString() ?? mergedData['name']?.toString() ?? '';
    mergedData['arguments'] =
        _toolArgumentsFromDeltaText(tool: tool, current: _mapValue(mergedData['arguments']), text: liveArgumentDeltaText) ??
        _mapValue(mergedData['arguments']);
  }

  final mergedArgumentDeltaBytes = math.max(_intValue(datasetData['argument_delta_bytes']), _intValue(liveData['argument_delta_bytes']));
  if (mergedArgumentDeltaBytes > 0) {
    mergedData['argument_delta_bytes'] = mergedArgumentDeltaBytes;
  }

  return <String, Object?>{...liveRow, ...datasetRow, 'data': mergedData};
}

_DatasetThreadMessage _mergeDuplicateDatasetThreadMessage(_DatasetThreadMessage existing, _DatasetThreadMessage next) {
  if (existing.kind != next.kind || existing.role != next.role) {
    return existing;
  }
  return _DatasetThreadMessage(
    id: existing.id,
    kind: existing.kind,
    role: existing.role,
    text: existing.text.trim().isEmpty ? next.text : existing.text,
    attachments: existing.attachments.isEmpty ? next.attachments : existing.attachments,
    createdAt: existing.createdAt.isBefore(next.createdAt) ? existing.createdAt : next.createdAt,
    image: existing.image ?? next.image,
    toolCallEntry: existing.toolCallEntry ?? next.toolCallEntry,
    expandedToolCallEntry: existing.expandedToolCallEntry ?? next.expandedToolCallEntry,
    diffPreviewBlocks: existing.diffPreviewBlocks.isNotEmpty ? existing.diffPreviewBlocks : next.diffPreviewBlocks,
    authorName: existing.authorName ?? next.authorName,
    phase: existing.phase ?? next.phase,
    turnId: existing.turnId ?? next.turnId,
  );
}

String _datasetThreadMessageDedupeKey({required Map<String, Object?> row, required _DatasetThreadMessage message}) {
  if (message.role == 'user') {
    return 'user:${message.id}';
  }
  return [message.role, message.kind, row['item_id']?.toString() ?? message.id, row['sequence']?.toString() ?? ''].join(':');
}

bool _datasetThreadMessageReconcilesLiveMessage({
  required _DatasetThreadMessage datasetMessage,
  required _DatasetThreadMessage liveMessage,
}) {
  if (datasetMessage.id != liveMessage.id || datasetMessage.kind != liveMessage.kind || datasetMessage.role != liveMessage.role) {
    return false;
  }

  final liveImage = liveMessage.image;
  final datasetImage = datasetMessage.image;
  if (liveImage != null || datasetImage != null) {
    if (liveImage == null || datasetImage == null) {
      return false;
    }
    if (_isTerminalImageGenerationStatus(liveImage.status) && !_isTerminalImageGenerationStatus(datasetImage.status)) {
      return false;
    }
    final liveKeys = _datasetThreadImageReferenceKeys(liveImage);
    final datasetKeys = _datasetThreadImageReferenceKeys(datasetImage);
    if (liveKeys.isNotEmpty) {
      return datasetKeys.any(liveKeys.contains);
    }
    return _normalizedImageGenerationStatus(datasetImage.status) == _normalizedImageGenerationStatus(liveImage.status);
  }

  if (liveMessage.attachments.isNotEmpty) {
    final datasetAttachments = datasetMessage.attachments.map(_comparableThreadAttachmentPath).toSet();
    return liveMessage.attachments.map(_comparableThreadAttachmentPath).every(datasetAttachments.contains);
  }

  final liveText = liveMessage.text.trim();
  if (liveText.isNotEmpty) {
    return datasetMessage.text.trim() == liveText;
  }

  return true;
}

class _DatasetThreadImage {
  const _DatasetThreadImage({this.uri, this.imageId, this.mimeType, this.status, this.statusDetail, this.width, this.height});

  final String? uri;
  final String? imageId;
  final String? mimeType;
  final String? status;
  final String? statusDetail;
  final double? width;
  final double? height;
}

int _compareDatasetThreadRows(Map<String, Object?> left, Map<String, Object?> right) {
  final leftSequence = _intValue(left['sequence']);
  final rightSequence = _intValue(right['sequence']);
  final sequenceOrder = leftSequence.compareTo(rightSequence);
  if (sequenceOrder != 0) {
    return sequenceOrder;
  }

  final timestampOrder = _rowTimestamp(left).compareTo(_rowTimestamp(right));
  if (timestampOrder != 0) {
    return timestampOrder;
  }

  return (left['item_id']?.toString() ?? '').compareTo(right['item_id']?.toString() ?? '');
}

String? _firstNestedStringValue(Object? value, Set<String> keys) {
  if (value is String) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : value;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key?.toString().trim().toLowerCase();
      if (key != null && keys.contains(key)) {
        final nested = _firstNestedStringValue(entry.value, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    for (final entry in value.entries) {
      final nested = _firstNestedStringValue(entry.value, keys);
      if (nested != null) {
        return nested;
      }
    }
  }
  if (value is List) {
    for (final item in value) {
      final nested = _firstNestedStringValue(item, keys);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

Map<String, Object?>? _toolArgumentsFromDeltaText({required String tool, required Map<String, Object?>? current, required String text}) {
  final trimmedText = text.trim();
  if (trimmedText.isEmpty) {
    return current;
  }

  if (tool.trim().toLowerCase() == 'apply_patch' ||
      trimmedText.contains('*** Begin Patch') ||
      trimmedText.contains('*** Update File:') ||
      trimmedText.contains('*** Add File:') ||
      trimmedText.contains('*** Delete File:')) {
    return <String, Object?>{...?current, 'patch': trimmedText};
  }

  try {
    final decoded = jsonDecode(trimmedText);
    if (decoded is Map) {
      return <String, Object?>{...?current, ...decoded.map((key, value) => MapEntry(key.toString(), value))};
    }
  } on FormatException {
    return current;
  }
  return current;
}

_DatasetDiffPreviewBlock? _openAiPatchOperationPreviewBlock(Map<String, Object?> arguments) {
  final operation = arguments['operation'];
  if (operation is! Map) {
    return null;
  }
  final path = _firstNestedStringValue(operation, const {'path'});
  final diff = _firstNestedStringValue(operation, const {'diff'});
  if (path == null || diff == null) {
    return null;
  }
  final counts = _diffLineCounts(diff);
  return _DatasetDiffPreviewBlock(header: path, code: diff, linesAdded: counts.$1, linesRemoved: counts.$2);
}

List<_DatasetDiffPreviewBlock> _applyPatchDiffPreviewBlocks(String patch) {
  final normalized = patch.replaceAll('\r\n', '\n').trimRight();
  if (!normalized.contains('*** Begin Patch') &&
      !normalized.contains('*** Update File:') &&
      !normalized.contains('*** Add File:') &&
      !normalized.contains('*** Delete File:')) {
    return const <_DatasetDiffPreviewBlock>[];
  }

  final previews = <_DatasetDiffPreviewBlock>[];
  var currentPath = '';
  var lines = <String>[];
  var linesAdded = 0;
  var linesRemoved = 0;
  final filePattern = RegExp(r'^\*\*\* (?:Update|Add|Delete) File: (.+)$');

  void flush() {
    if (currentPath.isNotEmpty && lines.isNotEmpty) {
      previews.add(
        _DatasetDiffPreviewBlock(
          header: currentPath,
          code: lines.join('\n').trimRight(),
          linesAdded: linesAdded,
          linesRemoved: linesRemoved,
        ),
      );
    }
    lines = <String>[];
    linesAdded = 0;
    linesRemoved = 0;
  }

  for (final line in normalized.split('\n')) {
    final fileMatch = filePattern.firstMatch(line);
    if (fileMatch != null) {
      flush();
      currentPath = fileMatch.group(1)?.trim() ?? '';
      continue;
    }
    if (currentPath.isEmpty || line.startsWith('*** ')) {
      continue;
    }
    lines.add(line);
    if (line.startsWith('+') && !line.startsWith('+++')) {
      linesAdded++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      linesRemoved++;
    }
  }
  flush();
  return previews;
}

(int, int) _diffLineCounts(String diff) {
  var linesAdded = 0;
  var linesRemoved = 0;
  for (final line in diff.replaceAll('\r\n', '\n').split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      linesAdded++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      linesRemoved++;
    }
  }
  return (linesAdded, linesRemoved);
}

List<_DatasetDiffPreviewBlock> _toolCallDiffPreviewBlocks({required String tool, required Map<String, Object?>? arguments}) {
  if (arguments == null) {
    return const <_DatasetDiffPreviewBlock>[];
  }
  final operationBlock = _openAiPatchOperationPreviewBlock(arguments);
  if (operationBlock != null && tool.trim().toLowerCase() == 'apply_patch') {
    return <_DatasetDiffPreviewBlock>[operationBlock];
  }
  final patch = _firstNestedStringValue(arguments, const {'patch', 'input', 'diff'});
  if (patch == null) {
    return const <_DatasetDiffPreviewBlock>[];
  }
  if (tool.trim().toLowerCase() != 'apply_patch' &&
      !patch.contains('*** Begin Patch') &&
      !patch.contains('*** Update File:') &&
      !patch.contains('*** Add File:') &&
      !patch.contains('*** Delete File:')) {
    return const <_DatasetDiffPreviewBlock>[];
  }
  return _applyPatchDiffPreviewBlocks(patch);
}

_DatasetThreadMessage? _messageForRow(
  Map<String, Object?> row, {
  Map<String, Map<String, Object?>> turnInputPayloadsById = const <String, Map<String, Object?>>{},
}) {
  final data = _rowData(row);
  if (data == null) {
    return null;
  }
  final agentMessage = _messageForAgentPayload(row, data, turnInputPayloadsById: turnInputPayloadsById);
  if (agentMessage != null) {
    return agentMessage;
  }

  final kind = data['kind']?.toString();
  final itemId = row['item_id']?.toString() ?? const Uuid().v4();
  final role = data['role']?.toString();
  final turnId = row['turn_id']?.toString();
  final phase = data['phase']?.toString();
  switch (kind) {
    case 'message':
      final text = data['text']?.toString() ?? '';
      final attachments = _stringList(data['attachments']);
      if (text.trim().isEmpty && attachments.isEmpty) {
        return null;
      }
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'message',
        role: role == 'assistant' ? 'agent' : (role ?? 'agent'),
        text: text,
        authorName: data['sender_name']?.toString(),
        attachments: attachments,
        createdAt: _rowTimestamp(row),
        phase: phase,
        turnId: turnId,
      );
    case 'file':
      final urls = _stringList(data['urls']);
      if (urls.isEmpty) {
        return null;
      }
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'message',
        role: role == 'assistant' ? 'agent' : (role ?? 'agent'),
        text: '',
        authorName: data['sender_name']?.toString(),
        attachments: urls,
        createdAt: _rowTimestamp(row),
        phase: phase,
        turnId: turnId,
      );
    case 'image_generation':
      final message = _mapValue(data['message']);
      final image = _firstGeneratedImage(message);
      final dimensions = _imageGenerationDimensions(data: data, message: message, image: image);
      final imageUri = _stringValue(image?['uri']);
      final imageId = _imageIdFromDatasetUri(imageUri);
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'message',
        role: 'agent',
        text: '',
        authorName: _stringValue(data['sender_name']) ?? _stringValue(image?['created_by']),
        attachments: const [],
        createdAt: _rowTimestamp(row),
        phase: phase,
        turnId: turnId,
        image: _DatasetThreadImage(
          uri: imageUri,
          imageId: imageId,
          mimeType: _stringValue(image?['mime_type']),
          status:
              _stringValue(data['status']) ??
              _stringValue(image?['status']) ??
              _imageGenerationStatusFromType(_stringValue(message?['type'])),
          statusDetail: _stringValue(image?['status_detail']),
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
    case 'reasoning':
      final text = data['text']?.toString() ?? '';
      return text.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'reasoning',
              role: 'agent',
              text: text,
              authorName: data['sender_name']?.toString(),
              attachments: const [],
              createdAt: _rowTimestamp(row),
              phase: phase,
              turnId: turnId,
            );
    case 'tool_call':
      final toolkit = data['toolkit']?.toString() ?? '';
      final tool = data['tool']?.toString() ?? '';
      final arguments = _mapValue(data['arguments']);
      final logs = _stringList(data['logs']);
      final errorMessage = data['error_message']?.toString();
      final status = data['status']?.toString();
      final argumentDeltaBytes = _intValue(data['argument_delta_bytes']);
      final diffPreviewBlocks = _toolCallDiffPreviewBlocks(tool: tool, arguments: arguments);
      final summary = formatToolCallEntry(
        toolkit: toolkit,
        tool: tool.trim().isEmpty ? 'tool' : tool,
        arguments: arguments,
        logs: logs,
        errorMessage: errorMessage,
        completed: !_toolCallStatusIsRunning(status),
        pending: _toolCallStatusIsPending(status),
        argumentDeltaBytes: argumentDeltaBytes,
      );
      final expandedSummary = formatToolCallEntry(
        toolkit: toolkit,
        tool: tool.trim().isEmpty ? 'tool' : tool,
        arguments: arguments,
        logs: logs,
        errorMessage: errorMessage,
        completed: !_toolCallStatusIsRunning(status),
        pending: _toolCallStatusIsPending(status),
        detailLineLimit: null,
        argumentDeltaBytes: argumentDeltaBytes,
      );
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'tool_call',
        role: 'agent',
        text: summary.text.trim().isEmpty ? 'Tool call' : summary.text,
        toolCallEntry: summary,
        expandedToolCallEntry: expandedSummary.text.trim().isEmpty ? null : expandedSummary,
        diffPreviewBlocks: diffPreviewBlocks,
        authorName: data['sender_name']?.toString(),
        attachments: const [],
        createdAt: _rowTimestamp(row),
        phase: phase,
        turnId: turnId,
      );
    case 'compaction':
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'compaction',
        role: 'agent',
        text: 'Context compacted',
        authorName: data['sender_name']?.toString(),
        attachments: const [],
        createdAt: _rowTimestamp(row),
        phase: phase,
        turnId: turnId,
      );
    case 'error':
      final text = data['text']?.toString() ?? data['error_message']?.toString() ?? '';
      return text.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'error',
              role: 'agent',
              text: text,
              authorName: data['sender_name']?.toString(),
              attachments: const [],
              createdAt: _rowTimestamp(row),
              phase: phase,
              turnId: turnId,
            );
  }
  return null;
}

class _DatasetThreadRealtimeAudioPlayer {
  static const int _sampleRate = 24000;
  static const int _channels = 1;
  static const int _bytesPerSample = 2;
  static const int _bytesPerFrame = _channels * _bytesPerSample;

  final Map<String, Future<void>> _queues = <String, Future<void>>{};
  final Set<String> _closed = <String>{};
  final Set<String> _seenDeltaMessageIds = <String>{};
  final RealtimeAudioOutput _output = createRealtimeAudioOutput();
  String? _activeItemId;
  bool _streamStarted = false;

  Future<void> start(String itemId) async {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty || _closed.contains(normalizedItemId)) {
      return;
    }
    if (_activeItemId == normalizedItemId && _streamStarted) {
      return;
    }
    try {
      if (_activeItemId != null && _activeItemId != normalizedItemId) {
        await stop(_activeItemId!);
      }
      await _output.start(sampleRate: _sampleRate, channels: _channels);
      _activeItemId = normalizedItemId;
      _streamStarted = true;
    } catch (_) {}
  }

  Future<void> append({required String itemId, required String? messageId, required Uint8List? data, required String? mimeType}) async {
    final normalizedItemId = itemId.trim();
    if (data == null || data.isEmpty || normalizedItemId.isEmpty || _closed.contains(normalizedItemId)) {
      return;
    }
    final normalizedMessageId = messageId?.trim();
    if (normalizedMessageId != null && normalizedMessageId.isNotEmpty && !_seenDeltaMessageIds.add(normalizedMessageId)) {
      return;
    }
    final queue = (_queues[normalizedItemId] ?? Future<void>.value()).then(
      (_) => _appendNow(itemId: normalizedItemId, data: data, mimeType: mimeType),
    );
    _queues[normalizedItemId] = queue.catchError((_) {});
    await queue;
  }

  Future<void> _appendNow({required String itemId, required Uint8List data, required String? mimeType}) async {
    try {
      if (_closed.contains(itemId)) {
        return;
      }
      await start(itemId);
      final pcm = _pcmAudioBytes(bytes: data, mimeType: mimeType);
      if (pcm.isEmpty || pcm.length % _bytesPerFrame != 0) {
        return;
      }
      if (_activeItemId != itemId) {
        return;
      }
      await _output.append(pcm);
    } catch (_) {}
  }

  Future<void> complete(String itemId) async {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) {
      return;
    }
    final queue = (_queues[normalizedItemId] ?? Future<void>.value()).then((_) => _completeNow(normalizedItemId));
    _queues[normalizedItemId] = queue.catchError((_) {});
    await queue;
  }

  Future<void> _completeNow(String itemId) async {
    _queues.remove(itemId);
    if (_activeItemId == itemId) {
      await _output.complete();
      _activeItemId = null;
      _streamStarted = false;
    }
  }

  Future<void> stop(String itemId) async {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) {
      return;
    }
    _queues.remove(normalizedItemId);
    _closed.add(normalizedItemId);
    if (_activeItemId != normalizedItemId) {
      unawaited(Future<void>.delayed(const Duration(seconds: 30)).then((_) => _closed.remove(normalizedItemId)));
      return;
    }
    try {
      await _output.stop();
    } catch (_) {}
    _activeItemId = null;
    _streamStarted = false;
    unawaited(Future<void>.delayed(const Duration(seconds: 30)).then((_) => _closed.remove(normalizedItemId)));
  }

  Future<void> stopAll() async {
    final activeItemId = _activeItemId;
    if (activeItemId != null) {
      await stop(activeItemId);
    } else {
      await _output.stop();
    }
    _queues.clear();
    _seenDeltaMessageIds.clear();
  }

  Future<void> dispose() async {
    await stopAll();
    try {
      await _output.dispose();
    } catch (_) {}
  }
}

Uint8List _pcmAudioBytes({required Uint8List bytes, required String? mimeType}) {
  final normalizedMimeType = mimeType?.split(';').first.trim().toLowerCase();
  if (normalizedMimeType == 'audio/wav' || normalizedMimeType == 'audio/wave' || normalizedMimeType == 'audio/x-wav') {
    return _wavDataChunk(bytes) ?? bytes;
  }
  return bytes;
}

Uint8List? _wavDataChunk(Uint8List bytes) {
  if (bytes.length < 44 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' || String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + chunkSize;
    if (chunkEnd > bytes.length) {
      return null;
    }
    if (chunkId == 'data') {
      return Uint8List.sublistView(bytes, chunkStart, chunkEnd);
    }
    offset = chunkEnd + (chunkSize.isOdd ? 1 : 0);
  }
  return null;
}

_DatasetThreadMessage? _messageForAgentPayload(
  Map<String, Object?> row,
  Map<String, Object?> payload, {
  Map<String, Map<String, Object?>> turnInputPayloadsById = const <String, Map<String, Object?>>{},
}) {
  final type = payload['type']?.toString();
  if (type == null || type.trim().isEmpty) {
    return null;
  }

  final itemId = _datasetThreadContentItemId(row: row, payload: payload, type: type);
  final createdAt = _rowTimestamp(row);
  final turnId = row['turn_id']?.toString() ?? payload['turn_id']?.toString();
  final phase = _agentMessagePhase(payload);
  switch (type) {
    case agentTurnStartType:
    case agentTurnSteerType:
      final content = payload['content'];
      if (content is! List) {
        return null;
      }
      final extracted = _agentInputContentParts(content);
      if (extracted.text.trim().isEmpty && extracted.attachments.isEmpty) {
        return null;
      }
      return _DatasetThreadMessage(
        id: payload['message_id']?.toString() ?? itemId,
        kind: 'message',
        role: 'user',
        text: extracted.text,
        authorName: payload['sender_name']?.toString(),
        attachments: extracted.attachments,
        createdAt: createdAt,
        turnId: turnId,
      );
    case agentModelsRequestType:
    case agentModelsResponseType:
    case agentModelChangeType:
    case agentModelChangedType:
      return null;
    case agentRealtimeAudioCommitType:
      final text = payload['text']?.toString() ?? '';
      if (text.trim().isEmpty) {
        return null;
      }
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'message',
        role: 'user',
        text: text,
        authorName: payload['sender_name']?.toString(),
        attachments: const [],
        createdAt: createdAt,
        turnId: turnId,
      );
    case agentTurnStartedType:
    case agentTurnSteeredType:
      final sourceMessageId = payload['source_message_id']?.toString().trim();
      if (sourceMessageId == null || sourceMessageId.isEmpty) {
        return null;
      }
      final inputPayload = turnInputPayloadsById[sourceMessageId] ?? payload;
      final content = inputPayload['content'];
      if (content is! List) {
        return null;
      }
      final extracted = _agentInputContentParts(content);
      if (extracted.text.trim().isEmpty && extracted.attachments.isEmpty) {
        return null;
      }
      return _DatasetThreadMessage(
        id: sourceMessageId,
        kind: 'message',
        role: 'user',
        text: extracted.text,
        authorName: inputPayload['sender_name']?.toString(),
        attachments: extracted.attachments,
        createdAt: createdAt,
        turnId: turnId,
      );
    case agentTurnStartAcceptedType:
    case agentTurnSteerAcceptedType:
      return null;
    case agentTextContentDeltaType:
    case agentAudioTranscriptionDeltaType:
    case agentAudioTranscriptionCompletedType:
      final text = payload['text']?.toString() ?? '';
      final role = type == agentAudioTranscriptionDeltaType || type == agentAudioTranscriptionCompletedType
          ? _textContentRoleFromPayload(payload)
          : 'assistant';
      return text.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'message',
              role: role == 'assistant' ? 'agent' : role,
              text: text,
              authorName: payload['sender_name']?.toString(),
              attachments: const [],
              createdAt: createdAt,
              phase: phase,
              turnId: turnId,
            );
    case agentAudioGenerationStartedType:
    case agentAudioGenerationDeltaType:
    case agentAudioGenerationCompletedType:
    case agentAudioGenerationFailedType:
    case agentAudioTranscriptionStartedType:
    case agentAudioTranscriptionFailedType:
      return null;
    case agentReasoningContentDeltaType:
      final text = payload['text']?.toString() ?? '';
      return text.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'reasoning',
              role: 'agent',
              text: text,
              authorName: payload['sender_name']?.toString(),
              attachments: const [],
              createdAt: createdAt,
              turnId: turnId,
            );
    case agentFileContentDeltaType:
      final url = payload['url']?.toString();
      return url == null || url.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'message',
              role: 'agent',
              text: '',
              authorName: payload['sender_name']?.toString(),
              attachments: [url.trim()],
              createdAt: createdAt,
              turnId: turnId,
            );
    case agentImageGenerationStartedType:
    case agentImageGenerationPartialType:
    case agentImageGenerationCompletedType:
    case agentImageGenerationFailedType:
      final image = _firstGeneratedImage(payload);
      final dimensions = _imageGenerationDimensions(data: const <String, Object?>{}, message: payload, image: image);
      final imageUri = _stringValue(image?['uri']);
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'message',
        role: 'agent',
        text: '',
        authorName: payload['sender_name']?.toString() ?? _stringValue(image?['created_by']),
        attachments: const [],
        createdAt: createdAt,
        turnId: turnId,
        image: _DatasetThreadImage(
          uri: imageUri,
          imageId: _imageIdFromDatasetUri(imageUri),
          mimeType: _stringValue(image?['mime_type']),
          status: _stringValue(image?['status']) ?? _imageGenerationStatusFromType(type),
          statusDetail: _stringValue(image?['status_detail']),
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
    case agentToolCallStartedType:
    case agentToolCallArgumentsDeltaType:
    case agentToolCallLogDeltaType:
      return null;
    case agentToolCallEndedType:
      return _messageForToolCallEndRow(row: row, payload: payload, state: null);
    case agentContextCompactedType:
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'compaction',
        role: 'agent',
        text: 'Context compacted',
        authorName: payload['sender_name']?.toString(),
        attachments: const [],
        createdAt: createdAt,
        turnId: turnId,
      );
    case agentTurnEndedType:
      final errorMessage = agentTurnEndedErrorMessage(payload);
      return errorMessage == null
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'error',
              role: 'agent',
              text: errorMessage,
              authorName: payload['sender_name']?.toString(),
              attachments: const [],
              createdAt: createdAt,
              phase: phase,
              turnId: turnId,
            );
  }
  return null;
}

bool _isDatasetToolCallStartType(String? type) {
  return type == agentToolCallPendingType || type == agentToolCallInProgressType || type == agentToolCallStartedType;
}

bool _toolCallStatusIsRunning(String? status) {
  final normalized = status?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty || normalized == 'pending' || normalized == 'in_progress' || normalized == 'running';
}

bool _toolCallStatusIsPending(String? status) {
  return status?.trim().toLowerCase() == 'pending';
}

_DatasetThreadMessage _messageForToolCallEndRow({
  required Map<String, Object?> row,
  required Map<String, Object?>? payload,
  required _DatasetToolCallState? state,
}) {
  final itemId =
      row['item_id']?.toString() ??
      state?.itemId ??
      (payload == null ? const Uuid().v4() : _payloadItemId(Map<String, dynamic>.from(payload)));
  final toolkit = state?.toolkit ?? payload?['toolkit']?.toString() ?? payload?['toolkit_name']?.toString() ?? '';
  final tool = state?.tool ?? payload?['tool']?.toString() ?? payload?['tool_name']?.toString() ?? payload?['name']?.toString() ?? 'tool';
  final arguments = state?.arguments ?? _mapValue(payload?['arguments']);
  final logs = state?.logs ?? const <String>[];
  final argumentDeltaBytes = state?.argumentDeltaBytes ?? _intValue(payload?['argument_delta_bytes']);
  final errorMessage = _agentToolCallErrorMessage(payload?['error']);
  final diffPreviewBlocks = _toolCallDiffPreviewBlocks(tool: tool, arguments: arguments);
  final entry = formatToolCallEntry(
    toolkit: toolkit,
    tool: tool.trim().isEmpty ? 'tool' : tool,
    arguments: arguments,
    logs: logs,
    errorMessage: errorMessage,
    argumentDeltaBytes: argumentDeltaBytes,
  );
  final expandedEntry = formatToolCallEntry(
    toolkit: toolkit,
    tool: tool.trim().isEmpty ? 'tool' : tool,
    arguments: arguments,
    logs: logs,
    errorMessage: errorMessage,
    detailLineLimit: null,
    argumentDeltaBytes: argumentDeltaBytes,
  );
  return _DatasetThreadMessage(
    id: itemId,
    kind: 'tool_call',
    role: 'agent',
    text: entry.text,
    toolCallEntry: entry,
    expandedToolCallEntry: expandedEntry.text.trim().isEmpty ? null : expandedEntry,
    diffPreviewBlocks: diffPreviewBlocks,
    authorName: payload?['sender_name']?.toString() ?? state?.authorName,
    attachments: const [],
    createdAt: _rowTimestamp(row),
    turnId: row['turn_id']?.toString() ?? payload?['turn_id']?.toString(),
  );
}

@visibleForTesting
String? agentTurnEndedErrorMessage(Map<String, Object?> payload) {
  if (payload['type'] != agentTurnEndedType) {
    return null;
  }
  final error = payload['error'];
  if (_agentErrorIsCancellation(error)) {
    return null;
  }
  return _agentErrorMessage(error);
}

String? _agentToolCallErrorMessage(Object? error) {
  return _agentErrorMessage(error);
}

bool _agentErrorIsCancellation(Object? error) {
  if (error == null) {
    return false;
  }
  final values = <String>[];
  if (error is String) {
    values.add(error);
  } else if (error is Map) {
    for (final key in const ['code', 'message', 'detail', 'error']) {
      final value = error[key];
      if (value is String) {
        values.add(value);
      }
    }
  } else {
    values.add(error.toString());
  }
  return values.any((value) {
    final normalized = value.trim().toLowerCase();
    return normalized.contains('cancel') || normalized.contains('interrupt') || normalized.contains('abort');
  });
}

String? _agentErrorMessage(Object? error) {
  if (error == null) {
    return null;
  }
  if (error is String) {
    final normalized = error.trim();
    return normalized.isEmpty ? null : normalized;
  }
  if (error is Map) {
    for (final key in const ['message', 'detail', 'error']) {
      final value = error[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final encoded = jsonEncode(error);
    return encoded.trim().isEmpty ? null : encoded;
  }
  final normalized = error.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

List<String> _agentToolCallLogLines(Object? lines) {
  if (lines is! List) {
    return const [];
  }
  final output = <String>[];
  for (final line in lines) {
    if (line is Map) {
      final text = line['text'];
      if (text is String && text.trim().isNotEmpty) {
        output.add(text);
      }
      continue;
    }
    if (line is String && line.trim().isNotEmpty) {
      output.add(line);
    }
  }
  return output;
}

({String text, List<String> attachments}) _agentInputContentParts(List<Object?> content) {
  final textParts = <String>[];
  final attachments = <String>[];
  for (final item in content) {
    final contentItem = item is Map<String, dynamic> ? item : (item is Map ? Map<String, dynamic>.from(item) : null);
    if (contentItem == null) {
      continue;
    }
    final contentType = contentItem['type'];
    if (contentType == 'text') {
      final text = contentItem['text']?.toString();
      if (text != null && text.isNotEmpty) {
        textParts.add(text);
      }
    } else if (contentType == 'file') {
      final url = contentItem['url']?.toString();
      if (url != null && url.trim().isNotEmpty) {
        attachments.add(url.trim());
      }
    }
  }
  return (text: textParts.join('\n'), attachments: attachments);
}

bool _datasetThreadMessageMatchesPendingAgentMessage(_DatasetThreadMessage message, PendingAgentMessage pending) {
  if (message.kind != 'message' || message.role == 'agent') {
    return false;
  }

  if (message.id == pending.messageId) {
    return _datasetThreadMessageContentMatchesPendingAgentMessage(message, pending);
  }

  if (!pending.matchByContentOnly) {
    return false;
  }

  return _datasetThreadMessageContentMatchesPendingAgentMessage(message, pending);
}

bool _pendingDatasetMessageIsOptimisticallyRendered({
  required PendingAgentMessage pending,
  required Iterable<_DatasetThreadMessage> messages,
}) {
  if (pending.messageType == agentTurnSteerType || pending.matchByContentOnly) {
    return false;
  }
  return pending.awaitingApplication || !messages.any((message) => message.id == pending.messageId);
}

bool _datasetThreadMessageContentMatchesPendingAgentMessage(_DatasetThreadMessage message, PendingAgentMessage pending) {
  final pendingText = pending.text.trim();
  if (pendingText.isNotEmpty && message.text.trim() != pendingText) {
    return false;
  }

  final pendingAttachments = pending.attachments
      .map(_comparableThreadAttachmentPath)
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (pendingAttachments.isEmpty) {
    return true;
  }

  final messageAttachments = message.attachments
      .map(_comparableThreadAttachmentPath)
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  return const ListEquality<String>().equals(messageAttachments, pendingAttachments);
}

bool _isTmpThreadPath(String path) {
  return path.trim().startsWith('tmp://');
}

bool _isDatasetTableNotFoundError(Object error) {
  if (error is! RoomServerException) {
    return false;
  }
  if (error.statusCode == 404) {
    return true;
  }
  final message = error.message.toLowerCase();
  return message.contains('table') &&
      (message.contains('not found') || message.contains('does not exist') || message.contains('no such table'));
}

String _payloadItemId(Map<String, dynamic> payload) {
  final explicitItemId = _payloadExplicitItemId(payload);
  if (explicitItemId != null) {
    return explicitItemId;
  }
  return const Uuid().v4();
}

String _turnApplicationItemId(Map<String, dynamic> payload, String suffix) {
  final explicitItemId = _payloadExplicitItemId(payload);
  if (explicitItemId != null) {
    return explicitItemId;
  }
  final sourceMessageId = payload['source_message_id'];
  if (sourceMessageId is String && sourceMessageId.trim().isNotEmpty) {
    return '${sourceMessageId.trim()}.$suffix';
  }
  final turnId = payload['turn_id'];
  if (turnId is String && turnId.trim().isNotEmpty) {
    return '${turnId.trim()}.$suffix';
  }
  return const Uuid().v4();
}

String? _payloadExplicitItemId(Map<String, dynamic> payload) {
  final itemId = payload['item_id'];
  if (itemId is String && itemId.trim().isNotEmpty) {
    return itemId.trim();
  }
  final messageId = payload['message_id'];
  if (messageId is String && messageId.trim().isNotEmpty) {
    return messageId.trim();
  }
  return null;
}

String _datasetThreadContentItemId({required Map<String, Object?> row, required Map<String, Object?>? payload, required String? type}) {
  if (_isAgentStreamContentType(type) && payload != null) {
    final payloadItemId = payload['item_id'];
    if (payloadItemId is String && payloadItemId.trim().isNotEmpty) {
      return payloadItemId.trim();
    }
  }
  final rowItemId = row['item_id'];
  if (rowItemId is String && rowItemId.trim().isNotEmpty) {
    return rowItemId.trim();
  }
  if (payload != null) {
    return _payloadItemId(Map<String, dynamic>.from(payload));
  }
  return '';
}

bool _isAgentStreamContentType(String? type) {
  return type == agentTextContentStartedType ||
      type == agentTextContentDeltaType ||
      type == agentTextContentEndedType ||
      type == agentAudioTranscriptionStartedType ||
      type == agentAudioTranscriptionDeltaType ||
      type == agentAudioTranscriptionCompletedType ||
      type == agentReasoningContentStartedType ||
      type == agentReasoningContentDeltaType ||
      type == agentReasoningContentEndedType;
}

String? _payloadTurnId(Map<String, dynamic> payload) {
  final turnId = payload['turn_id'];
  if (turnId is! String) {
    return null;
  }
  final trimmed = turnId.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _senderNameFromPayload(Map<String, dynamic> payload) {
  final senderName = payload['sender_name'];
  if (senderName is! String) {
    return null;
  }
  final trimmed = senderName.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _agentMessagePhase(Map<String, dynamic> payload) {
  final phase = payload['phase'];
  if (phase is String) {
    final normalized = phase.trim();
    if (normalized == 'commentary' || normalized == 'final_answer') {
      return normalized;
    }
  }
  final type = payload['type']?.toString();
  if ((type == agentAudioTranscriptionStartedType ||
          type == agentAudioTranscriptionDeltaType ||
          type == agentAudioTranscriptionCompletedType) &&
      _textContentRoleFromPayload(payload) != 'user') {
    return 'final_answer';
  }
  return null;
}

String _textContentRoleFromPayload(Map<String, Object?>? payload) {
  return payload?['role']?.toString() == 'user' ? 'user' : 'assistant';
}

DateTime? _timestampFromPayload(Map<String, dynamic> payload) {
  final createdAt = payload['created_at'];
  if (createdAt is DateTime) {
    return createdAt;
  }
  if (createdAt is String) {
    return DateTime.tryParse(createdAt);
  }
  return null;
}

String? _normalizeAgentAttachmentUrl(String path) {
  final trimmedPath = path.trim();
  if (trimmedPath.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmedPath);
  if (uri != null && uri.scheme.isNotEmpty) {
    return trimmedPath;
  }
  final roomPath = trimmedPath.startsWith('/') ? trimmedPath.substring(1) : trimmedPath;
  if (roomPath.isEmpty) {
    return null;
  }
  return 'room:///$roomPath';
}

String _previewPath(String path) {
  const prefix = 'room:///';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

String _comparableThreadAttachmentPath(String path) {
  final previewPath = _previewPath(path.trim());
  return previewPath.startsWith('/') ? previewPath.substring(1) : previewPath;
}

Map<String, Object?>? _rowData(Map<String, Object?> row) {
  final raw = row['data'];
  return _mapValue(raw);
}

String? _datasetRowKey(Map<String, Object?> row) {
  final itemId = row['item_id']?.toString();
  if (itemId == null || itemId.trim().isEmpty) {
    return null;
  }
  final sequence = row['sequence'];
  if (sequence != null) {
    final normalizedSequence = sequence.toString().trim();
    if (normalizedSequence.isNotEmpty) {
      return 'sequence:$normalizedSequence';
    }
  }
  final data = _rowData(row);
  final type = data?['type']?.toString();
  if (type != null && type.trim().isNotEmpty) {
    final messageId = data?['message_id']?.toString();
    final timestamp = row['timestamp']?.toString();
    return [
      'agent',
      itemId,
      type,
      if (messageId != null && messageId.trim().isNotEmpty) messageId.trim(),
      if (timestamp != null && timestamp.trim().isNotEmpty) timestamp.trim(),
    ].join(':');
  }
  return itemId;
}

Map<String, Object?>? _mapValue(Object? raw) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return Map<String, Object?>.from(raw);
  }
  if (raw is String) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  }
  return null;
}

Map<String, Object?>? _firstGeneratedImage(Map<String, Object?>? message) {
  if (message == null) {
    return null;
  }
  final images = message['images'];
  if (images is List && images.isNotEmpty) {
    return _mapValue(images.first);
  }
  return _mapValue(message['image']);
}

bool _isImageGenerationRow(Map<String, Object?> row) {
  final data = _rowData(row);
  if (data == null) {
    return false;
  }
  final kind = data['kind']?.toString();
  if (kind == 'image_generation') {
    return true;
  }
  final type = data['type']?.toString();
  return type == agentImageGenerationStartedType ||
      type == agentImageGenerationPartialType ||
      type == agentImageGenerationCompletedType ||
      type == agentImageGenerationFailedType;
}

Set<String> _imageGenerationCorrelationKeys(Map<String, Object?> row) {
  final keys = <String>{};
  final itemId = _stringValue(row['item_id']);
  if (itemId != null) {
    keys.add('item:$itemId');
  }
  final data = _rowData(row);
  final rawType = data?['type']?.toString();
  final message =
      rawType == agentImageGenerationStartedType ||
          rawType == agentImageGenerationPartialType ||
          rawType == agentImageGenerationCompletedType ||
          rawType == agentImageGenerationFailedType
      ? data
      : _mapValue(data?['message']);
  for (final value in <Object?>[data?['call_id'], message?['call_id']]) {
    final callId = _stringValue(value);
    if (callId != null) {
      keys.add('call:$callId');
    }
  }
  for (final value in <Object?>[message?['item_id'], message?['message_id']]) {
    final id = _stringValue(value);
    if (id != null) {
      keys.add('item:$id');
    }
  }
  return keys;
}

bool _imageGenerationRowsReconcile({required Map<String, Object?> datasetRow, required Map<String, Object?> liveRow}) {
  if (!_isImageGenerationRow(datasetRow) || !_isImageGenerationRow(liveRow)) {
    return false;
  }
  final liveKeys = _imageGenerationCorrelationKeys(liveRow);
  if (liveKeys.isEmpty || !_imageGenerationCorrelationKeys(datasetRow).any(liveKeys.contains)) {
    return false;
  }

  final liveStatus = _messageForRow(liveRow)?.image?.status;
  final datasetStatus = _messageForRow(datasetRow)?.image?.status;
  if (_isTerminalImageGenerationStatus(liveStatus)) {
    return _isTerminalImageGenerationStatus(datasetStatus);
  }
  return true;
}

Set<String> _datasetThreadImageReferenceKeys(_DatasetThreadImage image) {
  final keys = <String>{};
  final imageId = _stringValue(image.imageId);
  if (imageId != null) {
    keys.add('image:$imageId');
  }
  final uri = _stringValue(image.uri);
  if (uri != null) {
    keys.add('uri:$uri');
  }
  return keys;
}

(double?, double?) _imageGenerationDimensions({
  required Map<String, Object?> data,
  required Map<String, Object?>? message,
  required Map<String, Object?>? image,
}) {
  var width = _doubleValue(image?['width']);
  var height = _doubleValue(image?['height']);

  final argumentMaps = <Map<String, Object?>?>[_mapValue(data['arguments']), _mapValue(message?['arguments'])];
  for (final arguments in argumentMaps) {
    if (arguments == null) {
      continue;
    }
    width ??= _doubleValue(arguments['width']);
    height ??= _doubleValue(arguments['height']);
    if (width == null || height == null) {
      final parsed = _parseImageSize(arguments['size']);
      width ??= parsed.$1;
      height ??= parsed.$2;
    }
    if (width != null && height != null) {
      break;
    }
  }

  return (width, height);
}

(double?, double?) _parseImageSize(Object? value) {
  if (value is! String) {
    return (null, null);
  }
  final match = RegExp(r'^\s*(\d+)\s*[xX]\s*(\d+)\s*$').firstMatch(value);
  if (match == null) {
    return (null, null);
  }
  return (double.tryParse(match.group(1) ?? ''), double.tryParse(match.group(2) ?? ''));
}

String _imageGenerationStatusFromType(String? type) {
  switch (type) {
    case agentImageGenerationCompletedType:
      return 'completed';
    case agentImageGenerationFailedType:
      return 'failed';
    case agentImageGenerationPartialType:
      return 'in_progress';
    default:
      return 'pending';
  }
}

bool _isImageGenerationPendingStatus(String? status) {
  if (status == null || status.trim().isEmpty) {
    return false;
  }
  final normalized = status.trim().toLowerCase();
  return normalized == 'generating' ||
      normalized == 'in_progress' ||
      normalized == 'queued' ||
      normalized == 'running' ||
      normalized == 'pending';
}

bool _isImageGenerationFailedStatus(String? status) {
  if (status == null || status.trim().isEmpty) {
    return false;
  }
  final normalized = status.trim().toLowerCase();
  return normalized == 'failed' || normalized == 'cancelled';
}

bool _isTerminalImageGenerationStatus(String? status) {
  final normalized = _normalizedImageGenerationStatus(status);
  return normalized == 'completed' || _isImageGenerationFailedStatus(normalized);
}

String? _normalizedImageGenerationStatus(String? status) {
  if (status == null || status.trim().isEmpty) {
    return null;
  }
  return status.trim().toLowerCase();
}

String? _imageIdFromDatasetUri(String? uri) {
  if (uri == null || uri.trim().isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(uri.trim());
  if (parsed == null || parsed.scheme != 'dataset') {
    return null;
  }
  final imageId = parsed.queryParameters['id']?.trim();
  return imageId == null || imageId.isEmpty ? null : imageId;
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _doubleValue(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result > 0 ? result : null;
  }
  if (value is String) {
    final result = double.tryParse(value.trim());
    return result != null && result > 0 ? result : null;
  }
  return null;
}

DateTime _rowTimestamp(Map<String, Object?> row) {
  final value = row['timestamp'];
  if (value is DateTime) {
    return value;
  }
  if (value is ArrowTimestampValue) {
    return value.dateTime;
  }
  if (value is int) {
    return _dateTimeFromEpochValue(value);
  }
  if (value is BigInt) {
    return _dateTimeFromEpochValue(value.toInt());
  }
  if (value is double && value.isFinite) {
    return _dateTimeFromEpochValue(value.round());
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

DateTime _dateTimeFromEpochValue(int value) {
  final absolute = value.abs();
  if (absolute >= 100000000000000000) {
    return DateTime.fromMicrosecondsSinceEpoch(value ~/ 1000, isUtc: true);
  }
  if (absolute >= 100000000000000) {
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }
  if (absolute >= 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList(growable: false);
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is BigInt) {
    return value.toInt();
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _displayAgentName(String name) {
  return name.split('@').first.trim();
}

class _DatasetThreadRef {
  const _DatasetThreadRef({required this.namespace, required this.table});

  final List<String>? namespace;
  final String table;

  static _DatasetThreadRef parse(String url) {
    var path = url.trim();
    if (!path.startsWith('dataset://')) {
      throw ArgumentError.value(url, 'url', 'dataset thread URL must start with dataset://');
    }
    path = path.substring('dataset://'.length);
    if (path.startsWith('/')) {
      throw ArgumentError.value(url, 'url', 'dataset thread URL must use dataset://path');
    }
    final parts = path.split('/').map((part) => part.trim()).where((part) => part.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) {
      throw ArgumentError.value(url, 'url', 'dataset thread URL must include a table name');
    }
    return _DatasetThreadRef(namespace: parts.length == 1 ? null : parts.sublist(0, parts.length - 1), table: parts.last);
  }
}
