import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
import 'package:meshagent_flutter_shadcn/chat/tool_call_rendering.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _FakeManagedAgentChatClient extends agent_sessions.BaseChatClient {
  _FakeManagedAgentChatClient() : super(deduplicateClientToolRequests: true);

  final List<agent_sessions.AgentMessage> sentMessages = <agent_sessions.AgentMessage>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment}) async {
    sentMessages.add(message);
  }

  void emit(agent_sessions.AgentMessage message) {
    handleAgentMessage(message);
  }
}

class _TestToolCallRenderer implements ChatToolCallRenderer {
  final List<ChatToolCallSnapshot> snapshots = <ChatToolCallSnapshot>[];

  @override
  Widget build(BuildContext context, ChatToolCallRenderContext renderContext) {
    final snapshot = renderContext.snapshot;
    snapshots.add(snapshot);
    return Text('custom:${snapshot.identity.callId}:${snapshot.tool}:${snapshot.status.name}', key: const Key('custom-tool-call'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('managed agent tool calls remain collapsed by default', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    addTearDown(chatClient.stop);
    final renderer = _TestToolCallRenderer();
    final registry = ChatToolCallRendererRegistry(
      renderers: <ChatToolCallRendererKey, ChatToolCallRenderer>{const ChatToolCallRendererKey(tool: 'deploy'): renderer},
    );

    await tester.pumpWidget(
      ShadApp(
        home: SizedBox(
          width: 900,
          height: 820,
          child: DatasetChatThread(
            chatClient: chatClient,
            path: 'thread-tools-collapsed',
            agentName: 'builder',
            toolCallRenderers: registry,
          ),
        ),
      ),
    );
    await tester.pump();
    final openThread = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().single;
    chatClient.emit(agent_sessions.ThreadLoaded(threadId: 'thread-tools-collapsed', sourceMessageId: openThread.messageId));
    await tester.pump();
    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: 'thread-tools-collapsed',
        turnId: 'turn-1',
        sourceMessageId: 'source-1',
        messageId: 'turn-started-1',
        senderName: 'builder',
      ),
    );
    chatClient.emit(
      agent_sessions.AgentToolCallStarted(
        threadId: 'thread-tools-collapsed',
        turnId: 'turn-1',
        itemId: 'item-1',
        callId: 'call-1',
        toolkit: 'builder',
        tool: 'deploy',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-tool-call')), findsNothing);
    expect(find.text('Working'), findsWidgets);

    await tester.tap(find.byType(ChatThreadMessageView).first);
    await tester.pump();

    expect(find.text('custom:call-1:deploy:running'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent thread expands matching tool calls when opted in', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);
    final renderer = _TestToolCallRenderer();
    final registry = ChatToolCallRendererRegistry(
      renderers: <ChatToolCallRendererKey, ChatToolCallRenderer>{const ChatToolCallRendererKey(tool: 'deploy'): renderer},
    );

    await tester.pumpWidget(
      ShadApp(
        home: SizedBox(
          width: 900,
          height: 820,
          child: DatasetChatThread(
            chatClient: chatClient,
            path: 'thread-tools',
            agentName: 'builder',
            toolCallRenderers: registry,
            initialShowCompletedToolCalls: true,
            onDebugRowsChanged: debugRows.add,
          ),
        ),
      ),
    );
    await tester.pump();
    final openThread = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().single;
    chatClient.emit(agent_sessions.ThreadLoaded(threadId: 'thread-tools', sourceMessageId: openThread.messageId));
    await tester.pump();
    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: 'thread-tools',
        turnId: 'turn-1',
        sourceMessageId: 'source-1',
        messageId: 'turn-started-1',
        senderName: 'builder',
      ),
    );
    await tester.pump();
    chatClient.emit(
      agent_sessions.AgentToolCallStarted(
        threadId: 'thread-tools',
        turnId: 'turn-1',
        itemId: 'item-1',
        callId: 'call-1',
        toolkit: 'builder',
        tool: 'deploy',
      ),
    );
    await tester.pump();
    chatClient.emit(
      agent_sessions.AgentToolCallLogDelta(
        threadId: 'thread-tools',
        turnId: 'turn-1',
        itemId: 'item-1',
        callId: 'call-1',
        lines: const <agent_sessions.AgentToolCallLogLine>[agent_sessions.AgentToolCallLogLine(source: 'stdout', text: 'deploying')],
      ),
    );
    await tester.pump();
    chatClient.emit(
      agent_sessions.AgentToolCallEnded(
        threadId: 'thread-tools',
        turnId: 'turn-1',
        itemId: 'item-1',
        callId: 'call-1',
        toolkit: 'builder',
        tool: 'deploy',
        result: TextContent(text: 'deployed'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(debugRows.last.map((row) => row.type), contains(agent_sessions.agentToolCallEndedType));
    expect(find.byKey(const Key('custom-tool-call')), findsOneWidget);
    expect(find.text('custom:call-1:deploy:succeeded'), findsOneWidget);
    expect(renderer.snapshots.last.logs.single.source, 'stdout');
    expect(renderer.snapshots.last.logs.single.text, 'deploying');
    expect(renderer.snapshots.last.result, isA<TextContent>());
    expect((renderer.snapshots.last.result! as TextContent).text, 'deployed');
    expect(renderer.snapshots.last.startedAt.isAfter(renderer.snapshots.last.updatedAt), isFalse);
    expect(find.byType(ChatThreadAuthorHeader), findsOneWidget);
    expect(tester.getSize(find.byType(ChatThreadAuthorHeader)).width, greaterThan(600));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('hidden tool calls are removed before detail-group layout', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    addTearDown(chatClient.stop);
    final renderer = _TestToolCallRenderer();
    final registry = ChatToolCallRendererRegistry(
      renderers: <ChatToolCallRendererKey, ChatToolCallRenderer>{const ChatToolCallRendererKey(tool: 'inspect'): renderer},
    );

    await tester.pumpWidget(
      ShadApp(
        home: SizedBox(
          width: 900,
          height: 820,
          child: DatasetChatThread(
            chatClient: chatClient,
            path: 'thread-hidden-tools',
            agentName: 'builder',
            toolCallRenderers: registry,
            toolCallVisibilityPredicate: (_) => false,
            initialShowCompletedToolCalls: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final openThread = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().single;
    chatClient.emit(agent_sessions.ThreadLoaded(threadId: 'thread-hidden-tools', sourceMessageId: openThread.messageId));
    await tester.pump();
    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: 'thread-hidden-tools',
        turnId: 'turn-1',
        sourceMessageId: 'source-1',
        messageId: 'turn-started-1',
        senderName: 'builder',
      ),
    );
    chatClient.emit(
      agent_sessions.AgentToolCallStarted(
        threadId: 'thread-hidden-tools',
        turnId: 'turn-1',
        itemId: 'item-1',
        callId: 'call-1',
        toolkit: 'builder',
        tool: 'inspect',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-tool-call')), findsNothing);
    expect(find.byType(ChatThreadMessageView), findsNothing);
    expect(renderer.snapshots, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
