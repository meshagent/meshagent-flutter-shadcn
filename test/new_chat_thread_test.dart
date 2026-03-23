import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/new_chat_thread.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

void main() {
  testWidgets('wraps the new thread composer in a file drop area', (tester) async {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: NewChatThread(
              room: room,
              agentName: 'assistant',
              builder: (context, threadPath, loadingBuilder) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ChatThreadInput), findsOneWidget);
    expect(find.byType(FileDropArea), findsOneWidget);
    expect(find.ancestor(of: find.byType(ChatThreadInput), matching: find.byType(FileDropArea)), findsOneWidget);
  });
}
