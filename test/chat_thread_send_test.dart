import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/agent_stream_accumulator.dart';
import 'package:meshagent_flutter_shadcn/chat/tool_call_status_accumulator.dart';
import 'package:meshagent/runtime.dart';

void _expectRecentStartedAt(DateTime? startedAt) {
  expect(startedAt, isNotNull);
  final elapsed = DateTime.now().difference(startedAt!);
  expect(elapsed.inSeconds.abs(), lessThan(5));
}

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

  test('resolveChatThreadStatus reads status messages for the exact dataset thread path', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'image-1',
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Generating image');
    expect(state.mode, 'busy');
    expect(state.pendingItemId, 'image-1');
    expect(state.totalBytes, isNull);
    _expectRecentStartedAt(state.startedAt);
  });

  test('resolveChatThreadStatusFromStore reads websocket status without a room', () async {
    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    final store = AgentThreadMessageStatusStore();
    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Working',
        'mode': 'busy',
        'turn_id': 'turn-1',
      }),
    );

    final state = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    expect(state.text, 'Working');
    expect(state.mode, 'busy');
    expect(state.turnId, 'turn-1');
    expect(state.supportsAgentMessages, isTrue);
  });

  test('resolveChatThreadStatus ignores stale participant status attributes', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    await harness.room.messaging.enable();
    await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    await harness.server.sendParticipantAttributes(harness.pair.serverProtocol, {
      'thread.status.text.$threadPath': 'Old attribute status',
      'thread.status.mode.$threadPath': 'busy',
      'thread.status.pending_item_id.$threadPath': 'old-item',
    });
    await _waitUntil(
      () => harness.room.messaging.remoteParticipants.first.getAttribute('thread.status.text.$threadPath') == 'Old attribute status',
    );

    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'steerable',
        'started_at': '2026-05-04T12:00:00Z',
        'turn_id': 'turn-1',
        'pending_item_id': 'image-1',
        'total_bytes': 240,
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Generating image');
    expect(state.mode, 'steerable');
    expect(state.turnId, 'turn-1');
    expect(state.totalBytes, 240);
    expect(state.pendingItemId, 'image-1');
    _expectRecentStartedAt(state.startedAt);
    expect(state.supportsAgentMessages, isTrue);
  });

  test('resolveChatThreadStatusFromStore preserves startedAt for the same status operation', () {
    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    final store = AgentThreadMessageStatusStore();
    final currentStartedAt = DateTime.now().toUtc().toIso8601String();
    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': currentStartedAt,
        'turn_id': 'turn-1',
        'pending_item_id': 'image-1',
      }),
    );
    final first = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': DateTime.now().add(const Duration(seconds: 1)).toUtc().toIso8601String(),
        'turn_id': 'turn-1',
        'pending_item_id': 'image-1',
      }),
    );
    final second = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    expect(second.startedAt, first.startedAt);
  });

  test('resolveChatThreadStatusFromStore resets startedAt for a different turn status', () {
    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    final store = AgentThreadMessageStatusStore();
    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'turn_id': 'turn-1',
        'pending_item_id': 'image-1',
      }),
    );
    final first = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': DateTime.now().add(const Duration(seconds: 1)).toUtc().toIso8601String(),
        'turn_id': 'turn-2',
        'pending_item_id': 'image-1',
      }),
    );
    final second = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    expect(second.startedAt, isNot(first.startedAt));
    _expectRecentStartedAt(second.startedAt);
  });

  test('resolveChatThreadStatusFromStore clamps skewed remote startedAt', () {
    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    final store = AgentThreadMessageStatusStore();
    trackAgentThreadStatusMessageInStore(
      store: store,
      message: AgentMessage.fromJson({
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Generating image',
        'mode': 'busy',
        'started_at': DateTime.now().subtract(const Duration(minutes: 10)).toUtc().toIso8601String(),
        'turn_id': 'turn-1',
        'pending_item_id': 'image-1',
      }),
    );

    final state = resolveChatThreadStatusFromStore(store: store, path: threadPath);

    _expectRecentStartedAt(state.startedAt);
  });

  test('resolveChatThreadStatus stays clear when only stale attributes remain', () async {
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

    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.thread.status', 'thread_id': threadPath, 'status': 'Generating image', 'mode': 'busy'},
    );
    final changed = trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': null,
        'mode': null,
        'started_at': null,
        'turn_id': null,
      },
    );
    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(changed, isTrue);
    expect(state.text, isNull);
    expect(state.hasStatus, isFalse);
    expect(state.supportsAgentMessages, isTrue);
  });

  test('resolveChatThreadStatus computes status bytes from tool argument deltas', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Preparing Command',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'shell-1',
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.arguments_delta',
        'thread_id': threadPath,
        'item_id': 'shell-1',
        'delta': List.filled(120, 'x').join(),
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Preparing Command');
    expect(state.totalBytes, 120);
    expect(
      formatChatThreadStatusText(state.text!, startedAt: state.startedAt, totalBytes: state.totalBytes),
      'Preparing Command 120 bytes',
    );
  });

  test('resolveChatThreadStatus computes status bytes from deltas before status', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.arguments_delta',
        'thread_id': threadPath,
        'item_id': 'shell-1',
        'delta': List.filled(120, 'x').join(),
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Preparing Command',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'shell-1',
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Preparing Command');
    expect(state.totalBytes, 120);
    expect(
      formatChatThreadStatusText(state.text!, startedAt: state.startedAt, totalBytes: state.totalBytes),
      'Preparing Command 120 bytes',
    );
  });

  test('resolveChatThreadStatus reads patch line counters from status messages', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Editing app.ts',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'patch-1',
        'lines_added': 100,
        'lines_removed': 10,
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Editing app.ts');
    expect(state.linesAdded, 100);
    expect(state.linesRemoved, 10);
    expect(
      formatChatThreadStatusText(state.text!, startedAt: state.startedAt, linesAdded: state.linesAdded, linesRemoved: state.linesRemoved),
      'Editing app.ts +100 -10',
    );
  });

  test('resolveChatThreadStatus derives patch line counters from live argument deltas', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Preparing',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'pending-placeholder',
        'total_bytes': 270,
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.arguments_delta',
        'thread_id': threadPath,
        'item_id': 'patch-1',
        'delta': '*** Begin Patch\n*** Update File: app.ts\n@@\n-old\n+new\n',
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.arguments_delta',
        'thread_id': threadPath,
        'item_id': 'patch-1',
        'delta': '${List.filled(260, '+x\n').join()}*** End Patch\n',
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Editing app.ts');
    expect(state.totalBytes, greaterThan(270));
    expect(state.linesAdded, 261);
    expect(state.linesRemoved, 1);
    expect(
      formatChatThreadStatusText(state.text!, startedAt: state.startedAt, linesAdded: state.linesAdded, linesRemoved: state.linesRemoved),
      'Editing app.ts +261 -1',
    );
  });

  test('resolveChatThreadStatus joins OpenAI apply patch operation args with lean deltas', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.thread.status',
        'thread_id': threadPath,
        'status': 'Preparing',
        'mode': 'busy',
        'started_at': '2026-05-04T12:00:00Z',
        'pending_item_id': 'pending-placeholder',
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.arguments_delta',
        'thread_id': threadPath,
        'item_id': 'patch-1',
        'delta': '@@\n-old\n+new\n+extra\n',
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.tool_call.started',
        'thread_id': threadPath,
        'item_id': 'patch-1',
        'toolkit': 'openai',
        'tool': 'apply_patch',
        'arguments': {
          'operation': {'type': 'update_file', 'path': 'report.py', 'diff': '@@\n-old\n+new\n+extra\n'},
        },
      },
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.text, 'Editing report.py');
    expect(state.linesAdded, 2);
    expect(state.linesRemoved, 1);
    expect(state.pendingItemId, 'patch-1');
  });

  test('LiveToolCallAccumulator joins lean apply patch deltas with lifecycle arguments', () {
    final accumulator = LiveToolCallAccumulator();

    final deltaSnapshot = accumulator.appendDelta(itemId: 'patch-1', fallbackText: 'Preparing', delta: '@@\n-old\n+new\n+extra\n');
    expect(deltaSnapshot.text, 'Applying patch');
    expect(deltaSnapshot.linesAdded, 2);
    expect(deltaSnapshot.linesRemoved, 1);
    expect(deltaSnapshot.totalBytes, greaterThan(0));

    final lifecycleSnapshot = accumulator.upsert(
      itemId: 'patch-1',
      tool: 'apply_patch',
      fallbackText: 'Preparing',
      arguments: {
        'operation': {'type': 'update_file', 'path': 'report.py', 'diff': '@@\n-old\n+new\n+extra\n'},
      },
    );

    expect(lifecycleSnapshot.text, 'Editing report.py');
    expect(lifecycleSnapshot.linesAdded, 2);
    expect(lifecycleSnapshot.linesRemoved, 1);
    expect(lifecycleSnapshot.totalBytes, deltaSnapshot.totalBytes);
    final completed = accumulator.complete(itemId: 'patch-1');
    expect(completed?.status, 'completed');
  });

  test('LiveToolCallAccumulator keeps apply patch text stable before path arrives', () {
    final accumulator = LiveToolCallAccumulator();

    final started = accumulator.upsert(itemId: 'patch-1', tool: 'apply_patch', arguments: {}, fallbackText: 'Preparing');
    expect(started.text, 'Applying patch');

    final partialPatch = accumulator.appendDelta(itemId: 'patch-1', fallbackText: 'Preparing report', delta: '@@\n-old\n+new\n');
    expect(partialPatch.text, 'Applying patch');
    expect(partialPatch.linesAdded, 1);
    expect(partialPatch.linesRemoved, 1);

    final withPath = accumulator.appendDelta(itemId: 'patch-1', fallbackText: 'Preparing report', delta: '*** Update File: report.py\n');
    expect(withPath.text, 'Editing report.py');
  });

  test('LiveToolCallAccumulator summarizes Codex diff tool calls', () {
    final accumulator = LiveToolCallAccumulator();
    const diff = '''
diff --git a/report.py b/report.py
--- a/report.py
+++ b/report.py
@@
-old
+new
+extra
''';

    final snapshot = accumulator.upsert(itemId: 'diff-1', tool: 'diff_updated', arguments: {'diff': diff}, fallbackText: 'Updating diff');

    expect(snapshot.text, 'Editing report.py');
    expect(snapshot.linesAdded, 2);
    expect(snapshot.linesRemoved, 1);
  });

  test('stream accumulators expose in progress and completed status', () {
    final text = TextStreamAccumulator();
    final firstText = text.appendDelta(itemId: 'msg-1', delta: 'hello');
    expect(firstText.status, 'in_progress');
    expect(firstText.text, 'hello');
    final completedText = text.complete('msg-1');
    expect(completedText?.status, 'completed');

    final file = FileStreamAccumulator();
    final firstFile = file.appendUrl(itemId: 'file-1', url: 'mesh://one');
    expect(firstFile.status, 'in_progress');
    expect(firstFile.latestUrl, 'mesh://one');
    final completedFile = file.complete('file-1');
    expect(completedFile?.status, 'completed');
    expect(completedFile?.urls, <String>['mesh://one']);
  });

  test('resolveChatThreadStatus tracks accepted pending messages until applied', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = '/threads/test.thread';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.turn.start',
        'thread_id': threadPath,
        'message_id': 'message-1',
        'sender_name': 'sender',
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.turn.start.accepted', 'thread_id': threadPath, 'source_message_id': 'message-1'},
    );

    final pendingState = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(pendingState.pendingMessages, hasLength(1));
    expect(pendingState.pendingMessages.single.messageId, 'message-1');
    expect(pendingState.pendingMessages.single.text, 'hello');
    expect(pendingState.pendingMessages.single.awaitingAcceptance, isFalse);
    expect(pendingState.pendingMessages.single.awaitingApplication, isTrue);
    expect(pendingState.supportsAgentMessages, isTrue);

    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.turn.started', 'thread_id': threadPath, 'turn_id': 'turn-1', 'source_message_id': 'message-1'},
    );

    final appliedState = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(appliedState.pendingMessages, hasLength(1));
    expect(appliedState.pendingMessages.single.awaitingApplication, isFalse);
    expect(appliedState.turnId, 'turn-1');
    expect(appliedState.supportsAgentMessages, isTrue);
  });

  test('resolveChatThreadStatus ignores accepted messages with no known input content', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = '/threads/test.thread';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.turn.start.accepted', 'thread_id': threadPath, 'source_message_id': 'audio-message-1'},
    );

    final state = resolveChatThreadStatus(room: harness.room, path: threadPath, agentName: 'assistant');

    expect(state.pendingMessages, isEmpty);
    expect(state.supportsAgentMessages, isTrue);
  });

  test('ChatThreadController marks replayed pending messages when applied', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = '/threads/test.thread';
    final controller = ChatThreadController(room: harness.room);
    addTearDown(controller.dispose);

    controller.handleAgentMessagePayload({
      'type': 'meshagent.agent.turn.steer',
      'thread_id': threadPath,
      'turn_id': 'turn-1',
      'message_id': 'message-1',
      'sender_name': 'sender',
      'content': [
        {'type': 'text', 'text': 'wait'},
      ],
    });
    controller.handleAgentMessagePayload({
      'type': 'meshagent.agent.turn.steer.accepted',
      'thread_id': threadPath,
      'turn_id': 'turn-1',
      'source_message_id': 'message-1',
    });

    expect(controller.pendingAgentMessagesForPath(threadPath), hasLength(1));
    expect(controller.pendingAgentMessagesForPath(threadPath).single.text, 'wait');

    controller.handleAgentMessagePayload({
      'type': 'meshagent.agent.turn.steered',
      'thread_id': threadPath,
      'turn_id': 'turn-1',
      'source_message_id': 'message-1',
    });

    expect(controller.pendingAgentMessagesForPath(threadPath), isEmpty);
  });

  test('resolveChatThreadStatus preserves active turn without visible status text', () async {
    final harness = await _startMessagingHarness();
    addTearDown(harness.dispose);

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {
        'type': 'meshagent.agent.turn.steer',
        'thread_id': threadPath,
        'turn_id': 'turn-1',
        'message_id': 'message-1',
        'sender_name': 'self',
        'created_at': '2026-05-04T12:00:00Z',
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
      },
    );
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.thread.status', 'thread_id': threadPath, 'turn_id': 'turn-1', 'status': null},
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

    const threadPath = 'dataset://agents/dataset/threads/thread-1';
    trackAgentThreadStatusPayload(
      room: harness.room,
      payload: {'type': 'meshagent.agent.thread.status', 'thread_id': threadPath, 'status': 'Generating image', 'mode': 'busy'},
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
      final message = event.message.message;
      final payload = message['type'] is String ? message : message['payload'];
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
