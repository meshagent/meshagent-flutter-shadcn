import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'realtime_audio_output.dart';

RealtimeAudioOutput createRealtimeAudioOutput() => _WebRealtimeAudioOutput();

class _WebRealtimeAudioOutput implements RealtimeAudioOutput {
  web.AudioContext? _context;
  final List<web.AudioBufferSourceNode> _nodes = <web.AudioBufferSourceNode>[];
  int _generation = 0;
  int _sampleRate = 24000;
  int _channels = 1;
  double _nextStartTime = 0;
  bool _started = false;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (_started && _sampleRate == sampleRate && _channels == channels) {
      return;
    }
    if (_started || _nodes.isNotEmpty) {
      await stop();
    }
    _sampleRate = sampleRate;
    _channels = channels;
    final context = _context ?? web.AudioContext();
    _context = context;
    unawaited(context.resume().toDart.catchError((_) => null));
    _nextStartTime = context.currentTime + 0.03;
    _started = true;
  }

  @override
  Future<void> append(Uint8List pcm) async {
    if (!_started || pcm.isEmpty || pcm.length % (_channels * 2) != 0) {
      return;
    }
    final context = _context;
    if (context == null) {
      return;
    }
    final frames = pcm.length ~/ (_channels * 2);
    if (frames == 0) {
      return;
    }
    final buffer = context.createBuffer(_channels, frames, _sampleRate);
    final data = ByteData.sublistView(pcm);
    if (_channels == 1) {
      buffer.copyToChannel(_pcm16MonoToFloat32(data, frames).toJS, 0);
    } else {
      for (var channel = 0; channel < _channels; channel++) {
        buffer.copyToChannel(_pcm16ChannelToFloat32(data: data, frames: frames, channels: _channels, channel: channel).toJS, channel);
      }
    }
    final source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    final startAt = _nextStartTime < context.currentTime ? context.currentTime : _nextStartTime;
    _nextStartTime = startAt + frames / _sampleRate;
    final generation = _generation;
    _nodes.add(source);
    source.onended = ((web.Event _) {
      _nodes.remove(source);
    }).toJS;
    try {
      source.start(startAt);
    } catch (_) {
      if (generation == _generation) {
        _nodes.remove(source);
      }
    }
  }

  @override
  Future<void> complete() async {
    _started = false;
  }

  @override
  Future<void> stop() async {
    _generation++;
    _started = false;
    _nextStartTime = _context?.currentTime ?? 0;
    final nodes = _nodes.toList(growable: false);
    _nodes.clear();
    for (final node in nodes) {
      try {
        node.stop();
      } catch (_) {}
      try {
        node.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    final context = _context;
    _context = null;
    if (context != null) {
      try {
        await context.close().toDart;
      } catch (_) {}
    }
  }
}

Float32List _pcm16MonoToFloat32(ByteData data, int frames) {
  final samples = Float32List(frames);
  for (var frame = 0; frame < frames; frame++) {
    samples[frame] = data.getInt16(frame * 2, Endian.little) / 32768;
  }
  return samples;
}

Float32List _pcm16ChannelToFloat32({required ByteData data, required int frames, required int channels, required int channel}) {
  final samples = Float32List(frames);
  final bytesPerFrame = channels * 2;
  for (var frame = 0; frame < frames; frame++) {
    samples[frame] = data.getInt16(frame * bytesPerFrame + channel * 2, Endian.little) / 32768;
  }
  return samples;
}
