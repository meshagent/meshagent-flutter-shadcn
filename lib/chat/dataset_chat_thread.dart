import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'chat.dart';

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
const String _agentToolCallEndedType = 'meshagent.agent.tool_call.ended';
const String _agentImageGenerationStartedType = 'meshagent.agent.image_generation.started';
const String _agentImageGenerationPartialType = 'meshagent.agent.image_generation.partial';
const String _agentImageGenerationCompletedType = 'meshagent.agent.image_generation.completed';
const String _agentImageGenerationFailedType = 'meshagent.agent.image_generation.failed';

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

  @override
  State<DatasetChatThread> createState() => _DatasetChatThreadState();
}

class _DatasetChatThreadState extends State<DatasetChatThread> {
  StreamSubscription<DatasetTableWatchEvent>? _watchSubscription;
  StreamSubscription<RoomEvent>? _roomSubscription;
  Timer? _watchRetryTimer;
  final Map<String, Map<String, Object?>> _rowsByItemId = {};
  final Map<String, Map<String, Object?>> _initialRowsByItemId = {};
  final Map<String, Map<String, Object?>> _agentRowsByItemId = {};
  late ChatThreadController _controller;
  late bool _ownsController;
  late Key _composerInputKey;
  Object? _error;
  bool _fatalError = false;
  bool _ready = false;
  late bool _showCompletedToolCalls;
  ChatThreadStatusState _status = const ChatThreadStatusState();
  int _nextAgentSequence = 0;
  String? _openedPath;
  String? _openedAgentParticipantId;
  final OverlayPortalController _imageViewerController = OverlayPortalController();
  LocalHistoryEntry? _imageViewerHistoryEntry;
  List<ChatThreadFeedImage> _overlayImages = const <ChatThreadFeedImage>[];
  int _overlayInitialIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(_controller);
    _showCompletedToolCalls = widget.initialShowCompletedToolCalls;
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
      _refreshStatus();
      _syncOpenSubscription();
    }
    if (oldWidget.path != widget.path || oldWidget.room != widget.room) {
      _startWatch();
    }
  }

  @override
  void dispose() {
    _watchRetryTimer?.cancel();
    _watchSubscription?.cancel();
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
    _watchRetryTimer?.cancel();
    _watchSubscription?.cancel();
    _rowsByItemId.clear();
    _initialRowsByItemId.clear();
    _agentRowsByItemId.clear();
    _nextAgentSequence = 0;
    _error = null;
    _fatalError = false;
    _ready = false;

    if (_isTmpThreadPath(widget.path)) {
      _ready = true;
      _materializePendingMessagesForThread();
      return;
    }

    _connectDatasetWatch();
  }

  void _connectDatasetWatch() {
    _watchRetryTimer?.cancel();
    _watchSubscription?.cancel();
    try {
      final ref = _DatasetThreadRef.parse(widget.path);
      _watchSubscription = widget.room.datasets
          .watchTable(table: ref.table, namespace: ref.namespace)
          .listen(_handleWatchEvent, onError: _handleWatchError);
    } catch (error) {
      _error = error;
      _fatalError = true;
      _ready = true;
    }
  }

  void _handleWatchError(Object error, StackTrace stackTrace) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_isDatasetTableNotFoundError(error)) {
        _error = null;
        _fatalError = false;
        _scheduleDatasetWatchRetry();
      } else {
        _error = error;
        _fatalError = true;
      }
      _ready = true;
    });
  }

  void _scheduleDatasetWatchRetry() {
    _watchRetryTimer?.cancel();
    _watchRetryTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) {
        return;
      }
      _connectDatasetWatch();
    });
  }

  void _handleWatchEvent(DatasetTableWatchEvent event) {
    if (!_ready) {
      _handlePreReadyWatchEvent(event);
      return;
    }

    var changed = false;
    if (event.kind == 'delete' && event.deletePredicate != null) {
      changed = _applyDeletePredicate(event.deletePredicate!, _rowsByItemId) || changed;
    }

    final batch = event.batch;
    if (batch != null) {
      if (event.kind == 'delete' || event.changeType == 'delete') {
        for (final row in batch.toRows()) {
          final predicate = row['predicate']?.toString();
          if (predicate != null && predicate.trim().isNotEmpty) {
            changed = _applyDeletePredicate(predicate, _rowsByItemId) || changed;
          }
        }
        _finishWatchEvent(event, changed);
        return;
      }
      if (event.kind == 'transactions' || event.changeType == 'transactions') {
        _finishWatchEvent(event, changed);
        return;
      }
      changed = _applyRowsToMap(batch.toRows(), _rowsByItemId) || changed;
    }

    _finishWatchEvent(event, changed);
  }

  void _handlePreReadyWatchEvent(DatasetTableWatchEvent event) {
    var changed = false;
    if (event.kind == 'delete' && event.deletePredicate != null) {
      changed = _applyDeletePredicate(event.deletePredicate!, _initialRowsByItemId) || changed;
    }

    final batch = event.batch;
    if (batch != null) {
      if (event.kind == 'delete' || event.changeType == 'delete') {
        for (final row in batch.toRows()) {
          final predicate = row['predicate']?.toString();
          if (predicate != null && predicate.trim().isNotEmpty) {
            changed = _applyDeletePredicate(predicate, _initialRowsByItemId) || changed;
          }
        }
      } else if (event.kind != 'transactions' && event.changeType != 'transactions') {
        changed = _applyRowsToMap(batch.toRows(), _initialRowsByItemId) || changed;
      }
    }

    if (event.kind != 'ready') {
      if (changed && mounted) {
        setState(() {});
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _rowsByItemId
        ..clear()
        ..addAll(_initialRowsByItemId);
      _initialRowsByItemId.clear();
      _ready = true;
    });
    _controller.scrollThreadToBottom(animated: false);
  }

  void _finishWatchEvent(DatasetTableWatchEvent event, bool changed) {
    final initialReady = event.kind == 'ready' && event.phase == DatasetTableWatchPhase.initial && !_ready;
    if (initialReady || changed) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
      if (changed) {
        _controller.scrollThreadToBottom(animated: false);
      }
    }
  }

  bool _applyRowsToMap(Iterable<Map<String, Object?>> rows, Map<String, Map<String, Object?>> target) {
    var changed = false;
    for (final row in rows) {
      final normalized = Map<String, Object?>.from(row);
      final itemId = normalized['item_id']?.toString();
      if (itemId == null || itemId.trim().isEmpty) {
        continue;
      }
      final existing = target[itemId];
      if (existing == null || !const DeepCollectionEquality().equals(existing, normalized)) {
        target[itemId] = normalized;
        _agentRowsByItemId.remove(itemId);
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

  void _removeReconciledAgentRowsForDatasetRow(Map<String, Object?> datasetRow) {
    final datasetData = _rowData(datasetRow);
    if (datasetData?['kind'] != 'image_generation') {
      return;
    }
    final datasetKeys = _imageGenerationCorrelationKeys(datasetRow);
    if (datasetKeys.isEmpty) {
      return;
    }
    final liveItemIds = _agentRowsByItemId.entries
        .where((entry) {
          final liveData = _rowData(entry.value);
          if (liveData?['kind'] != 'image_generation') {
            return false;
          }
          return _imageGenerationCorrelationKeys(entry.value).any(datasetKeys.contains);
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
    final maxDatasetSequence = _maxDatasetSequence();
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
      if (_rowsByItemId.containsKey(itemId) || _initialRowsByItemId.containsKey(itemId)) {
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
    for (final row in [..._rowsByItemId.values, ..._initialRowsByItemId.values]) {
      final sequence = _intValue(row['sequence']);
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence;
  }

  bool _applyDeletePredicate(String predicate, Map<String, Map<String, Object?>> target) {
    final itemIds = _itemIdsForDeletePredicate(predicate);
    if (itemIds.isEmpty) {
      return false;
    }
    var changed = false;
    for (final itemId in itemIds) {
      changed = target.remove(itemId) != null || changed;
    }
    return changed;
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
        _handleAgentMessagePayload(payload);
      } else if (payload is Map) {
        _handleAgentMessagePayload(Map<String, dynamic>.from(payload));
      }
    }
    _refreshStatus(notify: true);
  }

  void _handleAgentMessagePayload(Map<String, dynamic> payload) {
    final changed = _applyAgentMessagePayload(payload);
    _controller.handleAgentMessagePayload(payload);
    if (changed && mounted) {
      setState(() {});
      _controller.scrollThreadToBottom(animated: false);
    }
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
      case _agentTurnStartAcceptedType:
      case _agentTurnSteerAcceptedType:
        break;
      case _agentTurnStartedType:
      case _agentTurnSteeredType:
        changed = _materializePendingMessage(payload['source_message_id']?.toString()) || _materializeTurnInputPayload(payload) || changed;
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
            ) ||
            changed;
        break;
      case _agentTextContentEndedType:
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: {'kind': 'message', 'role': 'assistant', 'text': payload['text']?.toString() ?? _agentRowText(_payloadItemId(payload))},
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
            _appendAgentRowUrl(itemId: _payloadItemId(payload), turnId: _payloadTurnId(payload), url: payload['url']?.toString()) ||
            changed;
        break;
      case _agentToolCallPendingType:
      case _agentToolCallInProgressType:
      case _agentToolCallStartedType:
      case _agentToolCallEndedType:
        final tool = payload['tool']?.toString() ?? payload['tool_name']?.toString() ?? payload['name']?.toString() ?? '';
        final isImageGeneration = tool.trim().toLowerCase() == 'image_generation';
        if (isImageGeneration && type == _agentToolCallEndedType && payload['error'] == null) {
          break;
        }
        changed =
            _upsertAgentRow(
              itemId: _payloadItemId(payload),
              turnId: _payloadTurnId(payload),
              data: isImageGeneration
                  ? {
                      'kind': 'image_generation',
                      'role': 'assistant',
                      'status': payload['error'] == null ? 'in_progress' : 'failed',
                      'status_detail': payload['error'] == null ? 'Generating image' : payload['error']?.toString(),
                      'call_id': payload['call_id']?.toString(),
                      'arguments': _mapValue(payload['arguments']),
                    }
                  : {
                      'kind': 'tool_call',
                      'role': 'assistant',
                      'toolkit': payload['toolkit']?.toString() ?? payload['toolkit_name']?.toString() ?? '',
                      'tool': tool,
                      'status': type == _agentToolCallEndedType ? 'completed' : 'running',
                    },
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
              },
            ) ||
            changed;
        break;
    }
    return changed;
  }

  bool _materializeTurnInputPayload(Map<String, dynamic> payload) {
    final messageId = payload['source_message_id']?.toString() ?? payload['message_id']?.toString();
    if (messageId == null || messageId.trim().isEmpty) {
      return false;
    }
    if (_rowsByItemId.containsKey(messageId) || _initialRowsByItemId.containsKey(messageId) || _agentRowsByItemId.containsKey(messageId)) {
      return false;
    }

    final content = payload['content'];
    if (content is! List) {
      return false;
    }

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

    final text = textParts.join('\n');
    if (text.trim().isEmpty && attachments.isEmpty) {
      return false;
    }

    return _upsertAgentRow(
      itemId: messageId,
      turnId: payload['turn_id']?.toString(),
      timestamp: _timestampFromPayload(payload) ?? DateTime.now().toUtc(),
      data: {
        'kind': 'message',
        'role': 'user',
        'text': text,
        'sender_name': payload['sender_name']?.toString(),
        'attachments': attachments,
      },
    );
  }

  bool _materializePendingMessagesForThread() {
    var changed = false;
    for (final pending in _controller.pendingAgentMessagesForPath(widget.path)) {
      changed = _materializePendingMessage(pending.messageId) || changed;
    }
    return changed;
  }

  bool _materializePendingMessage(String? messageId) {
    if (messageId == null || messageId.trim().isEmpty || _agentRowsByItemId.containsKey(messageId)) {
      return false;
    }
    PendingAgentMessage? pending;
    for (final candidate in _controller.pendingAgentMessagesForPath(widget.path)) {
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
    if (_rowsByItemId.containsKey(itemId) || _initialRowsByItemId.containsKey(itemId)) {
      return false;
    }
    final candidateRow = <String, Object?>{'turn_id': turnId, 'item_id': itemId, 'data': data};
    if (_isReconciledByDatasetRows(candidateRow)) {
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
    final liveData = _rowData(liveRow);
    if (liveData?['kind'] != 'image_generation') {
      return false;
    }
    final liveKeys = _imageGenerationCorrelationKeys(liveRow);
    if (liveKeys.isEmpty) {
      return false;
    }
    for (final datasetRow in [..._rowsByItemId.values, ..._initialRowsByItemId.values]) {
      final datasetData = _rowData(datasetRow);
      if (datasetData?['kind'] != 'image_generation') {
        continue;
      }
      if (_imageGenerationCorrelationKeys(datasetRow).any(liveKeys.contains)) {
        return true;
      }
    }
    return false;
  }

  bool _appendAgentRowText({
    required String itemId,
    required String? turnId,
    required String kind,
    required String role,
    required String delta,
  }) {
    if (delta.isEmpty) {
      return false;
    }
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final nextText = '${existingData?['text']?.toString() ?? ''}$delta';
    return _upsertAgentRow(itemId: itemId, turnId: turnId, data: {'kind': kind, 'role': role, 'text': nextText});
  }

  bool _appendAgentRowUrl({required String itemId, required String? turnId, required String? url}) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return false;
    }
    final existingData = _mapValue(_agentRowsByItemId[itemId]?['data']);
    final urls = _stringList(existingData?['urls']).toList(growable: true);
    if (!urls.contains(normalizedUrl)) {
      urls.add(normalizedUrl);
    }
    return _upsertAgentRow(itemId: itemId, turnId: turnId, data: {'kind': 'file', 'role': 'assistant', 'urls': urls});
  }

  String _agentRowText(String itemId) {
    return _mapValue(_agentRowsByItemId[itemId]?['data'])?['text']?.toString() ?? '';
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
    final messages = <_DatasetThreadMessage>[];
    for (final row in rows) {
      final message = _messageForRow(row);
      if (message != null && _shouldRenderDatasetThreadMessage(message)) {
        messages.add(message);
      }
    }
    return messages;
  }

  bool _hasWireBackedContent() {
    return _agentRowsByItemId.isNotEmpty ||
        _status.pendingMessages.isNotEmpty ||
        _controller.pendingAgentMessagesForPath(widget.path).isNotEmpty;
  }

  bool _shouldRenderDatasetThreadMessage(_DatasetThreadMessage message) {
    if (message.kind == 'tool_call') {
      return _showCompletedToolCalls;
    }
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
    final values = combined.values.where((pending) {
      return !messages.any((message) => _datasetThreadMessageMatchesPendingAgentMessage(message, pending));
    }).toList();
    return [...values.where((message) => !message.awaitingAcceptance), ...values.where((message) => message.awaitingAcceptance)];
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
      supportsAgentMessages: agent != null,
      supportsMcp: agent?.getAttribute('supports_mcp') == true,
      toolkits: const <String, AgentToolkitCapabilities>{},
      threadTurnId: _status.turnId,
      pendingMessages: pendingMessages,
      pendingItemId: _status.pendingItemId,
    );
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

  Widget _buildMessage(BuildContext context, _DatasetThreadMessage message, {required List<ChatThreadFeedImage> feedImages}) {
    final theme = ShadTheme.of(context);
    if (message.kind != 'message') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Text(message.text, style: theme.textTheme.muted, textAlign: TextAlign.center),
      );
    }

    final localParticipantName = widget.room.localParticipant?.getAttribute('name');
    final isAgentMessage = message.role == 'agent';
    final rawAuthorName = message.authorName;
    final mine =
        !isAgentMessage &&
        (rawAuthorName == localParticipantName || ((rawAuthorName == null || rawAuthorName.trim().isEmpty) && message.role == 'user'));
    final authorName = rawAuthorName ?? (isAgentMessage ? _displayAgentName(widget.agentName ?? 'agent') : '');
    final imageAttachmentId = message.id;
    final imageInitialIndex = feedImages.indexWhere((entry) => entry.attachmentElementId == imageAttachmentId);

    return ChatThreadMessageView(
      key: ValueKey(message.id),
      room: widget.room,
      mine: mine,
      isAgentMessage: isAgentMessage,
      text: message.text,
      authorName: authorName,
      createdAt: message.createdAt,
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

  List<Widget> _buildMessageWidgets(
    BuildContext context,
    List<_DatasetThreadMessage> messages,
    List<PendingAgentMessage> pendingMessages, {
    required List<ChatThreadFeedImage> feedImages,
  }) {
    final messageWidgets = <Widget>[];
    for (final message in messages.indexed) {
      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(0, const SizedBox(height: ChatThreadMessageView.chatMessageStackSpacing));
      }
      messageWidgets.insert(
        0,
        Container(
          key: ValueKey(message.$2.id),
          child: _buildMessage(context, message.$2, feedImages: feedImages),
        ),
      );
    }
    for (final pending in pendingMessages) {
      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(0, const SizedBox(height: ChatThreadMessageView.chatMessageStackSpacing));
      }
      messageWidgets.insert(0, PendingChatThreadMessage(room: widget.room, message: pending));
    }
    return messageWidgets;
  }

  Widget _buildThreadViewport(BuildContext context, List<_DatasetThreadMessage> messages, List<PendingAgentMessage> pendingMessages) {
    final statusText = _status.text?.trim();
    final showStatus = statusText != null && statusText.isNotEmpty;
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
                  text: statusText,
                  startedAt: _status.startedAt,
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
    if (!_ready && !hasWireBackedContent) {
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
              ChatThreadInputFrame(child: _buildInput(context, snapshot, pendingMessages)),
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
    this.authorName,
  });

  final String id;
  final String kind;
  final String role;
  final String text;
  final List<String> attachments;
  final DateTime createdAt;
  final _DatasetThreadImage? image;
  final String? authorName;
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

