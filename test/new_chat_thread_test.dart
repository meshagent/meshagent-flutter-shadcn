import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/multi_thread_view.dart';
import 'package:meshagent_flutter_shadcn/chat/new_chat_thread.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

class _PendingStartChatClient extends agent_sessions.BaseChatClient {
  _PendingStartChatClient(this.room);

  final RoomClient room;
  final List<agent_sessions.AgentMessage> sentMessages = <agent_sessions.AgentMessage>[];

  @override
  RemoteParticipant? agentParticipant() => RemoteParticipant(client: room, id: 'assistant', role: 'agent', online: true);

  @override
  Future<void> sendAgentMessage(agent_sessions.AgentMessage message, {Uint8List? attachment}) async {
    sentMessages.add(message);
  }
}

class _MultiThreadFocusHarness extends StatefulWidget {
  const _MultiThreadFocusHarness({required this.room, required this.controller});

  final RoomClient room;
  final ChatThreadController controller;

  @override
  State<_MultiThreadFocusHarness> createState() => _MultiThreadFocusHarnessState();
}

class _MultiThreadFocusHarnessState extends State<_MultiThreadFocusHarness> {
  String? _selectedThreadPath;

  @override
  Widget build(BuildContext context) {
    return MultiThreadView(
      room: widget.room,
      agentName: 'assistant',
      controller: widget.controller,
      centerComposer: false,
      selectedThreadPath: _selectedThreadPath,
      onSelectedThreadPathChanged: (path) {
        setState(() {
          _selectedThreadPath = path;
        });
      },
      builder: (context, threadPath, controller, composerKey) {
        return ChatThreadInput(
          key: composerKey,
          room: widget.room,
          controller: controller,
          clearOnSend: false,
          onSend: (text, attachments) async {},
        );
      },
    );
  }
}

