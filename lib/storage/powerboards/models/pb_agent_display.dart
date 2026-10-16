String pbDisplayAgentName(String rawName) {
  final normalized = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return rawName.trim();
  }

  return normalized
      .split(' ')
      .map((word) {
        if (word.isEmpty) {
          return word;
        }
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');
}
