import 'dart:collection';
import 'package:flutter/foundation.dart';

enum OutboundStatus {
  sending,
  sent,
  failed;

  String get name {
    switch (this) {
      case OutboundStatus.sending:
        return 'Sending...';
      case OutboundStatus.sent:
        return 'Delivered';
      case OutboundStatus.failed:
        return 'Failed to send';
    }
  }

  int get colorValue {
    switch (this) {
      case OutboundStatus.sending:
        return 0xFF929292;
      case OutboundStatus.sent:
        return 0xFF929292;
      case OutboundStatus.failed:
        return 0xFFFF4A4A;
    }
  }
}

abstract class OutboundState {
  const OutboundState({required this.status});

  final OutboundStatus status;
}

class Sending extends OutboundState {
  const Sending({required this.startedAt}) : super(status: OutboundStatus.sending);

  final DateTime startedAt;
}

class Delivered extends OutboundState {
  const Delivered({required this.completedAt}) : super(status: OutboundStatus.sent);

  final DateTime completedAt;
}

class Failed extends OutboundState {
  const Failed({required this.error, this.stackTrace}) : super(status: OutboundStatus.failed);

  final Object error;
  final StackTrace? stackTrace;
}

class OutboundEntry {
  OutboundEntry({required this.messageId, required this.state});

  final String messageId;
  OutboundState state;

  OutboundEntry copyWith({OutboundState? state}) {
    return OutboundEntry(messageId: messageId, state: state ?? this.state);
  }
}

abstract class OutboundStatusSink {
  void markSending(String id);
  void markDelivered(String id);
  void markFailed(String id, Object error, [StackTrace? stackTrace]);
}

class OutboundMessageStatusQueue extends ChangeNotifier implements OutboundStatusSink {
  OutboundMessageStatusQueue();

  bool _disposed = false;

  final LinkedHashMap<String, OutboundEntry> _entries = LinkedHashMap();

  OutboundEntry? _lastSentEntry;

  OutboundEntry? currentEntry() {
    final id = statusOwnerId;

    return id == null ? _lastSentEntry : _entries[id];
  }

  List<OutboundEntry> get entries {
    return List.unmodifiable(_entries.values.toList());
  }

  String? get statusOwnerId {
    if (_entries.isEmpty) return null;

    for (final e in _entries.values) {
      if (e.state.status == OutboundStatus.sending) return e.messageId;
    }

    return _entries.values.last.messageId;
  }

  @override
  void markSending(String id) {
    if (_entries.containsKey(id)) return;

    _entries[id] = OutboundEntry(messageId: id, state: Sending(startedAt: DateTime.now()));

    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void markDelivered(String id) {
    final e = _entries[id];

    if (e == null) return;

    _entries[id] = e.copyWith(state: Delivered(completedAt: DateTime.now()));

    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void markFailed(String id, Object error, [StackTrace? stackTrace]) {
    final e = _entries[id];

    if (e == null) return;

    _entries[id] = e.copyWith(state: Failed(error: error, stackTrace: stackTrace));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();

    super.dispose();
  }
}
