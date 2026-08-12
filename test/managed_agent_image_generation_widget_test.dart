import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
import 'package:meshagent_flutter_shadcn/chat/new_chat_thread.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _FakeManagedAgentChatClient extends agent_sessions.BaseChatClient {
  _FakeManagedAgentChatClient({this.participantName, this.participantId, this.autoCompleteThreadLoad = true})
    : super(deduplicateClientToolRequests: true);

  final String? participantName;
  final String? participantId;
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
  String? localParticipantId() => participantId;

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment}) async {
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

class _TestClientTool extends FunctionTool implements ToolResponseSentListener {
  _TestClientTool() : super(name: 'ask_user', title: 'Ask User', description: 'Ask the user a question', inputSchema: _schema);

  static const Map<String, dynamic> _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['prompt'],
    'properties': {
      'prompt': {'type': 'string'},
    },
  };

  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];
  int responseSentCount = 0;

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    calls.add(arguments);
    return JsonContent(json: <String, dynamic>{'answer': 'test response'});
  }

  @override
  void onToolResponseSent(ToolContext context, Content response) {
    responseSentCount += 1;
  }
}

class _TestClientToolkit extends Toolkit {
  _TestClientToolkit(this.tool) : super(name: 'test-client-tools', tools: [tool]);

  final _TestClientTool tool;
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

