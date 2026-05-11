import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class RealtimeConnectionInfo {
  const RealtimeConnectionInfo({required this.protocol, required this.url, this.headers = const <String, String>{}, this.webOnlyProtocol});

  final String protocol;
  final String url;
  final Map<String, String> headers;
  final String? webOnlyProtocol;

  static RealtimeConnectionInfo? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final protocol = value['protocol']?.toString().trim();
    final url = value['url']?.toString().trim();
    if (protocol == null || protocol.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    final rawHeaders = value['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key?.toString().trim();
        final headerValue = entry.value?.toString();
        if (key != null && key.isNotEmpty && headerValue != null) {
          headers[key] = headerValue;
        }
      }
    }
    return RealtimeConnectionInfo(protocol: protocol, url: url, headers: headers, webOnlyProtocol: value['web_only_protocol']?.toString());
  }
}

class RealtimeWebrtcSession {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _eventsChannel;
  MediaStream? _localStream;
  Future<void>? _startFuture;
  bool _stopRequested = false;

  bool get isStarted => _peerConnection != null;

  Future<void> start(RealtimeConnectionInfo connection) async {
    if (isStarted) {
      return;
    }
    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }
    if (connection.protocol != 'webrtc') {
      throw StateError('Realtime connection is not WebRTC.');
    }

    final startFuture = _start(connection);
    _startFuture = startFuture;
    try {
      await startFuture;
    } finally {
      if (_startFuture == startFuture) {
        _startFuture = null;
      }
    }
  }

  Future<void> _start(RealtimeConnectionInfo connection) async {
    _stopRequested = false;
    final localStream = await navigator.mediaDevices.getUserMedia(const <String, Object>{'audio': true, 'video': false});
    if (_stopRequested) {
      await _disposeResources(localStream: localStream);
      return;
    }
    _localStream = localStream;

    final peerConnection = await createPeerConnection(const <String, Object>{});
    if (_stopRequested) {
      await _disposeResources(peerConnection: peerConnection, localStream: localStream);
      return;
    }
    _peerConnection = peerConnection;

    final eventsChannel = await peerConnection.createDataChannel('oai-events', RTCDataChannelInit()..ordered = true);
    if (_stopRequested) {
      await _disposeResources(eventsChannel: eventsChannel, peerConnection: peerConnection, localStream: localStream);
      return;
    }
    _eventsChannel = eventsChannel;

    for (final track in localStream.getAudioTracks()) {
      await peerConnection.addTrack(track, localStream);
      if (_stopRequested) {
        await stop();
        return;
      }
    }

    final offer = await peerConnection.createOffer();
    if (_stopRequested) {
      await stop();
      return;
    }
    await peerConnection.setLocalDescription(offer);
    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty) {
      await stop();
      throw StateError('Unable to create WebRTC offer.');
    }

    final headers = <String, String>{...connection.headers, 'Content-Type': 'application/sdp'};
    final response = await http.post(Uri.parse(connection.url), headers: headers, body: sdp);
    if (_stopRequested) {
      await stop();
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await stop();
      throw StateError('Realtime WebRTC offer failed: ${response.statusCode} ${response.body}');
    }
    await peerConnection.setRemoteDescription(RTCSessionDescription(response.body, 'answer'));
    if (_stopRequested) {
      await stop();
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    final eventsChannel = _eventsChannel;
    final peerConnection = _peerConnection;
    final localStream = _localStream;
    _eventsChannel = null;
    _peerConnection = null;
    _localStream = null;
    await _disposeResources(eventsChannel: eventsChannel, peerConnection: peerConnection, localStream: localStream);
  }

  Future<void> _disposeResources({RTCDataChannel? eventsChannel, RTCPeerConnection? peerConnection, MediaStream? localStream}) async {
    try {
      await eventsChannel?.close();
    } catch (_) {}
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await localStream.dispose();
      } catch (_) {}
    }
    try {
      await peerConnection?.close();
    } catch (_) {}
  }
}
