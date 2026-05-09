import 'dart:convert';

class ToolCallStatusSnapshot {
  const ToolCallStatusSnapshot({
    required this.itemId,
    this.status = 'in_progress',
    this.text,
    this.totalBytes,
    this.linesAdded,
    this.linesRemoved,
  });

  final String itemId;
  final String status;
  final String? text;
  final int? totalBytes;
  final int? linesAdded;
  final int? linesRemoved;
}

class AccumulatedLiveToolCall {
  AccumulatedLiveToolCall();

  String? tool;
  Map<String, dynamic>? arguments;
  String status = 'in_progress';
  int argumentBytes = 0;
  String argumentText = "";
}

class LiveToolCallAccumulator {
  final Map<String, AccumulatedLiveToolCall> _callsByItemId = <String, AccumulatedLiveToolCall>{};

  bool get isEmpty => _callsByItemId.isEmpty;

  bool hasSingleItem(String itemId) => _callsByItemId.length == 1 && _callsByItemId.containsKey(itemId);

  AccumulatedLiveToolCall? operator [](String itemId) => _callsByItemId[itemId];

  int? totalBytes(String? itemId) {
    if (itemId == null || itemId.trim().isEmpty) {
      return null;
    }
    final bytes = _callsByItemId[itemId.trim()]?.argumentBytes;
    return bytes != null && bytes > 0 ? bytes : null;
  }

  ToolCallStatusSnapshot appendDelta({required String itemId, required String delta, String? fallbackText}) {
    final normalizedItemId = itemId.trim();
    final call = _callsByItemId.putIfAbsent(normalizedItemId, () => AccumulatedLiveToolCall());
    call.status = 'in_progress';
    call.argumentBytes += utf8.encode(delta).length;
    call.argumentText = "${call.argumentText}$delta";
    return _snapshotFor(itemId: normalizedItemId, call: call, fallbackText: fallbackText);
  }

  ToolCallStatusSnapshot upsert({
    required String itemId,
    required String tool,
    required Map<String, dynamic>? arguments,
    String? fallbackText,
  }) {
    final normalizedItemId = itemId.trim();
    final call = _callsByItemId.putIfAbsent(normalizedItemId, () => AccumulatedLiveToolCall());
    call.status = 'in_progress';
    final normalizedTool = tool.trim();
    if (normalizedTool.isNotEmpty) {
      call.tool = normalizedTool;
    }
    if (arguments != null) {
      call.arguments = arguments;
    }
    return _snapshotFor(itemId: normalizedItemId, call: call, fallbackText: fallbackText);
  }

  ToolCallStatusSnapshot? complete({required String itemId, String status = 'completed', String? fallbackText}) {
    final normalizedItemId = itemId.trim();
    final call = _callsByItemId[normalizedItemId];
    if (call == null) {
      return null;
    }
    call.status = status;
    return _snapshotFor(itemId: normalizedItemId, call: call, fallbackText: fallbackText);
  }

  bool remove(String itemId) => _callsByItemId.remove(itemId) != null;

  ToolCallStatusSnapshot _snapshotFor({required String itemId, required AccumulatedLiveToolCall call, required String? fallbackText}) {
    final isApplyPatch = call.tool?.trim().toLowerCase() == "apply_patch";
    final patchInfo = _patchStatusInfo(call);
    final path = patchInfo?.path;
    final patchText = patchInfo == null && !isApplyPatch
        ? null
        : path == null
        ? switch (call.status) {
            'completed' => 'Applied patch',
            'failed' => 'Attempted to patch',
            'cancelled' => 'Patch cancelled',
            _ => 'Applying patch',
          }
        : switch (call.status) {
            'completed' => 'Edited $path',
            'failed' => 'Attempted to patch $path',
            'cancelled' => 'Patch cancelled: $path',
            _ => 'Editing $path',
          };
    final text = patchText ?? fallbackText;
    return ToolCallStatusSnapshot(
      itemId: itemId,
      status: call.status,
      text: text,
      totalBytes: call.argumentBytes > 0 ? call.argumentBytes : null,
      linesAdded: patchInfo?.counts?.added,
      linesRemoved: patchInfo?.counts?.removed,
    );
  }

