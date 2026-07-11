import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _liveStatusFlushDelay = Duration(milliseconds: 150);

class _FakeChatClient extends agent_sessions.BaseChatClient {
  _FakeChatClient({this.completeOpenThread = true});

  final bool completeOpenThread;
  final List<agent_sessions.AgentMessage> sentMessages = <agent_sessions.AgentMessage>[];

  @override
  Future<void> start() async {
    emitConnectionStatus(status: 'connected', message: 'Chat websocket connected');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment}) async {
    sentMessages.add(message);
    if (completeOpenThread && message is agent_sessions.OpenThread && message.load != false) {
      scheduleMicrotask(() {
        handleAgentMessage(
          agent_sessions.ThreadLoaded(threadId: message.threadId, sourceMessageId: message.messageId, sinceTurn: message.sinceTurn),
        );
      });
    }
  }

  void emit(agent_sessions.AgentMessage message) {
    handleAgentMessage(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('renders streamed dataset rows before the rows stream closes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    addTearDown(rowsController.close);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: 'dataset://agents/assistant/threads/thread-1',
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Done from streaming rows'), findsNothing);

    rowsController.add([
      {
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'timestamp': '2026-06-23T19:35:00Z',
        'data': {'kind': 'message', 'role': 'assistant', 'text': 'Done from streaming rows', 'sender_name': 'Assistant'},
      },
    ]);

    await tester.pump();
    await tester.pump();

    expect(find.text('Done from streaming rows'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('keeps cached thread rows visible while the thread session reconnects', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient(completeOpenThread: false);
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: 'dataset://agents/assistant/threads/thread-1',
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    rowsController.add([
      {
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'timestamp': '2026-06-23T19:35:00Z',
        'data': {'kind': 'message', 'role': 'assistant', 'text': 'Cached website creation result', 'sender_name': 'Assistant'},
      },
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Cached website creation result'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('renders a provided webserver file tool result as a clickable attachment', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient();
    final openedPaths = <String>[];
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: 'dataset://agents/assistant/threads/thread-1',
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
              openFile: openedPaths.add,
              attachmentRenderer: (context, path) => Text('attachment:$path'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    rowsController.add(const []);
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentToolCallStarted(
        threadId: 'dataset://agents/assistant/threads/thread-1',
        turnId: 'turn-1',
        itemId: 'tool-1',
        toolkit: 'powerboards',
        tool: 'open_webserver_file',
      ),
    );
    await tester.pump();
    chatClient.emit(
      agent_sessions.AgentToolCallEnded(
        threadId: 'dataset://agents/assistant/threads/thread-1',
        turnId: 'turn-1',
        itemId: 'tool-1',
        result: LinkContent(url: 'room:///website/index.html', name: 'index.html'),
      ),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);

    expect(find.text('attachment:website/index.html'), findsOneWidget);
    await tester.tap(find.text('attachment:website/index.html'));
    await tester.pump();
    expect(openedPaths, ['website/index.html']);

    rowsController.add([
      {
        'item_id': 'tool-2',
        'turn_id': 'turn-2',
        'timestamp': '2026-06-23T19:36:00Z',
        'data': {
          'type': agent_sessions.agentToolCallEndedType,
          'thread_id': 'dataset://agents/assistant/threads/thread-1',
          'turn_id': 'turn-2',
          'item_id': 'tool-2',
          'result': {'type': 'link', 'url': 'room:///website/styles.css', 'name': 'styles.css'},
        },
      },
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('attachment:website/styles.css'), findsOneWidget);
    await tester.tap(find.text('attachment:website/styles.css'));
    await tester.pump();
    expect(openedPaths, ['website/index.html', 'website/styles.css']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('clears stale live status when persisted rows contain the terminal turn event', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const threadPath = 'dataset://agents/assistant/threads/thread-1';
    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient();
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: threadPath,
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/website/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);
    expect(find.text('Preparing to write /data/website/index.html'), findsOneWidget);

    rowsController.add([
      {
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-06-23T19:35:00Z',
        'data': {'kind': 'message', 'role': 'assistant', 'text': 'Done from persisted rows', 'sender_name': 'Assistant'},
      },
      {
        'item_id': 'turn-ended-1',
        'turn_id': 'turn-1',
        'sequence': 2,
        'timestamp': '2026-06-23T19:35:01Z',
        'data': {'type': agent_sessions.agentTurnEndedType, 'thread_id': threadPath, 'turn_id': 'turn-1'},
      },
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Done from persisted rows'), findsOneWidget);
    expect(find.text('Preparing to write /data/website/index.html'), findsNothing);

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/website/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    await tester.pump();

    expect(find.text('Done from persisted rows'), findsOneWidget);
    expect(find.text('Preparing to write /data/website/index.html'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('clears stale live status when persisted final rows arrive without terminal event', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const threadPath = 'dataset://agents/assistant/threads/thread-1';
    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient();
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: threadPath,
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/website/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);
    expect(find.text('Preparing to write /data/website/index.html'), findsOneWidget);

    rowsController.add([
      {
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-06-23T19:35:00Z',
        'data': {'kind': 'message', 'role': 'assistant', 'status': 'completed', 'text': 'Done from persisted rows'},
      },
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Done from persisted rows'), findsOneWidget);
    expect(find.text('Preparing to write /data/website/index.html'), findsNothing);

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/website/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    await tester.pump();

    expect(find.text('Done from persisted rows'), findsOneWidget);
    expect(find.text('Preparing to write /data/website/index.html'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('locks same-thread input while a turn is active', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const threadPath = 'dataset://agents/assistant/threads/thread-1';
    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient();
    final capturedConfigs = <ChatThreadInputConfig>[];
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: threadPath,
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
              customInputBuilder: (context, config, defaultInput) {
                capturedConfigs.add(config);
                return defaultInput;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(capturedConfigs.last.readOnly, isFalse);
    expect(capturedConfigs.last.sendEnabled, isTrue);

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/webserver/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);

    expect(capturedConfigs.last.readOnly, isTrue);
    expect(capturedConfigs.last.sendEnabled, isFalse);
    expect(capturedConfigs.last.sendDisabledReason, contains('Assistant is still working'));
    expect(tester.widget<EditableText>(find.byType(EditableText)).readOnly, isTrue);
    await expectLater(capturedConfigs.last.onSend('second request', const []), throwsA(isA<StateError>()));

    rowsController.add([
      {
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-06-23T19:35:00Z',
        'data': {'kind': 'message', 'role': 'assistant', 'status': 'completed', 'text': 'Done from persisted rows'},
      },
    ]);
    await tester.pump();
    await tester.pump();

    expect(capturedConfigs.last.readOnly, isFalse);
    expect(capturedConfigs.last.sendEnabled, isTrue);
    expect(tester.widget<EditableText>(find.byType(EditableText)).readOnly, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('does not render live tool argument deltas during an active turn', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const threadPath = 'dataset://agents/assistant/threads/thread-1';
    final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
    final chatClient = _FakeChatClient();
    final debugRowsSnapshots = <List<DatasetChatDebugRow>>[];
    addTearDown(rowsController.close);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              path: threadPath,
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => rowsController.stream,
              onDebugRowsChanged: debugRowsSnapshots.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentThreadStatus(
        threadId: threadPath,
        status: 'Preparing to write /data/webserver/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
      ),
    );
    chatClient.emit(
      agent_sessions.AgentToolCallPending(threadId: threadPath, turnId: 'turn-1', itemId: 'tool-1', toolkit: 'openai', tool: 'shell'),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);

    final rowsBeforeDelta = debugRowsSnapshots.lastOrNull ?? const <DatasetChatDebugRow>[];
    chatClient.emit(
      agent_sessions.AgentToolCallArgumentsDelta(
        threadId: threadPath,
        turnId: 'turn-1',
        itemId: 'tool-1',
        delta: List.filled(50000, 'x').join(),
      ),
    );
    await tester.pump();
    await tester.pump(_liveStatusFlushDelay);

    final rowsAfterDelta = debugRowsSnapshots.lastOrNull ?? const <DatasetChatDebugRow>[];
    expect(rowsAfterDelta.map((row) => row.signature), rowsBeforeDelta.map((row) => row.signature));
    expect(
      rowsAfterDelta.where((row) => row.data.containsKey('argument_delta_text') || row.data.containsKey('argument_delta_bytes')),
      isEmpty,
    );
    expect(find.textContaining('50,000'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
