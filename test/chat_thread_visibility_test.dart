import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent/runtime.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

class _FakeDocumentRuntime extends DocumentRuntime {
  _FakeDocumentRuntime() : super.base();

  @override
  void applyBackendChanges({required String documentId, required String base64}) {}

  @override
  void registerDocument(RuntimeDocument document) {}

  @override
  String getState({required String documentId, String? vectorBase64}) {
    return '';
  }

  @override
  String getStateVector({required String documentId}) {
    return '';
  }

  @override
  void sendChanges(Map<String, dynamic> message) {}

  @override
  void unregisterDocument(RuntimeDocument document) {}
}

final MeshSchema _threadSchema = MeshSchema(
  rootTagName: "thread",
  elements: [
    ElementType(
      tagName: "thread",
      description: "",
      properties: [
        ChildProperty(name: "children", description: "", childTagNames: ["messages", "members"]),
      ],
    ),
    ElementType(
      tagName: "messages",
      description: "",
      properties: [
        ChildProperty(name: "children", description: "", childTagNames: ["message", "reasoning", "event", "exec"]),
      ],
    ),
    ElementType(
      tagName: "members",
      description: "",
      properties: [
        ChildProperty(name: "children", description: "", childTagNames: ["member"]),
      ],
    ),
    ElementType(
      tagName: "member",
      description: "",
      properties: [ValueProperty(name: "name", description: "", type: SimpleValue.string)],
    ),
    ElementType(
      tagName: "message",
      description: "",
      properties: [
        ValueProperty(name: "text", description: "", type: SimpleValue.string),
        ValueProperty(name: "author_name", description: "", type: SimpleValue.string),
        ValueProperty(name: "role", description: "", type: SimpleValue.string),
        ChildProperty(name: "children", description: "", childTagNames: ["file", "image"]),
      ],
    ),
    ElementType(
      tagName: "file",
      description: "",
      properties: [ValueProperty(name: "path", description: "", type: SimpleValue.string)],
    ),
    ElementType(
      tagName: "image",
      description: "",
      properties: [ValueProperty(name: "path", description: "", type: SimpleValue.string)],
    ),
    ElementType(
      tagName: "reasoning",
      description: "",
      properties: [ValueProperty(name: "summary", description: "", type: SimpleValue.string)],
    ),
    ElementType(
      tagName: "event",
      description: "",
      properties: [
        ValueProperty(name: "kind", description: "", type: SimpleValue.string),
        ValueProperty(name: "state", description: "", type: SimpleValue.string),
        ValueProperty(name: "item_type", description: "", type: SimpleValue.string),
        ValueProperty(name: "method", description: "", type: SimpleValue.string),
        ValueProperty(name: "summary", description: "", type: SimpleValue.string),
        ValueProperty(name: "headline", description: "", type: SimpleValue.string),
        ValueProperty(name: "details", description: "", type: SimpleValue.string),
      ],
    ),
    ElementType(
      tagName: "exec",
      description: "",
      properties: [
        ValueProperty(name: "command", description: "", type: SimpleValue.string),
        ValueProperty(name: "stdout", description: "", type: SimpleValue.string),
        ValueProperty(name: "stderr", description: "", type: SimpleValue.string),
      ],
    ),
  ],
);

MeshDocument _createThreadDocument() {
  final document = MeshDocument(schema: _threadSchema, sendChangesToBackend: (_) {});
  _insertElement(document: document, targetId: null, tagName: "messages", elementId: "messages");
  return document;
}

MeshElement _messagesElement(MeshDocument document) {
  return document.root.getChildren().whereType<MeshElement>().firstWhere((child) => child.tagName == "messages");
}

void _insertElement({
  required MeshDocument document,
  required String? targetId,
  required String tagName,
  required String elementId,
  Map<String, dynamic> attributes = const {},
  List<Map<String, dynamic>> children = const [],
}) {
  document.receiveChanges({
    if (targetId == null) "root": true else "target": targetId,
    "elements": [
      {
        "insert": [
          {
            "element": {
              "tagName": tagName,
              "attributes": {"\$id": elementId, ...attributes},
              "children": children,
            },
          },
        ],
      },
    ],
    "attributes": {"set": const [], "delete": const []},
  });
}

