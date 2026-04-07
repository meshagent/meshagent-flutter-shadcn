import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/viewers/file.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

void main() {
  tearDown(() {
    customViewers.remove('thread');
  });

  test('classifyFile detects thread files explicitly', () {
    expect(classifyFile('agents/assistant/threads/main.thread'), FileKind.thread);
  });

  test('custom thread viewers do not override the built-in thread type', () {
    customViewers['thread'] = ({Key? key, required RoomClient room, required String filename, required Uri url}) {
      return const SizedBox.shrink();
    };

    expect(classifyFile('agents/assistant/threads/main.thread'), FileKind.thread);
  });

  test('fileViewer returns the thread viewer for thread files', () {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    final viewer = fileViewer(room, 'agents/assistant/threads/main.thread');
    expect(viewer, isA<ChatThreadLoader>());
  });
}
