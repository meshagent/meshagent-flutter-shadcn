class AccumulatedTextStream {
  const AccumulatedTextStream({
    required this.itemId,
    this.turnId,
    this.status = 'in_progress',
    this.text = '',
    this.senderName,
    this.phase,
  });

  final String itemId;
  final String? turnId;
  final String status;
  final String text;
  final String? senderName;
  final String? phase;
}

String accumulateTextStreamDelta(String current, String delta) {
  if (delta.isEmpty) {
    return current;
  }
  if (current.isEmpty || delta.startsWith(current)) {
    return delta;
  }
  if (current.endsWith(delta)) {
    return current;
  }
  return '$current$delta';
}

class TextStreamAccumulator {
  final Map<String, AccumulatedTextStream> _items = <String, AccumulatedTextStream>{};

  AccumulatedTextStream upsert({required String itemId, String? turnId, String? senderName, String? phase}) {
    final normalizedItemId = itemId.trim();
    final current = _items[normalizedItemId];
    final next = AccumulatedTextStream(
      itemId: normalizedItemId,
      turnId: _coalesceText(turnId, current?.turnId),
      status: 'in_progress',
      text: current?.text ?? '',
      senderName: _coalesceText(senderName, current?.senderName),
      phase: _coalesceText(phase, current?.phase),
    );
    _items[normalizedItemId] = next;
    return next;
  }

  AccumulatedTextStream appendDelta({required String itemId, required String delta, String? turnId, String? senderName, String? phase}) {
    final current = upsert(itemId: itemId, turnId: turnId, senderName: senderName, phase: phase);
    final next = AccumulatedTextStream(
      itemId: current.itemId,
      turnId: current.turnId,
      status: 'in_progress',
      text: accumulateTextStreamDelta(current.text, delta),
      senderName: current.senderName,
      phase: current.phase,
    );
    _items[current.itemId] = next;
    return next;
  }

  AccumulatedTextStream? operator [](String itemId) => _items[itemId.trim()];

  AccumulatedTextStream? complete(String itemId, {String status = 'completed'}) {
    final current = _items[itemId.trim()];
    if (current == null) {
      return null;
    }
    final next = AccumulatedTextStream(
      itemId: current.itemId,
      turnId: current.turnId,
      status: status,
      text: current.text,
      senderName: current.senderName,
      phase: current.phase,
    );
    _items[current.itemId] = next;
    return next;
  }

  AccumulatedTextStream? remove(String itemId) => _items.remove(itemId.trim());

  void clear() => _items.clear();
}

class AccumulatedFileStream {
  const AccumulatedFileStream({
    required this.itemId,
    this.turnId,
    this.status = 'in_progress',
    this.urls = const <String>[],
    this.senderName,
  });

  final String itemId;
  final String? turnId;
  final String status;
  final List<String> urls;
  final String? senderName;

  String? get latestUrl => urls.isEmpty ? null : urls.last;
}

class FileStreamAccumulator {
  final Map<String, AccumulatedFileStream> _items = <String, AccumulatedFileStream>{};

  AccumulatedFileStream upsert({required String itemId, String? turnId, String? senderName}) {
    final normalizedItemId = itemId.trim();
    final current = _items[normalizedItemId];
    final next = AccumulatedFileStream(
      itemId: normalizedItemId,
      turnId: _coalesceText(turnId, current?.turnId),
      status: 'in_progress',
      urls: List<String>.unmodifiable(current?.urls ?? const <String>[]),
      senderName: _coalesceText(senderName, current?.senderName),
    );
    _items[normalizedItemId] = next;
    return next;
  }

  AccumulatedFileStream appendUrl({required String itemId, required String url, String? turnId, String? senderName}) {
    final current = upsert(itemId: itemId, turnId: turnId, senderName: senderName);
    final normalizedUrl = url.trim();
    final urls = current.urls.toList(growable: true);
    if (normalizedUrl.isNotEmpty && !urls.contains(normalizedUrl)) {
      urls.add(normalizedUrl);
    }
    final next = AccumulatedFileStream(
      itemId: current.itemId,
      turnId: current.turnId,
      status: 'in_progress',
      urls: List<String>.unmodifiable(urls),
      senderName: current.senderName,
    );
    _items[current.itemId] = next;
    return next;
  }

  AccumulatedFileStream? operator [](String itemId) => _items[itemId.trim()];

  AccumulatedFileStream? complete(String itemId, {String status = 'completed'}) {
    final current = _items[itemId.trim()];
    if (current == null) {
      return null;
    }
    final next = AccumulatedFileStream(
      itemId: current.itemId,
      turnId: current.turnId,
      status: status,
      urls: current.urls,
      senderName: current.senderName,
    );
    _items[current.itemId] = next;
    return next;
  }

  AccumulatedFileStream? remove(String itemId) => _items.remove(itemId.trim());

  void clear() => _items.clear();
}

String? _coalesceText(String? value, String? fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}
