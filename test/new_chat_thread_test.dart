import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/multi_thread_view.dart';
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

    expect(find.byType(NewChatThread), findsNothing);
    final updatedFocusNode = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(identical(updatedFocusNode, originalFocusNode), isTrue);
    expect(updatedFocusNode.hasFocus, isTrue);
  });
}
