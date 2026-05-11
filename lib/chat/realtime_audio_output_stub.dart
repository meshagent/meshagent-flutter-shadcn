import 'dart:typed_data';

import 'realtime_audio_output.dart';

RealtimeAudioOutput createRealtimeAudioOutput() => _NoopRealtimeAudioOutput();

class _NoopRealtimeAudioOutput implements RealtimeAudioOutput {
  @override
  Future<void> start({required int sampleRate, required int channels}) async {}

  @override
  Future<void> append(Uint8List pcm) async {}

  @override
  Future<void> complete() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
