import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

void main() {
  test('text-like previews load directly from room storage', () {
    expect(filePreviewLoadsFromRoomStorage('docs/empty.txt'), isTrue);
    expect(filePreviewLoadsFromRoomStorage('docs/readme.md'), isTrue);
    expect(filePreviewLoadsFromRoomStorage('docs/report.pdf'), isTrue);
  });

  test('url-backed previews still require download URLs', () {
    expect(filePreviewLoadsFromRoomStorage('images/photo.png'), isFalse);
    expect(filePreviewLoadsFromRoomStorage('audio/clip.mp3'), isFalse);
    expect(filePreviewLoadsFromRoomStorage('video/demo.mp4'), isFalse);
  });
}
