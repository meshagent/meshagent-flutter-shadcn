import 'package:flutter/material.dart';

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

  Color get color {
    switch (this) {
      case OutboundStatus.sending:
        return const Color(0xFF929292);
      case OutboundStatus.sent:
        return const Color(0xFF929292);
      case OutboundStatus.failed:
        return const Color(0xFFFF4A4A);
    }
  }
}

class OutboundEntry {
  OutboundEntry({required this.messageId, required this.startedAt, required this.future, this.status = OutboundStatus.sending, this.error});

  final String messageId;
  final DateTime startedAt;
  final Future<void> future;

  OutboundStatus status;
  Object? error;
}

class OutboundMessageStatusQueue extends ChangeNotifier {
  OutboundMessageStatusQueue();

  bool _disposed = false;

  final List<String> _order = <String>[];

  final Map<String, OutboundEntry> _entries = <String, OutboundEntry>{};

  OutboundEntry? _lastSentEntry;

  OutboundEntry? currentEntry() {
    final id = statusOwnerId;

    return id == null ? _lastSentEntry : _entries[id];
  }

  List<OutboundEntry> get entries {
    return List.unmodifiable(_order.map((id) => _entries[id]!).toList());
  }

  String? get statusOwnerId {
    if (_order.isEmpty) return null;

    for (final id in _order) {
      final e = _entries[id]!;

      if (e.status == OutboundStatus.sending) return id;
    }

    return _order.last;
  }

  void setSending({required String messageId, required Future<void> sendFuture}) {
    if (_entries.containsKey(messageId)) return;

    final entry = OutboundEntry(messageId: messageId, startedAt: DateTime.now(), future: sendFuture, status: OutboundStatus.sending);

    _entries[messageId] = entry;
    _order.add(messageId);
    _lastSentEntry = entry;

    if (!_disposed) {
      notifyListeners();
    }

    sendFuture
        .then((_) {
          if (!_disposed) {
            _setDelivered(messageId);
          }
        })
        .catchError((Object e, StackTrace st) {
          if (!_disposed) {
            _setFailed(messageId, e);
          }
        });
  }

  bool get hasPending {
    return _entries.values.any((e) => e.status == OutboundStatus.sending);
  }

  OutboundStatus statusFor(String messageId) {
    return _entries[messageId]?.status ?? OutboundStatus.sent;
  }

  void _setDelivered(String messageId) {
    _entries.remove(messageId);
    _order.remove(messageId);

    if (_lastSentEntry != null && _lastSentEntry?.messageId == messageId) {
      _lastSentEntry!.status = OutboundStatus.sent;
    }

    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setFailed(String messageId, Object error) {
    final e = _entries[messageId];

    if (e == null) return;

    e.status = OutboundStatus.failed;
    e.error = error;

    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _order.clear();
    _entries.clear();

    super.dispose();
  }
}
