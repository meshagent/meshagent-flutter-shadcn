import 'dart:typed_data';
import 'dart:async';

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
  test('controller clear preserves enabled toolkits and selected MCP connectors', () {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
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

  testWidgets('renders tool footers below the new thread composer', (tester) async {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: NewChatThread(
              room: room,
              agentName: 'assistant',
              toolsBuilder: (context, controller, state) => const ChatThreadToolArea(leading: Text('Attach'), footer: Text('MCP footer')),
              builder: (context, threadPath, loadingBuilder) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Attach'), findsOneWidget);
    expect(find.text('MCP footer'), findsOneWidget);
  });

  testWidgets('footer width stays stable when send button visibility changes', (tester) async {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
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
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
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
}