Widget _buildThreadHarness({
  required RoomClient room,
  required ChatThreadController controller,
  required MeshDocument document,
  bool shouldShowAuthorNames = true,
  bool showCompletedToolCalls = false,
  bool showTyping = false,
  String? threadStatus,
  DateTime? threadStatusStartedAt,
  String? threadStatusMode,
  List<PendingAgentMessage> pendingMessages = const [],
}) {
  return ShadApp(
    home: Scaffold(
      body: Column(
        children: [
          ChatThreadMessages(
            room: room,
            path: "/threads/test",
            scrollController: controller.threadScrollController,
            messages: _messagesElement(document).getChildren().whereType<MeshElement>().toList(),
            online: const [],
            showCompletedToolCalls: showCompletedToolCalls,
            shouldShowAuthorNames: shouldShowAuthorNames,
            startChatCentered: true,
            showTyping: showTyping,
            threadStatus: threadStatus,
            threadStatusStartedAt: threadStatusStartedAt,
            threadStatusMode: threadStatusMode,
            pendingMessages: pendingMessages,
            emptyStateTitle: "No visible messages",
          ),
          ChatThreadInputFrame(
            child: ChatThreadInput(room: room, controller: controller, readOnly: true, onSend: (value, attachments) async {}),
          ),
        ],
      ),
    ),
  );
}

