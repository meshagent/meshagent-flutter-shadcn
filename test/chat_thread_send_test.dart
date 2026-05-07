import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent/runtime.dart';

class _ProtocolPair {
  _ProtocolPair() {
    serverProtocol = Protocol(
      channel: StreamProtocolChannel(input: _clientToServer.stream, output: _serverToClient.sink),
    );
  }

  final _clientToServer = StreamController<Uint8List>();
  final _serverToClient = StreamController<Uint8List>();
  Protocol? _clientProtocol;
  late final Protocol serverProtocol;

  Protocol clientProtocolFactory() {
    final existing = _clientProtocol;
    if (existing != null) {
      throw ProtocolReconnectUnsupportedException('protocolFactory was not configured for reconnecting this protocol');
    }
    final protocol = Protocol(
      channel: StreamProtocolChannel(input: _serverToClient.stream, output: _clientToServer.sink),
    );
    _clientProtocol = protocol;
    return protocol;
  }

  Future<void> dispose() async {
    final clientProtocol = _clientProtocol;
    if (clientProtocol != null) {
      try {
        clientProtocol.dispose();
      } catch (_) {}
    }
    try {
      serverProtocol.dispose();
    } catch (_) {}
    await _clientToServer.close();
    if (!_serverToClient.isClosed) {
      await _serverToClient.close();
    }
  }
}

Future<void> _sendRoomReady(Protocol protocol) async {
  await protocol.send(
    'room_ready',
    packMessage({'room_name': 'test-room', 'room_url': 'ws://example/rooms/test-room', 'session_id': 'session-1'}),
  );
  await protocol.send(
    'connected',
    packMessage({
      'type': 'init',
      'participantId': 'self',
      'attributes': {'name': 'self'},
    }),
  );
}

class _RecordedRequest {
  _RecordedRequest({required this.tool, required this.input});

  final String tool;
  final Map<String, dynamic> input;
}

class _MessagingHarness {
  _MessagingHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeMessagingServer server;

  Future<void> dispose() async {
    room.dispose();
    await pair.dispose();
  }
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

class _FakeMessagingServer {
  final requests = <_RecordedRequest>[];

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type != 'room.invoke_tool') {
      return;
    }

    final message = unpackMessage(data);
    final request = message.header;
    if (request['toolkit'] != 'messaging') {
      return;
    }

    final tool = request['tool'] as String;
    final input = _decodeInput(message: message, request: request);
    if (input is! JsonContent) {
      throw StateError('messaging.$tool expected JsonContent input');
    }

    requests.add(_RecordedRequest(tool: tool, input: Map<String, dynamic>.from(input.json)));

    switch (tool) {
      case 'enable':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        await protocol.send(
          'messaging.send',
          packMessage({
            'from_participant_id': 'local-participant',
            'type': 'messaging.enabled',
            'message': {
              'participants': [
                {
                  'id': 'remote-1',
                  'role': 'member',
                  'attributes': {'name': 'assistant'},
                },
              ],
            },
          }),
        );
        return;
      case 'send':
        await protocol.send('__response__', EmptyContent().pack(), id: messageId);
        return;
      default:
        throw StateError('unsupported messaging operation: $tool');
    }
  }

  Future<void> sendParticipantAttributes(Protocol protocol, Map<String, dynamic> attributes) async {
    await protocol.send(
      'messaging.send',
      packMessage({
        'from_participant_id': 'remote-1',
        'type': 'participant.attributes',
        'message': {'attributes': attributes},
      }),
    );
  }

  Future<void> sendAgentMessage(Protocol protocol, Map<String, dynamic> payload) async {
    await protocol.send(
      'messaging.send',
      packMessage({
        'from_participant_id': 'remote-1',
        'type': 'agent-message',
        'message': {'payload': payload},
      }),
    );
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }
}

Future<_MessagingHarness> _startMessagingHarness() async {
  final pair = _ProtocolPair();
  final server = _FakeMessagingServer();
  pair.serverProtocol.start(onMessage: server.handleMessage);

  final room = RoomClient(protocolFactory: pair.clientProtocolFactory);
  final startFuture = room.start();
  await _sendRoomReady(pair.serverProtocol);
  await startFuture;

  return _MessagingHarness(pair: pair, room: room, server: server);
}

Future<void> _waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 1)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final MeshSchema _threadSchema = MeshSchema(
  rootTagName: 'thread',
  elements: [
    ElementType(
      tagName: 'thread',
      description: '',
      properties: [
        ChildProperty(name: 'children', description: '', childTagNames: ['messages', 'members']),
      ],
    ),
    ElementType(
      tagName: 'messages',
      description: '',
      properties: [
        ChildProperty(name: 'children', description: '', childTagNames: ['message']),
      ],
    ),
    ElementType(
      tagName: 'members',
      description: '',
      properties: [
        ChildProperty(name: 'children', description: '', childTagNames: ['member']),
      ],
    ),
    ElementType(
      tagName: 'member',
      description: '',
      properties: [ValueProperty(name: 'name', description: '', type: SimpleValue.string)],
    ),
    ElementType(
      tagName: 'message',
      description: '',
      properties: [
        ValueProperty(name: 'text', description: '', type: SimpleValue.string),
        ValueProperty(name: 'author_name', description: '', type: SimpleValue.string),
      ],
    ),
  ],
);

MeshDocument _createThreadDocument() {
  final document = MeshDocument(schema: _threadSchema, sendChangesToBackend: (_) {});
  _insertElement(document: document, targetId: null, tagName: 'messages', elementId: 'messages');
  _insertElement(document: document, targetId: null, tagName: 'members', elementId: 'members');
  return document;
}