    chatClient.emit(
      agent_sessions.AgentConnectionStatus(
        status: 'disconnected',
        messageId: 'connection-disconnected-1',
        message: 'Chat websocket disconnected',
        reason: 'test disconnect',
      ),
    );
    await tester.pump();

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
    expect(find.byKey(const Key('rendered-generated-image')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('live generated image completion links dispatch save and copy actions', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    final changedImages = <DatasetThreadImage>[];
    final savedPrompts = <String>[];
    final clipboardWrites = <MethodCall>[];
    addTearDown(chatClient.stop);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add(call);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: DatasetChatThread(
            chatClient: chatClient,
            path: 'thread-live-image-prompt',
            generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) => const Text('live image'),
            onGeneratedImageChanged: changedImages.add,
            onGeneratedImageSave: (context, image) => savedPrompts.add(image.sourcePrompt!),
            generatedImageReadyText: '''
Your image is ready. You can:

- [Save a copy] to your files,
- [Copy prompt] used.

Or continue to refine it.''',
            replaceGeneratedImageTurnFinalAnswer: true,
          ),
        ),
      ),
    );
    await tester.pump();

    chatClient.emit(
      agent_sessions.TurnStart(
        threadId: 'thread-live-image-prompt',
        messageId: 'user-message-1',
        senderName: 'jesse.ezell',
        content: agent_sessions.agentInputContent(text: 'Create an image of a cat in a library', attachments: const []),
      ),
    );
    chatClient.emit(
      agent_sessions.TurnStarted(
        threadId: 'thread-live-image-prompt',
        turnId: 'turn-1',
        sourceMessageId: 'user-message-1',
        messageId: 'turn-started-1',
      ),
    );
    chatClient.emit(
      agent_sessions.AgentImageGenerationCompleted(
        threadId: 'thread-live-image-prompt',
        turnId: 'turn-1',
        itemId: 'image-1',
        messageId: 'image-completed-1',
        arguments: const {
          'prompt': 'Create an image of a cat in a library',
          'revised_prompt': 'A curious orange cat reading beneath tall library shelves',
        },
        images: const [agent_sessions.AgentGeneratedImage(uri: 'data:image/png;base64,cG5n', mimeType: 'image/png', status: 'completed')],
      ),
    );
    chatClient.emit(
      agent_sessions.TurnEnded(
        threadId: 'thread-live-image-prompt',
        turnId: 'turn-1',
        messageId: 'turn-ended-1',
        error: const agent_sessions.AgentError(message: 'Cannot write to closing transport'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('live image'), findsOneWidget);
    expect(changedImages.last.sourcePrompt, 'Create an image of a cat in a library');
    expect(changedImages.last.effectivePrompt, 'A curious orange cat reading beneath tall library shelves');
    expect(find.textContaining('Save a copy'), findsOneWidget);
    expect(find.textContaining('Copy prompt'), findsOneWidget);
    expect(find.text('Cannot write to closing transport'), findsNothing);

    await tester.tapOnText(find.textRange.ofSubstring('Save a copy'));
    await tester.pump();
    expect(savedPrompts, ['Create an image of a cat in a library']);

    await tester.tapOnText(find.textRange.ofSubstring('Copy prompt'));
    await tester.pump();
    expect(clipboardWrites, hasLength(1));
    expect(
      (clipboardWrites.single.arguments as Map<Object?, Object?>)['text'],
      'A curious orange cat reading beneath tall library shelves',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  test('live completed image wins while its persisted lifecycle row is still pending', () {
    final merged = mergeDatasetAndLiveRowForTesting(
      datasetRow: {
        'item_id': 'image-2',
        'turn_id': 'turn-2',
        'sequence': 4,
        'data': {
          'kind': 'image_generation',
          'role': 'assistant',
          'status': 'in_progress',
          'arguments': {'prompt': 'Create a blue whale at sunset'},
          'message': {'type': agent_sessions.agentImageGenerationStartedType, 'item_id': 'image-2'},
        },
      },
      liveRow: {
        'item_id': 'image-2',
        'turn_id': 'turn-2',
        'sequence': 8,
        'data': {
          'kind': 'image_generation',
          'role': 'assistant',
          'status': 'completed',
          'arguments': {'prompt': 'Create a blue whale at sunset', 'revised_prompt': 'A blue whale surfacing beneath a vivid sunset'},
          'message': {
            'type': agent_sessions.agentImageGenerationCompletedType,
            'item_id': 'image-2',
            'images': [
              {'uri': 'dataset://images?id=saved-image-2', 'mime_type': 'image/png', 'status': 'completed'},
            ],
          },
        },
      },
    );

    expect(merged['sequence'], 4);
    final mergedData = merged['data']! as Map<String, Object?>;
    expect(mergedData['status'], 'completed');
    final images = (mergedData['message']! as Map<String, Object?>)['images']! as List<Object?>;
    expect((images.single! as Map<String, Object?>)['uri'], 'dataset://images?id=saved-image-2');
    expect((mergedData['arguments']! as Map<String, Object?>)['revised_prompt'], 'A blue whale surfacing beneath a vivid sunset');
  });

  test('sequence-keyed dataset lifecycle merges with its live image completion', () {
    final rows = mergeDatasetAndLiveRowsForTesting(
      datasetRowsByKey: {
        'sequence:4': {
          'item_id': 'image-2',
          'turn_id': 'turn-2',
          'sequence': 4,
          'data': {
            'kind': 'image_generation',
            'role': 'assistant',
            'status': 'in_progress',
            'message': {'type': agent_sessions.agentImageGenerationStartedType, 'item_id': 'image-2'},
          },
        },
      },
      liveRowsByKey: {
        'image-2': {
          'item_id': 'image-2',
          'turn_id': 'turn-2',
          'sequence': 8,
          'data': {
            'kind': 'image_generation',
            'role': 'assistant',
            'status': 'completed',
            'message': {
              'type': agent_sessions.agentImageGenerationCompletedType,
              'item_id': 'image-2',
              'images': [
                {'uri': 'dataset://images?id=saved-image-2', 'mime_type': 'image/png', 'status': 'completed'},
              ],
            },
          },
        },
      },
    );

    expect(rows, hasLength(1));
    final image = (rows.single['data']! as Map<String, Object?>)['message']! as Map<String, Object?>;
    expect(image['type'], agent_sessions.agentImageGenerationCompletedType);
    expect(((image['images']! as List<Object?>).single! as Map<String, Object?>)['uri'], 'dataset://images?id=saved-image-2');
  });

  test('reused image item identifiers do not correlate across turns', () {
    final rows = mergeDatasetAndLiveRowsForTesting(
      datasetRowsByKey: {
        'sequence:2': {
          'item_id': 'image-generation',
          'turn_id': 'turn-1',
          'sequence': 2,
          'data': {
            'kind': 'image_generation',
            'status': 'completed',
            'message': {
              'type': agent_sessions.agentImageGenerationCompletedType,
              'item_id': 'image-generation',
              'images': [
                {'uri': 'dataset://images?id=first', 'status': 'completed'},
              ],
            },
          },
        },
      },
      liveRowsByKey: {
        'image-generation': {
          'item_id': 'image-generation',
          'turn_id': 'turn-2',
          'sequence': 5,
          'data': {
            'kind': 'image_generation',
            'status': 'completed',
            'message': {
              'type': agent_sessions.agentImageGenerationCompletedType,
              'item_id': 'image-generation',
              'images': [
                {'uri': 'dataset://images?id=second', 'status': 'completed'},
              ],
            },
          },
        },
      },
    );

    expect(rows, hasLength(2));
    expect(rows.map((row) => row['turn_id']), containsAll(<String>['turn-1', 'turn-2']));
  });

  testWidgets('turn end terminalizes an image lifecycle left pending by the provider', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    final changedImages = <DatasetThreadImage>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: DatasetChatThread(
          chatClient: chatClient,
          path: 'thread-incomplete-image',
          generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) => Text('image:${image.status}'),
          onGeneratedImageChanged: changedImages.add,
        ),
      ),
    );
    await tester.pump();

    chatClient.emit(
      agent_sessions.AgentImageGenerationStarted(
        threadId: 'thread-incomplete-image',
        turnId: 'turn-1',
        itemId: 'image-1',
        messageId: 'image-started-1',
        arguments: const {'prompt': 'Create a dinosaur chasing a taxi'},
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(changedImages.last.status, 'pending');

    chatClient.emit(agent_sessions.TurnEnded(threadId: 'thread-incomplete-image', turnId: 'turn-1', messageId: 'turn-ended-1'));
    await tester.pump();
    await tester.pump();

    expect(changedImages.last.status, 'failed');
    expect(find.text('image:failed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('two generated image turns keep independent completed lifecycle rows', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    final changedImages = <DatasetThreadImage>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: DatasetChatThread(
            chatClient: chatClient,
            path: 'thread-two-live-images',
            generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) => Text('image:${image.generationId}'),
            onGeneratedImageChanged: changedImages.add,
            onGeneratedImageSave: (context, image) {},
            generatedImageReadyText: 'Image ready. [Save a copy]. [Copy prompt].',
            replaceGeneratedImageTurnFinalAnswer: true,
          ),
        ),
      ),
    );
    await tester.pump();

    for (final turn in const [('turn-1', 'image-1', 'first'), ('turn-2', 'image-2', 'second')]) {
      chatClient.emit(
        agent_sessions.TurnStart(
          threadId: 'thread-two-live-images',
          messageId: 'user-${turn.$1}',
          content: agent_sessions.agentInputContent(text: 'Create the ${turn.$3} image', attachments: const []),
        ),
      );
      chatClient.emit(
        agent_sessions.AgentImageGenerationStarted(
          threadId: 'thread-two-live-images',
          turnId: turn.$1,
          itemId: turn.$2,
          messageId: 'started-${turn.$2}',
          arguments: {'prompt': 'Create the ${turn.$3} image'},
        ),
      );
      chatClient.emit(
        agent_sessions.AgentImageGenerationCompleted(
          threadId: 'thread-two-live-images',
          turnId: turn.$1,
          itemId: turn.$2,
          messageId: 'completed-${turn.$2}',
          arguments: {'prompt': 'Create the ${turn.$3} image', 'revised_prompt': 'Revised ${turn.$3} image'},
          images: [
            agent_sessions.AgentGeneratedImage(uri: 'dataset://images?id=saved-${turn.$2}', mimeType: 'image/png', status: 'completed'),
          ],
        ),
      );
    }
    await tester.pump();
    await tester.pump();

    expect(find.text('image:image-1'), findsOneWidget);
    expect(find.text('image:image-2'), findsOneWidget);
    expect(find.textContaining('Image ready.'), findsNWidgets(2));
    expect(
      changedImages.where((image) => image.status == 'completed').map((image) => image.generationId),
      containsAll(['image-1', 'image-2']),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('replayed generated images expose completion links inside assistant bubbles', (tester) async {
    final savedPrompts = <String>[];
    final changedImages = <DatasetThreadImage>[];
    final clipboardWrites = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add(call);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final rows = <Map<String, Object?>>[
      {
        'item_id': 'user-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-08-05T12:00:00Z',
        'data': {'kind': 'message', 'role': 'user', 'text': 'Create an image of a red fox in snow'},
      },
      {
        'item_id': 'image-1',
        'turn_id': 'turn-1',
        'sequence': 2,
        'timestamp': '2026-08-05T12:00:01Z',
        'data': {
          'kind': 'image_generation',
          'status': 'completed',
          'message': {
            'images': [
              {'uri': 'data:image/png;base64,cG5nMQ==', 'mime_type': 'image/png', 'status': 'completed'},
            ],
          },
        },
      },
      {
        'item_id': 'answer-1',
        'turn_id': 'turn-1',
        'sequence': 3,
        'timestamp': '2026-08-05T12:00:02Z',
        'data': {'kind': 'message', 'role': 'agent', 'phase': 'final_answer', 'text': 'Created the red fox image.'},
      },
      {
        'item_id': 'user-2',
        'turn_id': 'turn-2',
        'sequence': 4,
        'timestamp': '2026-08-05T12:01:00Z',
        'data': {'kind': 'message', 'role': 'user', 'text': 'Create an image of a blue whale at sunset'},
      },
      {
        'item_id': 'image-2',
        'turn_id': 'turn-2',
        'sequence': 5,
        'timestamp': '2026-08-05T12:01:01Z',
        'data': {
          'kind': 'image_generation',
          'status': 'completed',
          'message': {
            'images': [
              {'uri': 'data:image/png;base64,cG5nMg==', 'mime_type': 'image/png', 'status': 'completed'},
            ],
          },
        },
      },
      {
        'item_id': 'answer-2',
        'turn_id': 'turn-2',
        'sequence': 6,
        'timestamp': '2026-08-05T12:01:02Z',
        'data': {'kind': 'message', 'role': 'agent', 'phase': 'final_answer', 'text': 'Created the blue whale image.'},
      },
    ];

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: DatasetChatThread(
            path: 'dataset://threads/replay-images',
            rowsLoader: ({required namespace, required table}) => Stream.value(rows),
            generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) => Text('image:${image.generationId}'),
            onGeneratedImageChanged: changedImages.add,
            onGeneratedImageSave: (context, image) => savedPrompts.add(image.sourcePrompt!),
            generatedImageReadyText: '''
Your image is ready. You can:

- [Save a copy] to your files,
- [Copy prompt] used.

Or continue to refine it.''',
            replaceGeneratedImageTurnFinalAnswer: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      changedImages.map((image) => image.sourcePrompt),
      containsAll(<String>['Create an image of a red fox in snow', 'Create an image of a blue whale at sunset']),
    );
    expect(find.textContaining('Save a copy'), findsNWidgets(2));
    expect(find.textContaining('Copy prompt'), findsNWidgets(2));
    expect(find.textContaining('Created the red fox image.'), findsNothing);
    expect(find.textContaining('Created the blue whale image.'), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    final completionMessages = find.byWidgetPredicate(
      (widget) =>
          widget is ChatThreadMessageView &&
          widget.text?.contains('meshagent-action://generated-image/save-copy') == true &&
          widget.text?.contains('meshagent-action://generated-image/copy-prompt') == true,
    );
    expect(completionMessages, findsNWidgets(2));
    final firstCompletion = tester.widget<ChatThreadMessageView>(completionMessages.first);
    firstCompletion.markdownLinkHandler!(tester.element(completionMessages.first), 'meshagent-action://generated-image/save-copy');
    await tester.pump();
    expect(savedPrompts, hasLength(1));

    final secondCompletion = tester.widget<ChatThreadMessageView>(completionMessages.last);
    secondCompletion.markdownLinkHandler!(tester.element(completionMessages.last), 'meshagent-action://generated-image/copy-prompt');
    await tester.pump();
    expect(clipboardWrites, hasLength(1));
    expect(
      {savedPrompts.single, (clipboardWrites.single.arguments as Map<Object?, Object?>)['text']},
      {'Create an image of a red fox in snow', 'Create an image of a blue whale at sunset'},
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('deleted attachment replay keeps loaded history visible while the agent session is loading', (tester) async {
    final chatClient = _FakeManagedAgentChatClient(autoCompleteThreadLoad: false);
    addTearDown(chatClient.stop);
    final rows = <Map<String, Object?>>[
      {
        'item_id': 'user-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-08-05T12:00:00Z',
        'data': {
          'kind': 'message',
          'role': 'user',
          'text': 'Please inspect this image',
          'attachments': [
            {'url': 'room:///deleted-image.png', 'name': 'deleted-image.png'},
          ],
        },
      },
    ];

    await tester.pumpWidget(
      ShadApp(
        home: ThreadTypographyOverride(
          showAttachmentReplayWhileLoading: true,
          child: Scaffold(
            body: DatasetChatThread(
              path: 'dataset://threads/deleted-attachment',
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => Stream.value(rows),
              attachmentRenderer: (context, path) => Text(path == 'deleted-image.png' ? 'Attachment unavailable' : path),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(chatClient.sentMessages.whereType<agent_sessions.OpenThread>(), isNotEmpty);
    expect(find.text('Please inspect this image'), findsOneWidget);
    expect(find.text('Attachment unavailable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('moved attachment replay uses the supplied registry resolution without entering recovery', (tester) async {
    final chatClient = _FakeManagedAgentChatClient(autoCompleteThreadLoad: false);
    addTearDown(chatClient.stop);
    final rows = <Map<String, Object?>>[
      {
        'item_id': 'user-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-08-05T12:00:00Z',
        'data': {
          'kind': 'message',
          'role': 'user',
          'text': 'The moved attachment remains usable',
          'attachments': [
            {'url': 'room:///original/image.png', 'name': 'image.png'},
          ],
        },
      },
    ];

    await tester.pumpWidget(
      ShadApp(
        home: ThreadTypographyOverride(
          showAttachmentReplayWhileLoading: true,
          poisonedErrorPredicate: (message) => message.contains('unsupported image'),
          poisonedErrorBuilder: (context, {required error, required onStartNewThread}) => const Text('Recovery required'),
          child: Scaffold(
            body: DatasetChatThread(
              path: 'dataset://threads/moved-attachment',
              chatClient: chatClient,
              rowsLoader: ({required namespace, required table}) => Stream.value(rows),
              attachmentPathResolver: (path) => path == 'room:///original/image.png' ? 'room:///moved/image.png' : path,
              attachmentRenderer: (context, path) => Text('attachment:$path'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The moved attachment remains usable'), findsOneWidget);
    expect(find.text('attachment:moved/image.png'), findsOneWidget);
    expect(find.text('Recovery required'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('poisoned attachment replay replaces the provider error and locks composing until new thread', (tester) async {
    const providerError = 'The image data you provided does not represent a valid image. Please check your input and try again.';
    var startedNewThread = false;
    final rows = <Map<String, Object?>>[
      {
        'item_id': 'error-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'timestamp': '2026-08-05T12:00:00Z',
        'data': {'kind': 'error', 'role': 'assistant', 'status': 'failed', 'text': providerError},
      },
    ];

    await tester.pumpWidget(
      ShadApp(
        home: ThreadTypographyOverride(
          poisonedErrorPredicate: (message) => message == providerError,
          poisonedErrorBuilder: (context, {required error, required onStartNewThread}) => Column(
            children: [
              const Text('This thread cannot continue with that attachment.'),
              TextButton(onPressed: onStartNewThread, child: const Text('Start new thread')),
            ],
          ),
          onStartNewThread: () => startedNewThread = true,
          child: Scaffold(
            body: DatasetChatThread(
              path: 'dataset://threads/poisoned-attachment',
              rowsLoader: ({required namespace, required table}) => Stream.value(rows),
              customInputBuilder: (context, config, defaultInput) =>
                  Text('readOnly:${config.readOnly};sendEnabled:${config.sendEnabled};reason:${config.sendDisabledReason}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(providerError), findsNothing);
    expect(find.text('This thread cannot continue with that attachment.'), findsOneWidget);
    expect(find.text('readOnly:true;sendEnabled:false;reason:Start a new thread to continue.'), findsOneWidget);
    await tester.tap(find.text('Start new thread'));
    expect(startedNewThread, isTrue);
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

  testWidgets('managed agent widget invokes registered client toolkit and sends response', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const ui.Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatClient = _FakeManagedAgentChatClient(participantName: 'jesse.ezell', participantId: 'participant-current');
    final controller = ChatThreadController(room: null);
    final tool = _TestClientTool();
    addTearDown(chatClient.stop);
    addTearDown(controller.dispose);

    controller.addClientToolkit(_TestClientToolkit(tool));

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 820,
            child: DatasetChatThread(
              chatClient: chatClient,
              path: 'thread-client-tools',
              agentName: 'agent',
              controller: controller,
              inputPlaceholder: const Text('Message agent'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final request = agent_sessions.AgentClientToolCallRequested(
      threadId: 'thread-client-tools',
      turnId: 'turn-client-tools',
      requestId: 'request-client-tools',
      toolkit: 'client',
      tool: 'ask_user',
      arguments: const <String, dynamic>{'prompt': 'What should I ask?'},
      targetParticipantId: 'participant-current',
    );
    chatClient.emit(request);
    chatClient.emit(request);
    chatClient.emit(
      agent_sessions.AgentClientToolCallRequested(
        threadId: 'thread-client-tools',
        turnId: 'turn-client-tools',
        requestId: 'request-for-stale-page',
        toolkit: 'client',
        tool: 'ask_user',
        arguments: const <String, dynamic>{'prompt': 'Stale request'},
        targetParticipantId: 'participant-stale',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tool.calls, [
      {'prompt': 'What should I ask?'},
    ]);
    final responses = chatClient.sentMessages.whereType<agent_sessions.AgentClientToolCallResponse>().toList(growable: false);
    expect(responses, hasLength(1));
    expect(responses.single.threadId, 'thread-client-tools');
    expect(responses.single.turnId, 'turn-client-tools');
    expect(responses.single.requestId, 'request-client-tools');
    expect(responses.single.response, isA<JsonContent>());
    expect((responses.single.response as JsonContent).json, {'answer': 'test response'});
    expect(tool.responseSentCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('managed agent widget consumes only the new suffix from merged tool argument deltas', (tester) async {
    final chatClient = _FakeManagedAgentChatClient();
    final debugRows = <List<DatasetChatDebugRow>>[];
    addTearDown(chatClient.stop);

    await tester.pumpWidget(
      ShadApp(
        home: DatasetChatThread(
          chatClient: chatClient,
          path: 'thread-tool-deltas',
          agentName: 'agent',
          inputPlaceholder: const Text('Message agent'),
          onDebugRowsChanged: debugRows.add,
        ),
      ),
    );
    await tester.pump();

    chatClient.emit(agent_sessions.TurnStarted(threadId: 'thread-tool-deltas', turnId: 'turn-1', sourceMessageId: 'source-1'));
    chatClient.emit(
      agent_sessions.AgentThreadStatus(threadId: 'thread-tool-deltas', turnId: 'turn-1', status: 'Preparing', pendingItemId: 'tool-1'),
    );
    chatClient.emit(
      agent_sessions.AgentToolCallArgumentsDelta(
        threadId: 'thread-tool-deltas',
        turnId: 'turn-1',
        itemId: 'tool-1',
        messageId: 'delta-1',
        delta: '0123456789',
      ),
    );
    await tester.pump();
    await tester.pump();
    final firstDeltaRow = debugRows.last.lastWhere((row) => row.type == agent_sessions.agentToolCallArgumentsDeltaType);
    expect(firstDeltaRow.data['delta'], '0123456789');
    chatClient.emit(
      agent_sessions.AgentToolCallArgumentsDelta(
        threadId: 'thread-tool-deltas',
        turnId: 'turn-1',
        itemId: 'tool-1',
        messageId: 'delta-2',
        delta: 'abcde',
      ),
    );
    await tester.pump();
    await tester.pump();

    final deltaRow = debugRows.last.lastWhere((row) => row.type == agent_sessions.agentToolCallArgumentsDeltaType);
    expect(deltaRow.data['delta'], 'abcde');

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
