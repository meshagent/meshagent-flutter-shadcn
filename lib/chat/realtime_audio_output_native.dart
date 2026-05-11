import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'realtime_audio_output.dart';

RealtimeAudioOutput createRealtimeAudioOutput() => _NativeRealtimeAudioOutput();

class _NativeRealtimeAudioOutput implements RealtimeAudioOutput {
  AudioSource? _source;
  SoundHandle? _handle;
  bool _initialized = false;
  bool _started = false;
  bool _playing = false;
  int _sampleRate = 24000;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (_started && _sampleRate == sampleRate) {
      return;
    }
    if (_started || _source != null) {
      await stop();
    }
    _sampleRate = sampleRate;
    if (!_initialized) {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init(sampleRate: sampleRate, channels: channels == 1 ? Channels.mono : Channels.stereo);
      }
      _initialized = true;
    }
    _source = SoLoud.instance.setBufferStream(
      maxBufferSizeDuration: const Duration(seconds: 120),
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.25,
      sampleRate: sampleRate,
      channels: channels == 1 ? Channels.mono : Channels.stereo,
      format: BufferType.s16le,
    );
    _handle = null;
    _started = true;
    _playing = false;
  }

  @override
  Future<void> append(Uint8List pcm) async {
    if (!_started || pcm.isEmpty) {
      return;
    }
    final source = _source;
    if (source == null) {
      return;
    }
    SoLoud.instance.addAudioDataStream(source, pcm);
    if (!_playing) {
      _handle = SoLoud.instance.play(source);
      _playing = true;
    }
  }

  @override
  Future<void> complete() async {
    _started = false;
    _playing = false;
    final source = _source;
    if (source == null) {
      return;
    }
    try {
      SoLoud.instance.setDataIsEnded(source);
    } catch (_) {}
    unawaited(
      Future<void>.delayed(const Duration(seconds: 30)).then((_) async {
        if (_source == source) {
          _source = null;
          _handle = null;
        }
        try {
          await SoLoud.instance.disposeSource(source);
        } catch (_) {}
      }),
    );
  }

  @override
  Future<void> stop() async {
    _started = false;
    _playing = false;
    final source = _source;
    final handle = _handle;
    _source = null;
    _handle = null;
    if (source == null) {
      return;
    }
    if (handle != null) {
      try {
        await SoLoud.instance.stop(handle);
      } catch (_) {}
    }
    try {
      SoLoud.instance.setDataIsEnded(source);
    } catch (_) {}
    try {
      await SoLoud.instance.disposeSource(source);
    } catch (_) {}
  }

  @override
  Future<void> dispose() => stop();
}
