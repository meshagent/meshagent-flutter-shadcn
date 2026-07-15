import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat_bot_view.dart';
import 'package:meshagent_flutter_shadcn/chat/conversation_descriptor.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
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
    if (message is agent_sessions.ModelsRequest) {
      scheduleMicrotask(() {
        handleAgentMessage(
          agent_sessions.ModelsResponse(
            sourceMessageId: message.messageId,
            providers: const <agent_sessions.AgentProviderInfo>[
              agent_sessions.AgentProviderInfo(
                name: 'openai',
                friendlyName: 'OpenAI',
                defaultModel: 'gpt-5.6-sol',
                models: <agent_sessions.AgentModelInfo>[
                  agent_sessions.AgentModelInfo(name: 'gpt-5.6-sol', active: true),
                  agent_sessions.AgentModelInfo(name: 'gpt-5.5'),
                ],
              ),
              agent_sessions.AgentProviderInfo(
                name: 'anthropic',
                friendlyName: 'Anthropic',
                defaultModel: 'claude',
                models: <agent_sessions.AgentModelInfo>[agent_sessions.AgentModelInfo(name: 'claude')],
              ),
            ],
          ),
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

  testWidgets('selected threads refresh the current assistant model catalog', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final chatClient = _FakeChatClient();
    addTearDown(room.dispose);

    const threadPath = 'dataset://agents/codex/threads/12345678-1234-5678-1234-567812345678.thread';
    chatClient.openThread(threadPath);
    await tester.pump();
    final initialRequestCount = chatClient.sentMessages.whereType<agent_sessions.ModelsRequest>().length;
    expect(initialRequestCount, greaterThan(0));

    DatasetChatModelController? modelController;
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
              datasetThreadWrapperBuilder: (context, path, thread, controller) {
                modelController = controller;
                return thread;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(chatClient.sentMessages.whereType<agent_sessions.ModelsRequest>().length, greaterThan(initialRequestCount));
    expect(
      modelController?.models.map((model) => model.key),
      containsAll(<String>['/openai/gpt-5.6-sol', '/openai/gpt-5.5', '/anthropic/claude']),
    );
  });
}