  ApplyPatchStatusInfo? _patchStatusInfo(AccumulatedLiveToolCall call) {
    final tool = call.tool?.trim().toLowerCase();
    final deltaText = call.argumentText.trim().isEmpty ? null : call.argumentText;
    final looksLikePatch =
        tool == "apply_patch" || (deltaText != null && (deltaText.contains("*** Begin Patch") || deltaText.contains("@@")));
    if (!looksLikePatch) {
      return null;
    }
    return applyPatchStatusInfo(arguments: call.arguments, deltaText: deltaText);
  }
}

class PatchLineCounts {
  const PatchLineCounts({required this.added, required this.removed});

  final int added;
  final int removed;
}

class ApplyPatchStatusInfo {
  const ApplyPatchStatusInfo({this.path, this.counts});

  final String? path;
  final PatchLineCounts? counts;
}

String? applyPatchTextFromArguments(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }
  if (value is Map) {
    for (final key in const <String>["patch", "input", "diff"]) {
      final text = applyPatchTextFromArguments(value[key]);
      if (text != null) {
        return text;
      }
    }
    for (final nested in value.values) {
      final text = applyPatchTextFromArguments(nested);
      if (text != null) {
        return text;
      }
    }
  }
  if (value is Iterable) {
    for (final nested in value) {
      final text = applyPatchTextFromArguments(nested);
      if (text != null) {
        return text;
      }
    }
  }
  return null;
}

String? applyPatchPathFromArguments(Object? value) {
  if (value is Map) {
    final path = value["path"];
    if (path is String && path.trim().isNotEmpty) {
      return path.trim();
    }
    final operationPath = applyPatchPathFromArguments(value["operation"]);
    if (operationPath != null) {
      return operationPath;
    }
    for (final nested in value.values) {
      final nestedPath = applyPatchPathFromArguments(nested);
      if (nestedPath != null) {
        return nestedPath;
      }
    }
  }
  if (value is Iterable) {
    for (final nested in value) {
      final nestedPath = applyPatchPathFromArguments(nested);
      if (nestedPath != null) {
        return nestedPath;
      }
    }
  }
  return null;
}

String? applyPatchPathFromText(String patch) {
  final filePattern = RegExp(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$");
  final diffPattern = RegExp(r"^(?:\+\+\+ b/|--- a/)(.+)$");
  for (final line in patch.replaceAll("\r\n", "\n").split("\n")) {
    final path = filePattern.firstMatch(line)?.group(1)?.trim() ?? diffPattern.firstMatch(line)?.group(1)?.trim();
    if (path != null && path.isNotEmpty) {
      return path;
    }
  }
  return null;
}

PatchLineCounts? diffLineCountsFromText(String diff) {
  var added = 0;
  var removed = 0;
  for (final line in diff.replaceAll("\r\n", "\n").split("\n")) {
    if (line.startsWith("+") && !line.startsWith("+++")) {
      added++;
    } else if (line.startsWith("-") && !line.startsWith("---")) {
      removed++;
    }
  }
  return added == 0 && removed == 0 ? null : PatchLineCounts(added: added, removed: removed);
}

PatchLineCounts? applyPatchLineCountsFromText(String patch) {
  final normalized = patch.replaceAll("\r\n", "\n");
  final looksLikePatch =
      normalized.contains("*** Begin Patch") ||
      normalized.contains("*** Update File:") ||
      normalized.contains("*** Add File:") ||
      normalized.contains("*** Delete File:");
  if (!looksLikePatch && !normalized.contains("@@")) {
    return null;
  }
  return diffLineCountsFromText(normalized);
}

ApplyPatchStatusInfo? applyPatchStatusInfo({Object? arguments, String? deltaText}) {
  final path = applyPatchPathFromArguments(arguments);
  final argumentText = applyPatchTextFromArguments(arguments);
  final text = deltaText != null && deltaText.trim().isNotEmpty ? deltaText : argumentText;
  final counts = text == null ? null : applyPatchLineCountsFromText(text);
  final patchPath = text == null ? null : applyPatchPathFromText(text);
  final resolvedPath = path ?? patchPath;
  if (resolvedPath == null && counts == null) {
    return null;
  }
  return ApplyPatchStatusInfo(path: resolvedPath, counts: counts);
}
