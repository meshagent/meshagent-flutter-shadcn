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
        ChildProperty(name: "children", description: "", childTagNames: ["message", "reasoning", "event"]),
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

  testWidgets('filters empty standard messages from the thread display', (tester) async {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(document.dispose);

    _insertElement(
      document: document,
      targetId: _messagesElement(document).id,
      tagName: "message",
      elementId: "message-empty",
      attributes: {"text": "   ", "author_name": "assistant"},
    );

    var emptyCallbackCount = 0;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatThread(
              path: "/threads/test",
              document: document,
              room: room,
              startChatCentered: true,
              emptyStateTitle: "No visible messages",
              onVisibleMessagesEmpty: () {
                emptyCallbackCount += 1;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text("No visible messages"), findsOneWidget);
    expect(emptyCallbackCount, 1);
  });

  testWidgets('keeps non-empty messages visible when empty ones are present', (tester) async {
    final room = RoomClient(protocol: Protocol(channel: _NoopProtocolChannel()));
    final document = _createThreadDocument();
    addTearDown(room.dispose);
    addTearDown(document.dispose);

    final messages = _messagesElement(document);
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-empty",
      attributes: {"text": "", "author_name": "assistant"},
    );
    _insertElement(
      document: document,
      targetId: messages.id,
      tagName: "message",
      elementId: "message-visible",
      attributes: {"text": "hello", "author_name": "assistant"},
    );

    var emptyCallbackCount = 0;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatThread(
              path: "/threads/test",
              document: document,
              room: room,
              startChatCentered: true,
              emptyStateTitle: "No visible messages",
              onVisibleMessagesEmpty: () {
                emptyCallbackCount += 1;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text("hello"), findsOneWidget);
    expect(find.text("No visible messages"), findsNothing);
    expect(emptyCallbackCount, 0);
  });
}