_DatasetThreadMessage? _messageForRow(Map<String, Object?> row) {
  final data = _rowData(row);
  if (data == null) {
    return null;
  }
  final kind = data['kind']?.toString();
  final itemId = row['item_id']?.toString() ?? const Uuid().v4();
  final role = data['role']?.toString();
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
        authorName: _stringValue(image?['created_by']),
        attachments: const [],
        createdAt: _rowTimestamp(row),
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
              attachments: const [],
              createdAt: _rowTimestamp(row),
            );
    case 'tool_call':
      final toolkit = data['toolkit']?.toString() ?? '';
      final tool = data['tool']?.toString() ?? '';
      final summary = [toolkit, tool].where((part) => part.trim().isNotEmpty).join('.');
      return _DatasetThreadMessage(
        id: itemId,
        kind: 'tool_call',
        role: 'agent',
        text: summary.isEmpty ? 'Tool call' : summary,
        attachments: const [],
        createdAt: _rowTimestamp(row),
      );
  }
  return null;
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
  final itemId = payload['item_id'];
  if (itemId is String && itemId.trim().isNotEmpty) {
    return itemId.trim();
  }
  final messageId = payload['message_id'];
  if (messageId is String && messageId.trim().isNotEmpty) {
    return messageId.trim();
  }
  return const Uuid().v4();
}

String? _payloadTurnId(Map<String, dynamic> payload) {
  final turnId = payload['turn_id'];
  if (turnId is! String) {
    return null;
  }
  final trimmed = turnId.trim();
  return trimmed.isEmpty ? null : trimmed;
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

Set<String> _imageGenerationCorrelationKeys(Map<String, Object?> row) {
  final keys = <String>{};
  final itemId = _stringValue(row['item_id']);
  if (itemId != null) {
    keys.add('item:$itemId');
  }
  final data = _rowData(row);
  final message = _mapValue(data?['message']);
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

List<String> _itemIdsForDeletePredicate(String predicate) {
  final normalized = predicate.trim();
  final equality = RegExp(r'''^"?item_id"?\s*=\s*['"]([^'"]+)['"]$''', caseSensitive: false).firstMatch(normalized);
  if (equality != null) {
    return [equality.group(1)!];
  }

  final inList = RegExp(r'''^"?item_id"?\s+in\s*\((.*)\)$''', caseSensitive: false).firstMatch(normalized);
  if (inList == null) {
    return const [];
  }
  return RegExp(r'''['"]([^'"]+)['"]''').allMatches(inList.group(1)!).map((match) => match.group(1)!).toList(growable: false);
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
