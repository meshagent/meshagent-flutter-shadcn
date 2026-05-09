import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'chat.dart';
import 'tool_call_summary.dart';
import 'usage_footer_tooltip.dart';

const String _agentRoomMessageType = 'agent-message';
const String _agentTurnStartType = 'meshagent.agent.turn.start';
const String _agentTurnSteerType = 'meshagent.agent.turn.steer';
const String _agentTurnInterruptType = 'meshagent.agent.turn.interrupt';
const String _agentThreadOpenType = 'meshagent.agent.thread.open';
const String _agentThreadCloseType = 'meshagent.agent.thread.close';
const String _agentTurnStartAcceptedType = 'meshagent.agent.turn.start.accepted';
const String _agentTurnStartRejectedType = 'meshagent.agent.turn.start.rejected';
const String _agentTurnSteerAcceptedType = 'meshagent.agent.turn.steer.accepted';
const String _agentTurnSteerRejectedType = 'meshagent.agent.turn.steer.rejected';
const String _agentTurnStartedType = 'meshagent.agent.turn.started';
const String _agentTurnSteeredType = 'meshagent.agent.turn.steered';
const String _agentTextContentStartedType = 'meshagent.agent.text_content.started';
const String _agentTextContentDeltaType = 'meshagent.agent.text_content.delta';
const String _agentTextContentEndedType = 'meshagent.agent.text_content.ended';
const String _agentReasoningContentStartedType = 'meshagent.agent.reasoning_content.started';
const String _agentReasoningContentDeltaType = 'meshagent.agent.reasoning_content.delta';
const String _agentReasoningContentEndedType = 'meshagent.agent.reasoning_content.ended';
const String _agentFileContentStartedType = 'meshagent.agent.file_content.started';
const String _agentFileContentDeltaType = 'meshagent.agent.file_content.delta';
const String _agentFileContentEndedType = 'meshagent.agent.file_content.ended';
const String _agentToolCallPendingType = 'meshagent.agent.tool_call.pending';
const String _agentToolCallInProgressType = 'meshagent.agent.tool_call.in_progress';
const String _agentToolCallStartedType = 'meshagent.agent.tool_call.started';
const String _agentToolCallArgumentsDeltaType = 'meshagent.agent.tool_call.arguments_delta';
const String _agentToolCallLogDeltaType = 'meshagent.agent.tool_call.log_delta';
const String _agentToolCallEndedType = 'meshagent.agent.tool_call.ended';
const String _agentImageGenerationStartedType = 'meshagent.agent.image_generation.started';
const String _agentImageGenerationPartialType = 'meshagent.agent.image_generation.partial';
const String _agentImageGenerationCompletedType = 'meshagent.agent.image_generation.completed';
const String _agentImageGenerationFailedType = 'meshagent.agent.image_generation.failed';
const String _agentContextCompactedType = 'meshagent.agent.context.compacted';
const String _agentUsageUpdatedType = 'meshagent.agent.usage.updated';

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
  final bool initialShowCompletedToolCalls;
  final bool showUsageFooter;

  @override
  State<DatasetChatThread> createState() => _DatasetChatThreadState();
}

