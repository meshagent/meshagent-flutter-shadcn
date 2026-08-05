import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';

void main() {
  test('reuses an in-flight attachment image load', () async {
    final cache = ThreadAttachmentImageCache();
    var loadCount = 0;

    Future<ThreadAttachmentImageData?> load() async {
      loadCount += 1;
      await Future<void>.delayed(Duration.zero);
      return ThreadAttachmentImageData(data: Uint8List.fromList(<int>[1, 2, 3]), mimeType: 'image/png');
    }

    final first = cache.load(imageId: 'image-1', loader: load);
    final second = cache.load(imageId: 'image-1', loader: load);

    expect(identical(first, second), isTrue);
    expect((await first)?.data, <int>[1, 2, 3]);
    expect(loadCount, 1);
    expect(cache.read(imageId: 'image-1')?.mimeType, 'image/png');
  });

  test('evicts least-recently-used images over the byte limit', () {
    final cache = ThreadAttachmentImageCache(maximumBytes: 4);

    cache.write(imageId: 'first', data: Uint8List.fromList(<int>[1, 2]), mimeType: 'image/png');
    cache.write(imageId: 'second', data: Uint8List.fromList(<int>[3, 4]), mimeType: 'image/png');
    cache.read(imageId: 'first');
    cache.write(imageId: 'third', data: Uint8List.fromList(<int>[5, 6]), mimeType: 'image/png');

    expect(cache.read(imageId: 'first'), isNotNull);
    expect(cache.read(imageId: 'second'), isNull);
    expect(cache.read(imageId: 'third'), isNotNull);
  });
}
