const String transcriptFileExtension = '.transcript';

final RegExp _legacyTranscriptFileNamePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?\.transcript$');

String buildTranscriptFileName({DateTime? timestamp}) {
  final value = (timestamp ?? DateTime.now()).toLocal();
  final hourOfPeriod = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';

  return '${_formatDate(value)} $hourOfPeriod-$minute $meridiem$transcriptFileExtension';
}

String formatTranscriptFileNameForDisplay(String fileName) {
  final parsed = parseLegacyTranscriptFileName(fileName);
  if (parsed == null) {
    return fileName;
  }
  return buildTranscriptFileName(timestamp: parsed);
}

DateTime? parseLegacyTranscriptFileName(String fileName) {
  final match = _legacyTranscriptFileNamePattern.firstMatch(fileName);
  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6) ?? '0');

  return DateTime(year, month, day, hour, minute, second);
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
