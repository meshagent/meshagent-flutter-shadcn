import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat_bot_view.dart';
import 'package:meshagent_flutter_shadcn/chat/conversation_descriptor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

class _FakeChatClient extends agent_sessions.BaseChatClient {
  final List<agent_sessions.AgentMessage> sentMessages = <agent_sessions.AgentMessage>[];

  @override
  Future<void> start() async {
    emitConnectionStatus(status: 'connected', message: 'Agent messaging connected');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment}) async {
    sentMessages.add(message);
    if (message is agent_sessions.OpenThread && message.load != false) {
      scheduleMicrotask(() {
        handleAgentMessage(
          agent_sessions.ThreadLoaded(threadId: message.threadId, sourceMessageId: message.messageId, sinceTurn: message.sinceTurn),
        );
      });
    }
  }
}

void main() {
  testWidgets('default-new ChatBotView loads selected threads through agent messages', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final chatClient = _FakeChatClient();
    addTearDown(room.dispose);

    const threadPath = 'agents/codex/threads/12345678-1234-5678-1234-567812345678.thread';

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: ChatBotView(
              room: room,
              chatClient: chatClient,
              agentName: 'codex',
              threadDisplayMode: chatThreadDisplayModeFromAnnotation('default-new'),
              selectedThreadPath: threadPath,
              showThreadList: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final openMessages = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().toList();
    expect(openMessages.map((message) => message.threadId), contains(threadPath));
    expect(openMessages.singleWhere((message) => message.threadId == threadPath).load, isTrue);
    expect(find.text('Unable to load thread'), findsNothing);
  });
}
