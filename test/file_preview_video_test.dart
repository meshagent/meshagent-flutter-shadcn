import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/file_preview/video.dart';

void main() {
  test('video preview allows native fullscreen by default', () {
    final preview = VideoPreview(url: Uri.parse('https://example.com/clip.mp4'), fit: BoxFit.contain);

    expect(preview.allowNativeFullscreen, isTrue);
  });

  test('video attachment exposes native fullscreen preference', () {
    const attachment = VideoAttachment(videoUrl: 'https://example.com/clip.mp4', allowNativeFullscreen: false);

    expect(attachment.allowNativeFullscreen, isFalse);
  });
}
