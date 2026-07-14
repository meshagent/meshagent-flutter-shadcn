import 'package:meshagent_agents/meshagent_agents.dart'
    show
        agentThreadClearedType,
        agentThreadStatusType,
        agentToolCallApprovalRequestedType,
        agentToolCallArgumentsDeltaType,
        agentToolCallEndedType,
        agentToolCallInProgressType,
        agentToolCallPendingType,
        agentToolCallStartedType,
        agentTurnEndedType,
        agentTurnStartAcceptedType,
        agentTurnStartedType,
        agentTurnStartType,
        agentTurnSteerAcceptedType,
        agentTurnSteeredType,
        agentTurnSteerType;

import 'chat.dart';

class ChatTurnStateReducer {
  final Set<String> _completedTurnIds = <String>{};

  bool applyDatasetRow(Map<String, Object?> row) {
    final data = _rowData(row);
    if (data == null) {
      return false;
    }
    return _applyPayload(data, rowTurnId: row['turn_id']?.toString(), persisted: true);
  }

  bool applyLivePayload(Map<String, dynamic> payload) {
    return _applyPayload(payload, rowTurnId: null, persisted: false);
  }

  bool shouldIgnoreStatusPayload(Map<String, Object?> payload) {
    final type = payload['type']?.toString();
    if (!_statusStorePayloadTypes.contains(type)) {
      return false;
    }
    final turnId = _payloadTurnId(payload);
    return turnId != null && _completedTurnIds.contains(turnId);
  }

  ChatThreadStatusState reduceStatus(ChatThreadStatusState status) {
    final turnId = status.turnId?.trim();
    if (turnId == null || turnId.isEmpty || !_completedTurnIds.contains(turnId)) {
      return status;
    }
    return ChatThreadStatusState(supportsAgentMessages: status.supportsAgentMessages);
  }

  bool isTurnComplete(String turnId) => _completedTurnIds.contains(turnId.trim());

  void clear() {
    _completedTurnIds.clear();
  }

  bool _applyPayload(Map<String, Object?> payload, {required String? rowTurnId, required bool persisted}) {
    final type = payload['type']?.toString();
    if (type == agentThreadClearedType) {
      final hadCompleted = _completedTurnIds.isNotEmpty;
      _completedTurnIds.clear();
      return hadCompleted;
    }

    final turnId = _payloadTurnId(payload) ?? _normalizedString(rowTurnId);
    if (turnId == null) {
      return false;
    }

    if (type == agentTurnEndedType || (persisted && _persistedPayloadCompletesTurn(payload, type: type))) {
      return _completedTurnIds.add(turnId);
    }
    return false;
  }

  bool _persistedPayloadCompletesTurn(Map<String, Object?> payload, {required String? type}) {
    if (type == null) {
      return _persistedKindPayloadCompletesTurn(payload);
    }
    return false;
  }

  bool _persistedKindPayloadCompletesTurn(Map<String, Object?> payload) {
    final kind = payload['kind']?.toString().trim().toLowerCase();
    final role = payload['role']?.toString().trim().toLowerCase();
    if (role != 'assistant' && role != 'agent') {
      return false;
    }

    switch (kind) {
      case 'message':
        if (_isRunningStatus(payload['status'])) {
          return false;
        }
        if (payload['phase']?.toString().trim().toLowerCase() == 'commentary') {
          return false;
        }
        return _normalizedString(payload['text']) != null || _hasAttachments(payload['attachments']);
      case 'file':
        if (_isRunningStatus(payload['status'])) {
          return false;
        }
        if (payload['phase']?.toString().trim().toLowerCase() != 'final_answer') {
          return false;
        }
        return _hasAttachments(payload['urls']) || _hasAttachments(payload['attachments']);
    }
    return false;
  }
}

const Set<String?> _statusStorePayloadTypes = <String?>{
  agentThreadStatusType,
  agentTurnStartType,
  agentTurnSteerType,
  agentTurnStartAcceptedType,
  agentTurnSteerAcceptedType,
  agentTurnStartedType,
  agentTurnSteeredType,
  agentToolCallArgumentsDeltaType,
  agentToolCallPendingType,
  agentToolCallInProgressType,
  agentToolCallStartedType,
  agentToolCallApprovalRequestedType,
  agentToolCallEndedType,
};

Map<String, Object?>? _rowData(Map<String, Object?> row) {
  final data = row['data'];
  if (data is Map<String, Object?>) {
    return data;
  }
  if (data is Map) {
    return Map<String, Object?>.from(data);
  }
  return null;
}

String? _payloadTurnId(Map<String, Object?> payload) {
  return _normalizedString(payload['turn_id']);
}

String? _normalizedString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _hasAttachments(Object? value) {
  if (value is! List) {
    return false;
  }
  for (final item in value) {
    if (item is String && item.trim().isNotEmpty) {
      return true;
    }
    if (item is Map) {
      final url = item['url'];
      if (url is String && url.trim().isNotEmpty) {
        return true;
      }
    }
  }
  return false;
}

bool _isRunningStatus(Object? status) {
  final normalized = status?.toString().trim().toLowerCase();
  return normalized == 'pending' || normalized == 'in_progress' || normalized == 'running';
}