class _DatasetChatThreadState extends State<DatasetChatThread> {
  StreamSubscription<ArrowRecordBatch>? _tableLoadSubscription;
  StreamSubscription<RoomEvent>? _roomSubscription;
  Timer? _tableLoadRetryTimer;
  final Map<String, Map<String, Object?>> _rowsByItemId = {};
  final Map<String, Map<String, Object?>> _agentRowsByItemId = {};
  final List<Map<String, dynamic>> _bufferedAgentPayloads = <Map<String, dynamic>>[];
  late ChatThreadController _controller;
  late bool _ownsController;
  late Key _composerInputKey;
  int _tableLoadGeneration = 0;
  Object? _error;
  bool _fatalError = false;
  bool _ready = false;
  ChatThreadStatusState _status = const ChatThreadStatusState();
  AgentUsageSnapshot? _usage;
  int _nextAgentSequence = 0;
  String? _openedPath;
  String? _openedAgentParticipantId;
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
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    _roomSubscription = widget.room.listen(_onRoomEvent);
    widget.room.messaging.addListener(_onMessagingChanged);
    _refreshStatus();
    _startWatch();
    _syncOpenSubscription();
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
    if (oldWidget.path != widget.path || oldWidget.agentName != widget.agentName || oldWidget.room != widget.room) {
      _usage = null;
      _refreshStatus();
      _syncOpenSubscription();
    }
    if (oldWidget.path != widget.path || oldWidget.room != widget.room) {
      _startWatch();
    }
  }

  @override
  void dispose() {
    _tableLoadRetryTimer?.cancel();
    _tableLoadSubscription?.cancel();
    _closeOpenSubscription();
    _roomSubscription?.cancel();
    final historyEntry = _imageViewerHistoryEntry;
    _imageViewerHistoryEntry = null;
    historyEntry?.remove();
    widget.room.messaging.removeListener(_onMessagingChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _startWatch() {
    _tableLoadGeneration += 1;
    _tableLoadRetryTimer?.cancel();
    _tableLoadSubscription?.cancel();
    _rowsByItemId.clear();
    _agentRowsByItemId.clear();
    _bufferedAgentPayloads.clear();
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
      final message = rawType == _agentUsageUpdatedType
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
    _syncOpenSubscription();
  }

  void _onRoomEvent(RoomEvent event) {
    if (!mounted) {
      return;
    }
    if (event is! RoomMessageEvent) {
      return;
    }
    if (event.message.type == _agentRoomMessageType) {
      final payload = event.message.message['payload'];
      if (payload is Map<String, dynamic>) {
        trackAgentThreadStatusPayload(room: widget.room, payload: payload);
        if (_shouldBufferAgentPayload(payload)) {
          _bufferedAgentPayloads.add(Map<String, dynamic>.from(payload));
        } else {
          _handleAgentMessagePayload(payload);
        }
      } else if (payload is Map) {
        final normalized = Map<String, dynamic>.from(payload);
        trackAgentThreadStatusPayload(room: widget.room, payload: normalized);
        if (_shouldBufferAgentPayload(normalized)) {
          _bufferedAgentPayloads.add(normalized);
        } else {
          _handleAgentMessagePayload(normalized);
        }
      }
    }
    _refreshStatus(notify: true);
  }

  bool _shouldBufferAgentPayload(Map<String, dynamic> payload) {
    return !_ready && _agentPayloadBelongsToThread(payload);
  }

  bool _agentPayloadBelongsToThread(Map<String, dynamic> payload) {
    final threadId = payload['thread_id'];
    if (threadId is String && threadId.trim() == widget.path) {
      return true;
    }
    final usage = AgentUsageSnapshot.fromPayload(payload);
    return usage != null && usage.threadPath == widget.path;
  }

  void _handleAgentMessagePayload(Map<String, dynamic> payload, {bool notify = true, bool scroll = true}) {
    if (_handleUsagePayload(payload, notify: notify)) {
      return;
    }
    final changed = _applyAgentMessagePayload(payload);
    _controller.handleAgentMessagePayload(payload);
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

  bool _applyAgentMessagePayload(Map<String, dynamic> payload) {
    if (payload['thread_id'] != widget.path) {
      return false;
    }

    final type = payload['type'];
    if (type is! String) {
      return false;
    }
    if (type == _agentTurnStartRejectedType || type == _agentTurnSteerRejectedType) {
      return false;
    }

    var changed = false;

    switch (type) {
      case _agentTurnStartType:
      case _agentTurnSteerType:
        break;
      case _agentTurnStartAcceptedType:
      case _agentTurnSteerAcceptedType:
        break;
      case _agentTurnStartedType:
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
      case _agentTurnSteeredType:
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
      case _agentTextContentStartedType:
        break;
      case _agentTextContentDeltaType:
        changed =
            _appendAgentRowText(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              kind: 'message',
              role: 'assistant',
              delta: payload['text']?.toString() ?? '',
              senderName: _senderNameFromPayload(payload),
              phase: _agentMessagePhase(payload),
            ) ||
            changed;
        break;
      case _agentTextContentEndedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: {
                'kind': 'message',
                'role': 'assistant',
                'text': payload['text']?.toString() ?? _agentRowText(_payloadItemId(payload)),
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
                if (_agentMessagePhase(payload) != null) 'phase': _agentMessagePhase(payload),
              },
            ) ||
            changed;
        break;
      case _agentReasoningContentStartedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: const {'kind': 'reasoning', 'role': 'assistant', 'text': ''},
            ) ||
            changed;
        break;
      case _agentReasoningContentDeltaType:
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
      case _agentReasoningContentEndedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: {
                'kind': 'reasoning',
                'role': 'assistant',
                'text': payload['text']?.toString() ?? _agentRowText(_payloadItemId(payload)),
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
      case _agentFileContentStartedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: const {'kind': 'file', 'role': 'assistant', 'urls': <String>[]},
            ) ||
            changed;
        break;
      case _agentFileContentDeltaType:
      case _agentFileContentEndedType:
        changed =
            _appendAgentRowUrl(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              url: payload['url']?.toString(),
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case _agentToolCallPendingType:
      case _agentToolCallInProgressType:
      case _agentToolCallStartedType:
      case _agentToolCallEndedType:
        final itemId = _payloadItemId(payload);
        final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
        final tool = payload['tool']?.toString() ?? payload['tool_name']?.toString() ?? payload['name']?.toString() ?? '';
        final resolvedTool = tool.trim().isEmpty ? (existingData?['tool']?.toString() ?? '') : tool;
        final toolkit = payload['toolkit']?.toString() ?? payload['toolkit_name']?.toString() ?? existingData?['toolkit']?.toString() ?? '';
        final arguments = _mapValue(payload['arguments']) ?? _mapValue(existingData?['arguments']);
        final errorMessage = _agentToolCallErrorMessage(payload['error']);
        final errorData = errorMessage == null ? const <String, Object?>{} : <String, Object?>{'error_message': errorMessage};
        final logs = _stringList(existingData?['logs']);
        final isImageGeneration = tool.trim().toLowerCase() == 'image_generation';
        final status = type == _agentToolCallEndedType
            ? (errorMessage == null ? 'completed' : 'failed')
            : (type == _agentToolCallPendingType ? 'pending' : 'running');
        if (isImageGeneration && type == _agentToolCallEndedType && payload['error'] == null) {
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
                      'status_detail': payload['error'] == null ? 'Generating image' : payload['error']?.toString(),
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
                      ...errorData,
                      'text': formatToolCallEntryText(
                        toolkit: toolkit,
                        tool: resolvedTool,
                        arguments: arguments,
                        logs: logs,
                        errorMessage: errorMessage,
                        completed: type == _agentToolCallEndedType,
                        pending: _toolCallStatusIsPending(status),
                        argumentDeltaBytes: _intValue(existingData?['argument_delta_bytes']),
                      ),
                      'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(itemId),
                    },
            ) ||
            changed;
        break;
      case _agentToolCallArgumentsDeltaType:
        changed =
            _appendAgentToolArgumentDelta(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              delta: payload['delta']?.toString() ?? '',
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case _agentToolCallLogDeltaType:
        changed =
            _appendAgentToolLogs(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              lines: _agentToolCallLogLines(payload['lines']),
              senderName: _senderNameFromPayload(payload),
            ) ||
            changed;
        break;
      case _agentImageGenerationStartedType:
      case _agentImageGenerationPartialType:
      case _agentImageGenerationCompletedType:
      case _agentImageGenerationFailedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
              data: {
                'kind': 'image_generation',
                'role': 'assistant',
                'status': _imageGenerationStatusFromType(type),
                'status_detail': payload['status_detail']?.toString(),
                'call_id': payload['call_id']?.toString(),
                'arguments': _mapValue(payload['arguments']),
                'message': payload,
                'sender_name': _senderNameFromPayload(payload) ?? _agentRowSenderName(_payloadItemId(payload)),
              },
            ) ||
            changed;
        break;
      case _agentContextCompactedType:
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
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final nextText = '${existingData?['text']?.toString() ?? ''}$delta';
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {
        'kind': kind,
        'role': role,
        'text': nextText,
        'sender_name': senderName ?? existingData?['sender_name']?.toString(),
        if (phase != null) 'phase': phase else if (existingData?['phase'] != null) 'phase': existingData?['phase'],
      },
    );
  }

  bool _appendAgentRowUrl({required String itemId, required String? turnId, required String? url, required String? senderName}) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return false;
    }
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final urls = _stringList(existingData?['urls']).toList(growable: true);
    if (!urls.contains(normalizedUrl)) {
      urls.add(normalizedUrl);
    }
    return _upsertAgentRow(
      itemId: itemId,
      turnId: turnId,
      data: {'kind': 'file', 'role': 'assistant', 'urls': urls, 'sender_name': senderName ?? existingData?['sender_name']?.toString()},
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
    final arguments = _mapValue(existingData?['arguments']);
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
    if (notify && mounted) {
      setState(() {});
    }
  }

  RemoteParticipant? _agentParticipant() {
    final normalizedAgentName = widget.agentName?.trim();
    for (final participant in widget.room.messaging.remoteParticipants) {
      if (normalizedAgentName != null && normalizedAgentName.isNotEmpty && participant.getAttribute('name') != normalizedAgentName) {
        continue;
      }
      if (participant.getAttribute('supports_agent_messages') == true) {
        return participant;
      }
    }
    return null;
  }

  void _syncOpenSubscription() {
    final agent = _agentParticipant();
    if (agent == null) {
      return;
    }
    if (_openedPath == widget.path && _openedAgentParticipantId == agent.id) {
      return;
    }
    _closeOpenSubscription();
    _openedPath = widget.path;
    _openedAgentParticipantId = agent.id;
    _sendThreadSubscriptionMessageNowait(agent: agent, messageType: _agentThreadOpenType, path: widget.path);
  }

  void _closeOpenSubscription() {
    final openedPath = _openedPath;
    final openedAgentParticipantId = _openedAgentParticipantId;
    _openedPath = null;
    _openedAgentParticipantId = null;
    if (openedPath == null || openedAgentParticipantId == null) {
      return;
    }
    final agent = widget.room.messaging.remoteParticipants.firstWhereOrNull((participant) => participant.id == openedAgentParticipantId);
    if (agent == null) {
      return;
    }
    _sendThreadSubscriptionMessageNowait(agent: agent, messageType: _agentThreadCloseType, path: openedPath);
  }

  void _sendThreadSubscriptionMessageNowait({required RemoteParticipant agent, required String messageType, required String path}) {
    unawaited(() async {
      try {
        await widget.room.messaging.sendMessage(
          to: agent,
          type: _agentRoomMessageType,
          ignoreOffline: true,
          message: {
            'payload': {'type': messageType, 'thread_id': path},
          },
        );
      } catch (_) {}
    }());
  }

  List<_DatasetThreadMessage> _messages() {
    final mergedRowsByItemId = <String, Map<String, Object?>>{};
    mergedRowsByItemId.addAll(_agentRowsByItemId);
    mergedRowsByItemId.addAll(_rowsByItemId);
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
    for (final row in rows) {
      final data = _rowData(row);
      final type = data?['type']?.toString();
      final itemId = row['item_id']?.toString() ?? (data == null ? '' : _payloadItemId(Map<String, dynamic>.from(data)));
      if (_isDatasetToolCallStartType(type)) {
        toolCallsByItemId[itemId] = _DatasetToolCallState.fromPayload(row: row, payload: data!);
        final pendingArgumentDeltaBytes = toolArgumentDeltaBytesByItemId[itemId];
        if (pendingArgumentDeltaBytes != null) {
          toolCallsByItemId[itemId]!.argumentDeltaBytes += pendingArgumentDeltaBytes;
        }
        continue;
      }
      if (type == _agentToolCallLogDeltaType) {
        final state = toolCallsByItemId[itemId];
        if (state != null) {
          state.logs.addAll(_agentToolCallLogLines(data?['lines']));
        }
        continue;
      }
      if (type == _agentToolCallArgumentsDeltaType) {
        final deltaBytes = utf8.encode(data?['delta']?.toString() ?? '').length;
        final state = toolCallsByItemId[itemId];
        if (state != null) {
          state.argumentDeltaBytes += deltaBytes;
        } else {
          toolArgumentDeltaBytesByItemId[itemId] = (toolArgumentDeltaBytesByItemId[itemId] ?? 0) + deltaBytes;
        }
        continue;
      }
      if (type == _agentToolCallEndedType) {
        final state = toolCallsByItemId.remove(itemId);
        final message = _messageForToolCallEndRow(row: row, payload: data, state: state);
        messages.add((row: row, message: message));
        continue;
      }
      final message = _messageForRow(row, turnInputPayloadsById: turnInputPayloadsById);
      messages.add((row: row, message: message));
    }
    return messages;
  }

  Map<String, Map<String, Object?>> _turnInputPayloadsById(Iterable<Map<String, Object?>> rows) {
    final payloadsById = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final data = _rowData(row);
      final type = data?['type']?.toString();
      if (type != _agentTurnStartType && type != _agentTurnSteerType) {
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
      if (type == _agentTurnSteeredType || type == _agentTurnSteerRejectedType) {
        final sourceMessageId = data?['source_message_id']?.toString();
        if (sourceMessageId != null && sourceMessageId.trim().isNotEmpty) {
          pendingByMessageId.remove(sourceMessageId.trim());
        }
        continue;
      }
      if (type == _agentTurnSteerAcceptedType) {
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
      if (type != _agentTurnSteerType || data == null) {
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
        messageType: _agentTurnSteerType,
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

  bool _canInterruptActiveTurn(List<PendingAgentMessage> pendingMessages) {
    return _status.supportsAgentMessages && _status.turnId != null && pendingMessages.isNotEmpty;
  }

  Future<void> _cancelTurn() async {
    final turnId = _status.turnId;
    if (turnId == null || turnId.trim().isEmpty) {
      return;
    }
    final agent = _agentParticipant();
    if (agent == null) {
      return;
    }
    await widget.room.messaging.sendMessage(
      to: agent,
      type: _agentRoomMessageType,
      message: {
        'payload': {'type': _agentTurnInterruptType, 'thread_id': widget.path, 'turn_id': turnId},
      },
    );
  }

  Future<void> _send(String value, List<FileAttachment> attachments) async {
    final agent = _agentParticipant();
    if (agent == null) {
      throw StateError('No online agent supports agent messages for this thread.');
    }

    final isSteer = _status.mode == 'steerable' && _status.turnId != null;
    final messageId = const Uuid().v4();
    final attachmentPaths = attachments.map((attachment) => attachment.path).toList(growable: false);
    final senderName = widget.room.localParticipant?.getAttribute('name');
    _controller.markPendingAgentMessage(
      PendingAgentMessage(
        messageId: messageId,
        messageType: isSteer ? _agentTurnSteerType : _agentTurnStartType,
        threadPath: widget.path,
        text: value,
        attachments: attachmentPaths,
        senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
        createdAt: DateTime.now(),
        awaitingAcceptance: true,
      ),
    );
    _controller.outboundStatus.markSending(messageId);

    try {
      final payload = <String, dynamic>{
        'type': isSteer ? _agentTurnSteerType : _agentTurnStartType,
        'thread_id': widget.path,
        'message_id': messageId,
        'content': _agentInputContent(text: value, attachments: attachmentPaths),
      };
      if (isSteer && _status.turnId != null) {
        payload['turn_id'] = _status.turnId;
      }
      await widget.room.messaging.sendMessage(to: agent, type: _agentRoomMessageType, message: {'payload': payload});
      _controller.outboundStatus.markDelivered(messageId);
      _controller.clear();
    } catch (error, stackTrace) {
      _controller.outboundStatus.markFailed(messageId, error, stackTrace);
      _controller.clearPendingAgentMessagesForThread(widget.path);
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
      supportsAgentMessages: agent != null,
      supportsMcp: agent?.getAttribute('supports_mcp') == true,
      toolkits: const <String, AgentToolkitCapabilities>{},
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
    return ChatThreadInput(
      key: _composerInputKey,
      focusTrigger: _controller,
      sendEnabled: snapshot.supportsAgentMessages,
      sendDisabledReason: !snapshot.supportsAgentMessages ? 'This thread requires an online agent that supports agent messages.' : null,
      onInterrupt: _canInterruptActiveTurn(pendingMessages) ? _cancelTurn : null,
      sendPendingText: waitingForOnlineMessage == null
          ? null
          : 'Waiting for ${_displayAgentName(widget.agentName ?? "agent")} to come online.',
      placeholder: widget.inputPlaceholder,
      leading: toolArea.leading,
      footer: toolArea.footer,
      trailing: null,
      room: widget.room,
      controller: _controller,
      attachmentBuilder: widget.attachmentBuilder,
      contextMenuBuilder: widget.inputContextMenuBuilder,
      onPressedOutside: widget.inputOnPressedOutside,
      onSend: _send,
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
        return Padding(
          padding: const EdgeInsets.only(left: 42, right: 18),
          child: SizedBox(
            width: double.infinity,
            child: _buildToolCallSummaryText(
              context,
              expanded && expandedToolCallEntry != null ? expandedToolCallEntry : toolCallEntry,
              canExpand: expandedToolCallEntry != null && expandedToolCallEntry.text != toolCallEntry.text,
              onTapDetails: () {
                if (expandedToolCallEntry == null || expandedToolCallEntry.text == toolCallEntry.text) {
                  return;
                }
                setState(() {
                  if (!_expandedToolCallIds.add(message.id)) {
                    _expandedToolCallIds.remove(message.id);
                  }
                });
              },
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
      if (pending.messageType == _agentTurnSteerType || pending.matchByContentOnly) {
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

    final activeTurnId = _status.turnId?.trim();
    if (activeTurnId != null && activeTurnId.isNotEmpty) {
      for (var index = start; index < end; index += 1) {
        final messageTurnId = messages[index].turnId?.trim();
        if (messageTurnId == null || messageTurnId.isEmpty || messageTurnId == activeTurnId) {
          return -1;
        }
      }
    }

    var inferredFinalIndex = -1;
    for (var index = start; index < end; index += 1) {
      if (_datasetThreadMessageCanRenderAsFinalAnswer(messages[index])) {
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
    final headerText = TextSpan(
      children: [
        TextSpan(text: display.headline.action, style: highlightStyle),
        if (headlineRest.trim().isNotEmpty) TextSpan(text: ' $headlineRest'),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText.rich(headerText, style: baseStyle, textAlign: TextAlign.left),
        if (detailLines.isNotEmpty) details,
      ],
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
              (pending.messageType == _agentTurnStartType || pending.messageType == _agentTurnSteerType) &&
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
                if (_canInterruptActiveTurn(pendingMessages))
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

  Widget _buildThreadViewport(BuildContext context, List<_DatasetThreadMessage> messages, List<PendingAgentMessage> pendingMessages) {
    final statusText = _status.text?.trim();
    final showStatus = shouldShowChatThreadStatus(_status);
    final feedImages = _collectThreadImages(messages);
    final threadView = ChatThreadViewportBody(
      scrollController: _controller.threadScrollController,
      bottomAlign: true,
      centerContent: ChatThreadEmptyStateContent(
        title: widget.emptyStateTitle ?? 'Chat to get started',
        description: widget.emptyStateDescription,
      ),
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
                  text: statusText ?? '',
                  startedAt: _status.startedAt,
                  totalBytes: _status.totalBytes,
                  onCancel: _canInterruptActiveTurn(pendingMessages) ? _cancelTurn : null,
                  showCancelButton: _status.mode != null,
                  cancelEnabled: true,
                ),
              ),
            ),
          ),
      ],
      children: _buildMessageWidgets(context, messages, pendingMessages, feedImages: feedImages),
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
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final messages = _messages();
        final pendingMessages = _combinedPendingMessages(messages);
        final snapshot = _snapshot(messages, pendingMessages);
        return FileDropArea(
          onFileDrop: (name, dataStream, size) async {
            await _controller.uploadFile(name, dataStream, size ?? 0);
          },
          child: Column(
            children: [
              Expanded(child: _buildThreadViewport(context, messages, pendingMessages)),
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
  final String? authorName;
  final String? phase;
  final String? turnId;
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
  String? authorName;
  final DateTime createdAt;
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
          statusDetail:
              _stringValue(data['status_detail']) ?? _stringValue(message?['status_detail']) ?? _stringValue(image?['status_detail']),
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

  final itemId = row['item_id']?.toString() ?? _payloadItemId(Map<String, dynamic>.from(payload));
  final createdAt = _rowTimestamp(row);
  final turnId = row['turn_id']?.toString() ?? payload['turn_id']?.toString();
  final phase = _agentMessagePhase(payload);
  switch (type) {
    case _agentTurnStartType:
    case _agentTurnSteerType:
      return null;
    case _agentTurnStartedType:
    case _agentTurnSteeredType:
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
    case _agentTurnStartAcceptedType:
    case _agentTurnSteerAcceptedType:
      return null;
    case _agentTextContentDeltaType:
      final text = payload['text']?.toString() ?? '';
      return text.trim().isEmpty
          ? null
          : _DatasetThreadMessage(
              id: itemId,
              kind: 'message',
              role: 'agent',
              text: text,
              authorName: payload['sender_name']?.toString(),
              attachments: const [],
              createdAt: createdAt,
              phase: phase,
              turnId: turnId,
            );
    case _agentReasoningContentDeltaType:
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
    case _agentFileContentDeltaType:
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
    case _agentImageGenerationStartedType:
    case _agentImageGenerationPartialType:
    case _agentImageGenerationCompletedType:
    case _agentImageGenerationFailedType:
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
          statusDetail: _stringValue(payload['status_detail']) ?? _stringValue(image?['status_detail']),
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
    case _agentToolCallStartedType:
    case _agentToolCallArgumentsDeltaType:
    case _agentToolCallLogDeltaType:
      return null;
    case _agentToolCallEndedType:
      return _messageForToolCallEndRow(row: row, payload: payload, state: null);
    case _agentContextCompactedType:
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
  }
  return null;
}

bool _isDatasetToolCallStartType(String? type) {
  return type == _agentToolCallPendingType || type == _agentToolCallInProgressType || type == _agentToolCallStartedType;
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
    authorName: payload?['sender_name']?.toString() ?? state?.authorName,
    attachments: const [],
    createdAt: _rowTimestamp(row),
    turnId: row['turn_id']?.toString() ?? payload?['turn_id']?.toString(),
  );
}

String? _agentToolCallErrorMessage(Object? error) {
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
  if (pending.messageType == _agentTurnSteerType || pending.matchByContentOnly) {
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

List<Map<String, dynamic>> _agentInputContent({required String text, required List<String> attachments}) {
  final content = <Map<String, dynamic>>[];
  if (text.trim().isNotEmpty) {
    content.add({'type': 'text', 'text': text});
  }
  for (final attachment in attachments) {
    final url = _normalizeAgentAttachmentUrl(attachment);
    if (url != null) {
      content.add({'type': 'file', 'url': url});
    }
  }
  return content;
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
  if (phase is! String) {
    return null;
  }
  final normalized = phase.trim();
  return normalized == 'commentary' || normalized == 'final_answer' ? normalized : null;
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
  return type == _agentImageGenerationStartedType ||
      type == _agentImageGenerationPartialType ||
      type == _agentImageGenerationCompletedType ||
      type == _agentImageGenerationFailedType;
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
      rawType == _agentImageGenerationStartedType ||
          rawType == _agentImageGenerationPartialType ||
          rawType == _agentImageGenerationCompletedType ||
          rawType == _agentImageGenerationFailedType
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
    case _agentImageGenerationCompletedType:
      return 'completed';
    case _agentImageGenerationFailedType:
      return 'failed';
    case _agentImageGenerationPartialType:
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
