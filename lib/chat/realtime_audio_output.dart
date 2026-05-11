import 'dart:typed_data';

import 'realtime_audio_output_stub.dart'
    if (dart.library.io) 'realtime_audio_output_native.dart'
    if (dart.library.js_interop) 'realtime_audio_output_web.dart'
    as impl;

abstract class RealtimeAudioOutput {
  Future<void> start({required int sampleRate, required int channels});

  Future<void> append(Uint8List pcm);

  Future<void> complete();

  Future<void> stop();

  Future<void> dispose();
}

RealtimeAudioOutput createRealtimeAudioOutput() => impl.createRealtimeAudioOutput();
