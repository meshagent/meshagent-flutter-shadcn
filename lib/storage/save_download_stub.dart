Future<void> saveDownload(String name, Stream<List<int>> bytes) =>
    Future.error(UnsupportedError('Saving files is unavailable on this platform.'));
