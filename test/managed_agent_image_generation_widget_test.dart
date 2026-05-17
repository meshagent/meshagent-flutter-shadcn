import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
import 'package:meshagent_flutter_shadcn/chat/new_chat_thread.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _FakeManagedAgentChatClient extends agent_sessions.BaseChatClient {
  _FakeManagedAgentChatClient({this.participantName, this.autoCompleteThreadLoad = true});

  final String? participantName;
  final bool autoCompleteThreadLoad;
  final List<agent_sessions.AgentMessage> sentMessages = <agent_sessions.AgentMessage>[];
  int _threadCounter = 0;

  @override
  Future<void> start() async {
    emitConnectionStatus(status: 'connected', message: 'Chat websocket connected');
  }

  @override
  Future<void> stop() async {}

  @override
  String? localParticipantName() => participantName;

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment, bool ignoreOffline = false}) async {
    sentMessages.add(message);
    if (message is agent_sessions.StartThread) {
      final threadId = 'thread-${++_threadCounter}';
      scheduleMicrotask(() {
        handleAgentMessage(
          agent_sessions.ThreadStarted(
            threadId: threadId,
            sourceMessageId: message.messageId,
            messageId: 'thread-started-${message.messageId}',
          ),
        );
      });
    } else if (autoCompleteThreadLoad && message is agent_sessions.OpenThread && message.load != false) {
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

class _ManagedAgentThreadHarness extends StatefulWidget {
  const _ManagedAgentThreadHarness({required this.chatClient, required this.debugRows});

  final _FakeManagedAgentChatClient chatClient;
  final List<List<DatasetChatDebugRow>> debugRows;

  @override
  State<_ManagedAgentThreadHarness> createState() => _ManagedAgentThreadHarnessState();
}

class _ManagedAgentThreadHarnessState extends State<_ManagedAgentThreadHarness> {
  final ChatThreadController _controller = ChatThreadController(room: null);
  final DatasetChatModelController _modelController = DatasetChatModelController();
  String? _threadPath;

  @override
  void dispose() {
    _controller.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NewChatThread(
      chatClient: widget.chatClient,
      agentName: 'image-gen',
      controller: _controller,
      modelController: _modelController,
      selectedThreadPath: _threadPath,
      onThreadPathChanged: (path) {
        setState(() {
          _threadPath = path;
        });
      },
      inputPlaceholder: const Text('Message agent'),
      centerComposer: false,
      builder: (context, threadPath) {
        return DatasetChatThread(
          chatClient: widget.chatClient,
          path: threadPath,
          agentName: 'image-gen',
          controller: _controller,
          modelController: _modelController,
          inputPlaceholder: const Text('Message agent'),
          onDebugRowsChanged: widget.debugRows.add,
          generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) =>
              const SizedBox(key: Key('rendered-generated-image'), width: 96, height: 96, child: Text('rendered image')),
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('managed agent thread shows a loading indicator until replay completes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient(autoCompleteThreadLoad: false);
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              chatClient: chatClient,
              path: 'thread-loading',
              agentName: 'image-gen',
              inputPlaceholder: const Text('Message agent'),
              onDebugRowsChanged: debugRows.add,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final openThread = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().single;
    chatClient.emit(agent_sessions.ThreadLoaded(threadId: 'thread-loading', sourceMessageId: openThread.messageId));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent thread suppresses replayed pending state and sends while loading', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient(autoCompleteThreadLoad: false);
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              chatClient: chatClient,
              path: 'thread-loading',
              agentName: 'image-gen',
              inputPlaceholder: const Text('Message agent'),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    chatClient.emit(
      agent_sessions.TurnStart(
        threadId: 'thread-loading',
        messageId: 'replayed-input-1',
        senderName: 'jesse.ezell',
        content: agent_sessions.agentInputContent(text: 'old replayed prompt', attachments: const []),
      ),
    );
    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: 'thread-loading',
        turnId: 'replayed-turn-1',
        sourceMessageId: 'replayed-input-1',
        messageId: 'replayed-turn-started-1',
        senderName: 'image-gen',
      ),
    );
    await tester.pump();

    expect(find.text('Pending messages:'), findsNothing);
    expect(find.text('old replayed prompt'), findsNothing);
    expect(find.byType(ChatThreadProcessingStatusRow), findsNothing);

    final sentCountWhileLoading = chatClient.sentMessages.length;
    final editableText = find.byType(EditableText);
    expect(editableText, findsOneWidget);
    await tester.tap(editableText);
    await tester.enterText(editableText, 'do not send yet');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(chatClient.sentMessages, hasLength(sentCountWhileLoading));

    final openThread = chatClient.sentMessages.whereType<agent_sessions.OpenThread>().single;
    chatClient.emit(agent_sessions.ThreadLoaded(threadId: 'thread-loading', sourceMessageId: openThread.messageId));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent widget renders non-dataset image generation completion and clears status', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient();
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: _ManagedAgentThreadHarness(chatClient: chatClient, debugRows: debugRows),
          ),
        ),
      ),
    );
    await tester.pump();

    final editableText = find.byType(EditableText);
    expect(editableText, findsOneWidget);
    await tester.tap(editableText);
    await tester.enterText(editableText, 'make me an image of a cat');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final started = chatClient.sentMessages.whereType<agent_sessions.StartThread>().single;
    const turnId = 'turn-1';
    const itemId = 'image-call-1';
    final threadId = chatClient.sessions.single.threadPath;

    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: threadId,
        turnId: turnId,
        sourceMessageId: started.messageId,
        messageId: 'turn-started-1',
        senderName: 'image-gen',
      ),
    );
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentImageGenerationStarted(
        threadId: threadId,
        turnId: turnId,
        itemId: itemId,
        messageId: 'image-started-1',
        senderName: 'image-gen',
      ),
    );
    await tester.pump();

    expect(debugRows.last.map((row) => row.type), contains(agent_sessions.agentImageGenerationStartedType));
    expect(debugRows.last.map((row) => row.type), isNot(contains('message')));

    chatClient.emit(
      agent_sessions.AgentConnectionStatus(
        status: 'disconnected',
        messageId: 'connection-disconnected-1',
        message: 'Chat websocket disconnected',
        reason: 'test disconnect',
      ),
    );
    await tester.pump();

    expect(debugRows.last.map((row) => row.type), contains(agent_sessions.agentConnectionStatusType));
    expect(debugRows.last.map((row) => row.type), isNot(contains('message')));

    chatClient.emit(
      agent_sessions.AgentImageGenerationCompleted(
        threadId: threadId,
        turnId: turnId,
        itemId: itemId,
        messageId: 'image-completed-1',
        senderName: 'image-gen',
        images: const <agent_sessions.AgentGeneratedImage>[
          agent_sessions.AgentGeneratedImage(
            uri: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
            mimeType: 'image/png',
            width: 1,
            height: 1,
            status: 'completed',
          ),
        ],
      ),
    );
    chatClient.emit(agent_sessions.TurnEnded(threadId: threadId, turnId: turnId, messageId: 'turn-ended-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final finalDebugRows = debugRows.last;
    expect(finalDebugRows.map((row) => row.type), contains(agent_sessions.agentImageGenerationCompletedType));
    expect(finalDebugRows.map((row) => row.type), isNot(contains('message')));
    expect(find.byKey(const Key('rendered-generated-image')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent widget treats local websocket participant messages as mine', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient(participantName: 'jesse.ezell@timu.com');
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: _ManagedAgentThreadHarness(chatClient: chatClient, debugRows: debugRows),
          ),
        ),
      ),
    );
    await tester.pump();

    final editableText = find.byType(EditableText);
    expect(editableText, findsOneWidget);
    await tester.tap(editableText);
    await tester.enterText(editableText, 'hello from me');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final started = chatClient.sentMessages.whereType<agent_sessions.StartThread>().single;
    expect(started.senderName, 'jesse.ezell@timu.com');
    expect(
      find.byWidgetPredicate((widget) => widget is ChatThreadMessageView && widget.text == 'hello from me' && widget.mine),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent inline file attachments render filename and open inline preview', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient(participantName: 'jesse.ezell');
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: _ManagedAgentThreadHarness(chatClient: chatClient, debugRows: debugRows),
          ),
        ),
      ),
    );
    await tester.pump();

    final editableText = find.byType(EditableText);
    await tester.tap(editableText);
    await tester.enterText(editableText, 'hello');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final threadId = chatClient.sessions.single.threadPath;
    chatClient.emit(
      agent_sessions.TurnStart(
        threadId: threadId,
        messageId: 'file-message-1',
        senderName: 'jesse.ezell',
        content: agent_sessions.agentInputContent(
          text: "what's in this file",
          attachments: const <agent_sessions.AgentFileContent>[
            agent_sessions.AgentFileContent(url: 'data:application/pdf;base64,JVBERi0xLjQKJcfsj6IK', name: 'timu domain.pdf'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Inline attachment (application/pdf)'), findsNothing);
    expect(find.text('timu domain.pdf'), findsOneWidget);

    await tester.tap(find.text('timu domain.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('timu domain.pdf'), findsAtLeastNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