MeshElement _membersElement(MeshDocument document) {
  return document.root.getChildren().whereType<MeshElement>().firstWhere((child) => child.tagName == 'members');
}

void _insertElement({
  required MeshDocument document,
  required String? targetId,
  required String tagName,
  required String elementId,
  Map<String, dynamic> attributes = const {},
}) {
  document.receiveChanges({
    if (targetId == null) 'root': true else 'target': targetId,
    'elements': [
      {
        'insert': [
          {
            'element': {
              'tagName': tagName,
              'attributes': {'\$id': elementId, ...attributes},
            },
          },
        ],
      },
    ],
    'attributes': {'set': const [], 'delete': const []},
  });
}

void main() {
  final previousRuntime = DocumentRuntime.instance;

  setUpAll(() {
    DocumentRuntime.instance = _FakeDocumentRuntime();
  });

  tearDownAll(() {
    if (previousRuntime != null) {
      DocumentRuntime.instance = previousRuntime;
    }
  });

  test('ChatThreadController.send deduplicates recipients for duplicate thread members', () async {
    final harness = await _startMessagingHarness();
    final controller = ChatThreadController(room: harness.room);
    final document = _createThreadDocument();

    addTearDown(controller.dispose);
    addTearDown(document.dispose);
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    final members = _membersElement(document);
    _insertElement(document: document, targetId: members.id, tagName: 'member', elementId: 'member-1', attributes: {'name': 'assistant'});
    _insertElement(document: document, targetId: members.id, tagName: 'member', elementId: 'member-2', attributes: {'name': 'assistant'});

    await controller.send(
      thread: document,
      path: '/threads/test.thread',
      message: const ChatMessage(id: 'message-1', text: 'hello'),
      remoteStoreParticipantName: 'assistant',
      storeLocally: false,
    );

    expect(harness.server.requests.map((request) => request.tool).toList(), ['enable', 'send']);
    expect(harness.server.requests.where((request) => request.tool == 'send'), hasLength(1));
    expect(harness.server.requests.last.input['to_participant_id'], 'remote-1');
  });

  test('resolveChatThreadStatus reads the exact dataset thread path', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    await harness.server.sendParticipantAttributes(harness.pair.serverProtocol, {
      'thread.status.text.$threadPath': 'Generating image',
      'thread.status.mode.$threadPath': 'busy',
      'thread.status.started_at.$threadPath': '2026-05-04T12:00:00Z',
      'thread.status.pending_item_id.$threadPath': 'image-1',
    });
    await _waitUntil(
      () => harness.room.messaging.remoteParticipants.first.getAttribute('thread.status.text.$threadPath') == 'Generating image',
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Generating image');
    expect(state.mode, 'busy');
    expect(state.pendingItemId, 'image-1');
    expect(state.startedAt, DateTime.parse('2026-05-04T12:00:00Z'));
  });

  test('resolveChatThreadStatus preserves active turn without visible status text', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    await harness.server.sendParticipantAttributes(harness.pair.serverProtocol, {
      'supports_agent_messages': true,
      'thread.status.pending_messages.$threadPath': jsonEncode({
        'turn_id': 'turn-1',
        'messages': [
          {
            'message_id': 'message-1',
            'message_type': 'meshagent.agent.turn.steer',
            'sender_name': 'self',
            'created_at': '2026-05-04T12:00:00Z',
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
          },
        ],
      }),
    });
    await _waitUntil(
      () => harness.room.messaging.remoteParticipants.first.getAttribute('thread.status.pending_messages.$threadPath') != null,
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, isNull);
    expect(state.turnId, 'turn-1');
    expect(state.pendingMessages, hasLength(1));
    expect(state.pendingMessages.single.text, 'hello');
    expect(state.supportsAgentMessages, isTrue);
  });

  test('resolveChatThreadStatus does not require supports agent messages when agent name is omitted', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    await harness.server.sendParticipantAttributes(harness.pair.serverProtocol, {
      'thread.status.text.$threadPath': 'Generating image',
      'thread.status.mode.$threadPath': 'busy',
    });
    await _waitUntil(
      () => harness.room.messaging.remoteParticipants.first.getAttribute('thread.status.text.$threadPath') == 'Generating image',
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath);

    expect(state.text, 'Generating image');
    expect(state.mode, 'busy');
  });

  test('agent-message usage payload is observable and parseable on the Dart room event stream', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    AgentUsageSnapshot? latestUsage;
    final subscription = harness.room.listen((event) {
      if (event is! RoomMessageEvent || event.message.type != 'agent-message') {
        return;
      }
      final payload = event.message.message['payload'];
      if (payload is Map<String, dynamic>) {
        latestUsage = AgentUsageSnapshot.fromPayload(payload);
      } else if (payload is Map) {
        latestUsage = AgentUsageSnapshot.fromPayload(Map<String, dynamic>.from(payload));
      }
    });
    addTearDown(subscription.cancel);

    await harness.server.sendAgentMessage(harness.pair.serverProtocol, {
      'type': 'meshagent.agent.usage.updated',
      'thread_id': '/threads/test.thread',
      'message_id': 'usage-1',
      'turn_id': 'turn-1',
      'usage': {'input_tokens': 120.0, 'output_tokens': 30.0},
      'context_window': {'used_tokens': 480, 'total_tokens': 128000},
    });
    await _waitUntil(() => latestUsage != null);

    final usage = latestUsage;
    expect(usage, isNotNull);
    expect(usage!.threadPath, '/threads/test.thread');
    expect(usage.turnId, 'turn-1');
    expect(usage.contextUsedTokens, 480);
    expect(usage.contextTotalTokens, 128000);
    expect(usage.totalTokens, 150);
  });
}