void main() {
  final previousRuntime = DocumentRuntime.instance;
  final previousVisibilityUpdateInterval = VisibilityDetectorController.instance.updateInterval;

  setUpAll(() {
    DocumentRuntime.instance = _FakeDocumentRuntime();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDownAll(() {
    if (previousRuntime != null) {
      DocumentRuntime.instance = previousRuntime;
    }
    VisibilityDetectorController.instance.updateInterval = previousVisibilityUpdateInterval;
  });

  testWidgets('filters empty standard messages from the thread display without showing an empty state', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-empty",
      attributes: {"text": "   ", "author_name": "assistant", "role": "agent"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("No visible messages"), findsNothing);
    expect(find.byType(ChatThreadEmptyStateContent), findsNothing);
  });

  testWidgets('keeps non-empty messages visible when empty ones are present', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    final messages = _messagesElement(document);
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-empty",
      attributes: {"text": "", "author_name": "assistant", "role": "agent"},
    );
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"text": "hello", "author_name": "assistant", "role": "agent"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text("hello"), findsOneWidget);
    expect(find.text("No visible messages"), findsNothing);
  });

  testWidgets('shows author headers for consecutive messages by default', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    final messages = _messagesElement(document);
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-one",
      attributes: {"text": "hello", "author_name": "assistant", "role": "agent"},
    );
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-two",
      attributes: {"text": "again", "author_name": "assistant", "role": "agent"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.text("assistant"), findsNWidgets(2));
  });

  testWidgets('can hide author headers explicitly', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-one",
      attributes: {"text": "hello", "author_name": "assistant", "role": "agent"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document, shouldShowAuthorNames: false));
    await tester.pump();

    expect(find.text("assistant"), findsNothing);
  });

  testWidgets('does not render standard messages until author name and role are present', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    final messages = _messagesElement(document);
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-no-role",
      attributes: {"text": "missing role", "author_name": "assistant"},
    );
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-no-name",
      attributes: {"text": "missing name", "role": "agent"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.text("missing role"), findsNothing);
    expect(find.text("missing name"), findsNothing);
    expect(find.byType(ChatBubble), findsNothing);
  });

  testWidgets('hides in-progress tool call events when tool calls are disabled', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "event",
      elementId: "tool-call-running",
      attributes: {
        "kind": "tool",
        "state": "in_progress",
        "item_type": "function_call",
        "method": "tool.started",
        "summary": "Calling Tool: weather",
        "headline": "Calling Tool: weather",
        "details": "Tool: weather",
      },
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.text("Calling Tool: weather"), findsNothing);
    expect(find.text("Tool: weather"), findsNothing);

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document, showCompletedToolCalls: true));
    await tester.pump();

    expect(find.text("Calling Tool: weather"), findsOneWidget);
  });

  testWidgets('hides preparing tool events without item type when tool calls are disabled', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "event",
      elementId: "tool-call-preparing",
      attributes: {
        "kind": "tool",
        "state": "queued",
        "method": "response.output_item.added",
        "summary": "Preparing Tool Call",
        "headline": "Preparing Tool Call",
        "details": "Preparing search",
      },
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.text("Preparing Tool Call"), findsNothing);
    expect(find.text("Preparing search"), findsNothing);

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document, showCompletedToolCalls: true));
    await tester.pump();

    expect(find.text("Preparing Tool Call"), findsOneWidget);
  });

  testWidgets('hides shell call events when tool calls are disabled', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "event",
      elementId: "shell-call-running",
      attributes: {
        "kind": "exec",
        "state": "in_progress",
        "item_type": "shell_call",
        "method": "response.shell_call",
        "summary": "Running Command",
        "headline": "Running Command",
        "details": "Shell: pwd",
      },
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.text("Running Command"), findsNothing);
    expect(find.text("Shell: pwd"), findsNothing);
  });

  testWidgets('hides exec elements when tool calls are disabled', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "exec",
      elementId: "exec-running",
      attributes: {"command": "echo hidden", "stdout": "hidden output"},
    );

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.textContaining("echo hidden"), findsNothing);
    expect(find.textContaining("hidden output"), findsNothing);
  });

  testWidgets('renders pending turn start messages in the feed', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "optimistic hello",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(PendingChatThreadMessage), findsOneWidget);
    expect(find.text("optimistic hello"), findsOneWidget);
  });

  testWidgets('does not optimistically render pending steer messages in the feed', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Writing",
        threadStatusMode: "steerable",
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-steer-1",
            messageType: "meshagent.agent.turn.steer",
            threadPath: "/threads/test",
            text: "queued steer",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("queued steer"), findsNothing);
  });

  test('marks pending steer messages after application events', () async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    controller.notifyOnSend = false;
    await controller.send(
      thread: document,
      path: "/threads/test",
      message: const ChatMessage(id: "pending-steer-1", text: "translate to spanish"),
      messageType: "steer",
      storeLocally: false,
      useAgentMessages: true,
      turnId: "turn-1",
    );

    expect(controller.pendingAgentMessages.single.awaitingAcceptance, isTrue);
    expect(controller.pendingAgentMessages.single.awaitingApplication, isTrue);

    controller.handleAgentMessagePayload({
      "type": "meshagent.agent.turn.steer.accepted",
      "thread_id": "/threads/test",
      "turn_id": "turn-1",
      "source_message_id": "pending-steer-1",
    });

    expect(controller.pendingAgentMessages.single.awaitingAcceptance, isFalse);
    expect(controller.pendingAgentMessages.single.awaitingApplication, isTrue);
    expect(controller.pendingAgentMessages.single.text, "translate to spanish");

    controller.handleAgentMessagePayload({
      "type": "meshagent.agent.turn.steered",
      "thread_id": "/threads/test",
      "turn_id": "turn-1",
      "source_message_id": "pending-steer-1",
    });

    expect(controller.pendingAgentMessages, isEmpty);
  });

  testWidgets('does not render matching thread messages while pending application', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"id": "pending-steer-1", "text": "queued steer", "author_name": "user", "role": "user"},
    );

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-steer-1",
            messageType: "meshagent.agent.turn.steer",
            threadPath: "/threads/test",
            text: "queued steer",
            attachments: [],
            awaitingApplication: true,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("queued steer"), findsNothing);
  });

  testWidgets('renders turn start messages once the real message is visible', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"id": "pending-1", "text": "optimistic hello", "author_name": "user", "role": "user"},
    );

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "optimistic hello",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text("optimistic hello"), findsOneWidget);
  });

  testWidgets('does not render new thread first-message pending rows before matching content is visible', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-new-thread-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "first new thread message",
            attachments: [],
            matchByContentOnly: true,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("first new thread message"), findsNothing);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"text": "first new thread message", "author_name": "user", "role": "user"},
    );

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-new-thread-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "first new thread message",
            attachments: [],
            matchByContentOnly: true,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text("first new thread message"), findsOneWidget);
  });

  testWidgets('does not render pending messages when the real message text is incomplete', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"id": "pending-1", "text": "", "author_name": "user", "role": "user"},
    );

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "optimistic hello",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text("optimistic hello"), findsNothing);
  });

  testWidgets('renders pending turn starts in the feed while the agent is processing', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Working",
        threadStatusMode: "busy",
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "optimistic hello",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(PendingChatThreadMessage), findsOneWidget);
    expect(find.text("optimistic hello"), findsOneWidget);
  });

  testWidgets('does not render pending turn starts when matching server messages are not renderable', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-pending-incomplete",
      attributes: {"id": "pending-1", "text": "optimistic hello", "author_name": "user"},
    );

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Working",
        threadStatusMode: "busy",
        pendingMessages: const [
          PendingAgentMessage(
            messageId: "pending-1",
            messageType: "meshagent.agent.turn.start",
            threadPath: "/threads/test",
            text: "optimistic hello",
            attachments: [],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("optimistic hello"), findsNothing);
  });

  testWidgets('animates the processing status spacer when status appears', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    const spacerKey = ValueKey("chat-thread-status-bottom-spacer");

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Working",
        threadStatusMode: "busy",
      ),
    );

    expect(tester.getSize(find.byKey(spacerKey)).height, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final midAnimationHeight = tester.getSize(find.byKey(spacerKey)).height;
    expect(midAnimationHeight, greaterThan(0));
    expect(midAnimationHeight, lessThan(20));

    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.getSize(find.byKey(spacerKey)).height, 20);
  });

  testWidgets('keeps the processing status row visible briefly after status clears', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Working",
        threadStatusMode: "busy",
      ),
    );
    await tester.pump();

    expect(find.byType(ChatThreadProcessingStatusRow), findsOneWidget);
    expect(find.text("Working"), findsWidgets);

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump();

    expect(find.byType(ChatThreadProcessingStatusRow), findsOneWidget);
    expect(find.text("Working"), findsWidgets);

    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byType(ChatThreadProcessingStatusRow), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ChatThreadProcessingStatusRow), findsNothing);
  });

  testWidgets('does not render a processing status row for mode-only thread status', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    final status = ChatThreadStatusState(mode: 'busy', turnId: 'turn-1');

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: shouldShowChatThreadStatus(status),
        threadStatus: status.text,
        threadStatusMode: status.mode,
      ),
    );
    await tester.pump();

    expect(find.byType(ChatThreadProcessingStatusRow), findsNothing);
    expect(find.text('Thinking'), findsNothing);
  });

  testWidgets('cancels delayed processing status collapse when status returns', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(controller.dispose);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Working",
        threadStatusMode: "busy",
      ),
    );
    await tester.pump();

    await tester.pumpWidget(_buildThreadHarness(room: room, controller: controller, document: document));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(
      _buildThreadHarness(
        room: room,
        controller: controller,
        document: document,
        showTyping: true,
        threadStatus: "Still working",
        threadStatusMode: "busy",
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChatThreadProcessingStatusRow), findsOneWidget);
    expect(find.text("Still working"), findsWidgets);
  });

  testWidgets('renders tool footers below the thread composer', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    final controller = ChatThreadController(room: room);
    addTearDown(room.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.shrink()),
              ChatThreadInputFrame(
                child: ChatThreadInput(
                  room: room,
                  controller: controller,
                  leading: const Text("Attach"),
                  footer: const Text("MCP footer"),
                  onSend: (value, attachments) async {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Attach"), findsOneWidget);
    expect(find.text("MCP footer"), findsOneWidget);
  });
}