void main() {
  testWidgets('reports new-thread start activity while the server path is pending', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final chatClient = _PendingStartChatClient(room);
    final activity = <bool>[];
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: NewChatThread(
              room: room,
              chatClient: chatClient,
              agentName: 'assistant',
              controller: controller,
              onThreadStartActivityChanged: activity.add,
              builder: (context, threadPath) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    controller.textFieldController.text = 'Create a site';
    await tester.pump();
    final sendFuture = tester.widget<ChatThreadInput>(find.byType(ChatThreadInput)).onSend('Create a site', const []);
    await tester.pump();

    expect(activity, [true]);
    final request = chatClient.sentMessages.whereType<agent_sessions.StartThread>().single;
    chatClient.handleAgentMessage(agent_sessions.ThreadStarted(sourceMessageId: request.messageId, threadId: 'dataset://threads/new-site'));
    await sendFuture;
    await tester.pumpAndSettle();

    expect(activity, [true, false]);
  });

  test('controller clear preserves enabled toolkits and selected MCP connectors', () {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    final controller = ChatThreadController(room: room);
    controller.toggleToolkit('mcp');
    controller.setMcpConnectorSelected(OpenAIConnectors.gmail, true);
    controller.textFieldController.text = 'draft';
    controller.attachFile('/draft.txt');

    controller.clear();

    expect(controller.isToolkitEnabled('mcp'), isTrue);
    expect(controller.selectedMcpConnectors.map((connector) => connector.name), ['Gmail']);
    expect(controller.text, isEmpty);
    expect(controller.attachmentUploads, isEmpty);
  });

  test('inline data attachments keep the original file name in pending uploads', () {
    final controller = ChatThreadController(room: null);
    addTearDown(controller.dispose);

    controller.attachFile('data:text/plain;base64,aGVsbG8=', mimeType: 'text/plain', displayName: 'readme.md');

    expect(controller.attachmentUploads.single.filename, 'readme.md');
  });

  test('inline data attachments without display names use a generated pending upload file name', () {
    final controller = ChatThreadController(room: null);
    addTearDown(controller.dispose);

    controller.attachFile('data:text/plain;base64,aGVsbG8=', mimeType: 'text/plain');

    expect(controller.attachmentUploads.single.filename, 'attachment.txt');
  });

  testWidgets('new thread composer reports removed attachments without changing typed text', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final removedPaths = <String>[];
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: NewChatThread(
              room: room,
              agentName: 'assistant',
              controller: controller,
              onAttachmentRemoved: (attachment) => removedPaths.add(attachment.path),
              builder: (context, threadPath) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.textFieldController.text = 'keep this draft';
    controller.attachFile('/draft.txt');
    await tester.pump();

    tester.widget<FileDefaultAttachmentPreview>(find.byType(FileDefaultAttachmentPreview)).onRemove();
    await tester.pump();

    expect(removedPaths, ['/draft.txt']);
    expect(controller.attachmentUploads, isEmpty);
    expect(controller.text, 'keep this draft');
    expect(find.text('keep this draft'), findsOneWidget);
  });

  testWidgets('wraps the new thread composer in a file drop area', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: NewChatThread(room: room, agentName: 'assistant', builder: (context, threadPath) => const SizedBox.shrink()),
          ),
        ),
      ),
    );

    expect(find.byType(ChatThreadInput), findsOneWidget);
    expect(find.byType(FileDropArea), findsOneWidget);
    expect(find.ancestor(of: find.byType(ChatThreadInput), matching: find.byType(FileDropArea)), findsOneWidget);
  });

  testWidgets('renders tool footers below the new thread composer', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: NewChatThread(
              room: room,
              agentName: 'assistant',
              toolsBuilder: (context, controller, state) => const ChatThreadToolArea(leading: Text('Attach'), footer: Text('MCP footer')),
              builder: (context, threadPath) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Attach'), findsOneWidget);
    expect(find.text('MCP footer'), findsOneWidget);
  });

  testWidgets('footer width stays stable when send button visibility changes', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final footerKey = GlobalKey();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: ChatThreadInput(
              room: room,
              controller: controller,
              footer: Container(key: footerKey, alignment: Alignment.centerLeft, child: const Text('MCP footer')),
              onSend: (text, attachments) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final footerWidthWithoutSend = tester.getSize(find.byKey(footerKey)).width;

    controller.textFieldController.text = 'hello';
    await tester.pump();

    final footerWidthWithSend = tester.getSize(find.byKey(footerKey)).width;
    expect(footerWidthWithSend, footerWidthWithoutSend);
  });

  testWidgets('composer box does not resize when focus changes', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final composerKey = GlobalKey();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        themeMode: ThemeMode.dark,
        darkTheme: ShadThemeData(
          brightness: Brightness.dark,
          inputTheme: ShadInputTheme(
            decoration: ShadDecoration(border: ShadBorder.all(width: 1, padding: const EdgeInsets.all(1))),
          ),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: ChatThreadInput(key: composerKey, room: room, controller: controller, onSend: (text, attachments) async {}),
          ),
        ),
      ),
    );
    await tester.pump();

    final inputFinder = find.byType(ShadInput);
    final decoration = tester.widget<ShadInput>(inputFinder).decoration!;
    expect(decoration.focusedBorder?.top?.color, isNot(decoration.border?.top?.color));
    expect(decoration.focusedBorder?.top?.width, decoration.border?.top?.width);
    expect(decoration.focusedBorder?.radius, decoration.border?.radius);
    expect(decoration.focusedBorder?.padding, decoration.border?.padding);

    final composerFinder = find.byKey(composerKey);
    final unfocusedComposerHeight = tester.getSize(composerFinder).height;
    final unfocusedSize = tester.getSize(inputFinder);
    final unfocusedTopLeft = tester.getTopLeft(inputFinder);

    await tester.tap(find.byType(EditableText));
    await tester.pump();

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    expect(tester.getSize(composerFinder).height, unfocusedComposerHeight);
    expect(tester.getSize(inputFinder).height, unfocusedSize.height);
    expect(tester.getSize(inputFinder), unfocusedSize);
    expect(tester.getTopLeft(inputFinder), unfocusedTopLeft);
  });

  testWidgets('mcp footer keeps row content visible while connectors load', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final completer = Completer<List<Connector>>();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    controller.toggleToolkit('mcp');

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ChatThreadMcpFooter(
            controller: controller,
            agentName: 'assistant',
            showMcpConnectors: true,
            availableConnectors: () => completer.future,
          ),
        ),
      ),
    );

    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.text('MCP'));
    await tester.pump();

    expect(find.text('Add'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const <Connector>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the draft visible while send is pending when clearOnSend is false', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final completer = Completer<void>();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: ChatThreadInput(room: room, controller: controller, clearOnSend: false, onSend: (text, attachments) => completer.future),
          ),
        ),
      ),
    );

    controller.textFieldController.text = 'draft message';
    await tester.pump();
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    await tester.tap(find.byIcon(LucideIcons.arrowUp));
    await tester.pump();

    expect(controller.text, 'draft message');
    expect(find.text('draft message'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    completer.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('keeps text typed while send is pending when clearOnSend is true', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final completer = Completer<void>();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: ChatThreadInput(room: room, controller: controller, onSend: (text, attachments) => completer.future),
          ),
        ),
      ),
    );

    controller.textFieldController.text = 'draft message';
    await tester.pump();
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    await tester.tap(find.byIcon(LucideIcons.arrowUp));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(find.text('draft message'), findsNothing);

    controller.textFieldController.text = 'next draft';
    await tester.pump();

    completer.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(controller.text, 'next draft');
    expect(find.text('next draft'), findsOneWidget);
  });

  testWidgets('mouse clicking send keeps the composer focused', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final completer = Completer<void>();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: ChatThreadInput(room: room, controller: controller, clearOnSend: false, onSend: (text, attachments) => completer.future),
          ),
        ),
      ),
    );

    controller.textFieldController.text = 'draft message';
    await tester.pump();
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    final sendButtonCenter = tester.getCenter(find.byIcon(LucideIcons.arrowUp));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: sendButtonCenter);
    await tester.pump();
    await gesture.moveTo(sendButtonCenter);
    await tester.pump();
    await gesture.down(sendButtonCenter);
    await tester.pump();

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    await gesture.up();
    await tester.pump();

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

    await gesture.removePointer();

    completer.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('preserves the same focused composer when switching from new thread to thread view', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: _MultiThreadFocusHarness(room: room, controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(EditableText));
    await tester.pump();

    final originalFocusNode = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(originalFocusNode.hasFocus, isTrue);

    final newThread = tester.widget<NewChatThread>(find.byType(NewChatThread));
    newThread.onThreadPathChanged?.call('/threads/focused.thread');
    await tester.pumpAndSettle();

    expect(find.byType(NewChatThread), findsOneWidget);
    expect(find.byType(ChatThreadInput), findsOneWidget);
    final updatedFocusNode = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(identical(updatedFocusNode, originalFocusNode), isTrue);
    expect(updatedFocusNode.hasFocus, isTrue);
  });
}
