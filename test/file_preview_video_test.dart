import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:meshagent_flutter_shadcn/file_preview/video.dart';

class FakePlayer extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final played = <int>[];
  final urls = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final id = streams.length;
    streams[id] = StreamController<VideoEvent>.broadcast();
    urls.add(options.dataSource.uri!);
    return id;
  }

  void initialize(int id) =>
      streams[id]!.add(VideoEvent(eventType: VideoEventType.initialized, size: const Size(320, 240), duration: const Duration(seconds: 2)));
  void fail(int id) => streams[id]!.addError(PlatformException(code: 'VideoError', message: 'Test failure'));
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Widget buildView(int playerId) => const SizedBox();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

Widget app({String url = 'https://example.com/clip.mp4', bool autoPlay = false}) => MaterialApp(
  home: Scaffold(
    body: VideoAttachment(videoUrl: url, autoPlay: autoPlay),
  ),
);

void main() {
  test('video preview allows native fullscreen by default', () {
    final preview = VideoPreview(url: Uri.parse('https://example.com/clip.mp4'), fit: BoxFit.contain);

    expect(preview.allowNativeFullscreen, isTrue);
  });

  test('video attachment exposes native fullscreen preference', () {
    const attachment = VideoAttachment(videoUrl: 'https://example.com/clip.mp4', allowNativeFullscreen: false);

    expect(attachment.allowNativeFullscreen, isFalse);
  });

  late FakePlayer player;
  late VideoPlayerPlatform previousPlatform;
  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    player = FakePlayer();
    VideoPlayerPlatform.instance = player;
  });
  tearDown(() async {
    VideoPlayerPlatform.instance = previousPlatform;
    for (final stream in player.streams.values) {
      await stream.close();
    }
  });

  testWidgets('error UI works in a ShadApp without a Material scaffold', (tester) async {
    await tester.pumpWidget(
      const ShadApp(
        home: Center(
          child: SizedBox(width: 320, child: VideoAttachment(videoUrl: 'https://example.com/clip.mp4')),
        ),
      ),
    );
    player.fail(0);
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });

  testWidgets('failed initialization stops and offers an explicit retry', (tester) async {
    await tester.pumpWidget(app());
    player.fail(0);
    await tester.pump();
    expect(find.text('Unable to play video.'), findsOneWidget);
    expect(player.streams.length, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(player.streams.length, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(player.streams.length, 2);
    // Native controller disposal completes outside the widget-test fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, contains(0));
    player.initialize(1);
    await tester.pump();
    expect(find.text('Unable to play video.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // Native controller disposal completes outside the widget-test fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, contains(1));
  });

  testWidgets('playback errors also stop without silently recreating the player', (tester) async {
    await tester.pumpWidget(app(autoPlay: true));
    player.initialize(0);
    await tester.pump();
    expect(player.played, [0]);
    player.fail(0);
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(player.streams.length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, [0]);
  });

  testWidgets('URL change ignores stale initialization and disposes the old player', (tester) async {
    await tester.pumpWidget(app(autoPlay: true));
    await tester.pumpWidget(app(url: 'https://example.com/new.mp4', autoPlay: true));
    expect(player.streams.length, 2);
    expect(player.urls, ['https://example.com/clip.mp4', 'https://example.com/new.mp4']);
    player.initialize(0);
    await tester.pump();
    expect(player.played, isEmpty);
    player.initialize(1);
    await tester.pump();
    expect(player.played, [1]);
    // Native controller disposal completes outside the widget-test fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, contains(0));
    await tester.pumpWidget(const SizedBox());
    // Native controller disposal completes outside the widget-test fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, contains(1));
  });

  testWidgets('failure from a replaced URL cannot fail the current player', (tester) async {
    await tester.pumpWidget(app(autoPlay: true));
    await tester.pumpWidget(app(url: 'https://example.com/new.mp4', autoPlay: true));
    player.fail(0);
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
    player.initialize(1);
    await tester.pump();
    expect(player.played, [1]);
    expect(find.byType(Chewie), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, containsAll([0, 1]));
  });

  testWidgets('successful playback preserves preview and position callbacks', (tester) async {
    final started = <Duration>[];
    final positions = <Duration>[];
    var paused = 0;
    var stopped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoAttachment(
            videoUrl: 'https://example.com/clip.mp4',
            autoPlay: true,
            onPreviewStarted: started.add,
            onPositionChanged: positions.add,
            onPreviewPaused: () => paused++,
            onPreviewStopped: () => stopped++,
          ),
        ),
      ),
    );
    player.initialize(0);
    await tester.pump();
    // Existing callers receive the video's duration when a preview starts.
    expect(started, [const Duration(seconds: 2)]);
    final controller = tester.widget<Chewie>(find.byType(Chewie)).controller.videoPlayerController;
    await controller.seekTo(const Duration(milliseconds: 500));
    await tester.pump();
    expect(positions.last, const Duration(milliseconds: 500));
    await controller.pause();
    await tester.pump();
    expect(paused, 1);
    await controller.play();
    await tester.pump();
    expect(started, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(stopped, 1);
    expect(player.disposed, [0]);
  });

  testWidgets('disposing during initialization never starts late playback', (tester) async {
    await tester.pumpWidget(app(autoPlay: true));
    await tester.pumpWidget(const SizedBox());
    player.initialize(0);
    await tester.pump();
    expect(player.played, isEmpty);
    // Native controller disposal completes outside the widget-test fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, [0]);
  });
}
