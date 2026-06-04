import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/chat_bot_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:super_native_extensions/src/native/context.dart';

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

class _MessagingHarness {
  _MessagingHarness({required this.pair, required this.room, required this.server});

  final _ProtocolPair pair;
  final RoomClient room;
  final _FakeMessagingServer server;

  Future<void> dispose() async {
    room.dispose();
    await server.drainPendingSends();
    // Room disposal can enqueue final protocol messages; give the protocol send
    // loops a turn to flush before closing the in-memory stream sinks.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pair.dispose();
  }
}

class _FakeMessagingServer {
  _FakeMessagingServer({ArrowRecordBatch? initialDatasetBatch, Completer<void>? initialReadyGate})
    : _initialDatasetBatch = initialDatasetBatch ?? _usageRowsBatch(),
      _initialReadyGate = initialReadyGate;

  final ArrowRecordBatch _initialDatasetBatch;
  final Completer<void>? _initialReadyGate;
  final Map<String, String> _streamToolsByCallId = {};
  final List<Future<void>> _pendingSends = [];
  final List<Map<String, dynamic>> invocations = [];
  int _watchPullCount = 0;
  int watchStarts = 0;
  int watchReadyEvents = 0;

  Future<void> drainPendingSends() async {
    final gate = _initialReadyGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    while (_pendingSends.isNotEmpty) {
      await Future.wait<void>(List<Future<void>>.of(_pendingSends));
    }
  }

  void _trackPendingSend(Future<void> future) {
    _pendingSends.add(future);
    unawaited(
      future.whenComplete(() {
        _pendingSends.remove(future);
      }),
    );
  }

  Future<void> handleMessage(Protocol protocol, int messageId, String type, Uint8List data) async {
    if (type == 'room.tool_call_request_chunk') {
      await _handleToolCallChunk(protocol, data);
      return;
    }

    if (type != 'room.invoke_tool') {
      return;
    }
    final message = unpackMessage(data);
    final request = message.header;
    invocations.add(Map<String, dynamic>.from(request));

    if (request['toolkit'] == 'dataset') {
      final tool = request['tool']?.toString();
      if (tool != 'watch_table' && tool != 'search') {
        throw StateError('unsupported dataset operation: $tool');
      }
      final input = _decodeInput(message: message, request: request);
      if (input is! ControlContent) {
        throw StateError('dataset.$tool expected stream control input');
      }
      final toolCallId = request['tool_call_id']?.toString();
      if (toolCallId == null || toolCallId.isEmpty) {
        throw StateError('dataset.$tool missing tool_call_id');
      }
      _streamToolsByCallId[toolCallId] = tool!;
      await protocol.send('__response__', ControlContent(method: 'open').pack(), id: messageId);
      _trackPendingSend(() async {
        try {
          await Future<void>.delayed(Duration.zero);
          watchStarts += 1;
          await _sendResponseChunk(
            protocol,
            toolCallId,
            BinaryContent(
              data: _initialDatasetBatch.ipcBytes,
              headers: tool == 'watch_table' ? const {'kind': 'data', 'watch_event': 'data', 'phase': 'initial'} : const {'kind': 'data'},
            ),
          );
          await _initialReadyGate?.future;
          watchReadyEvents += 1;
          if (tool == 'watch_table') {
            await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'ready', 'phase': 'initial'}));
          }
          await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
        } catch (_) {}
      }());
      return;
    }

    if (request['toolkit'] != 'messaging') {
      return;
    }
    switch (request['tool']) {
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
                  'role': 'agent',
                  'attributes': {'name': 'assistant', 'supports_agent_messages': true},
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
        throw StateError('unsupported messaging operation: ${request['tool']}');
    }
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

  Future<void> sendDatasetRows(Protocol protocol, ArrowRecordBatch batch) async {
    String? toolCallId;
    for (final entry in _streamToolsByCallId.entries) {
      if (entry.value == 'watch_table') {
        toolCallId = entry.key;
        break;
      }
    }
    if (toolCallId == null) {
      return;
    }
    if (_streamToolsByCallId[toolCallId] != 'watch_table') {
      return;
    }
    await _sendResponseChunk(
      protocol,
      toolCallId,
      BinaryContent(data: batch.ipcBytes, headers: const {'kind': 'data', 'watch_event': 'data', 'phase': 'update'}),
    );
  }

  Future<void> _handleToolCallChunk(Protocol protocol, Uint8List data) async {
    final message = unpackMessage(data);
    final request = message.header;
    final toolCallId = request['tool_call_id']?.toString();
    if (toolCallId == null) {
      return;
    }
    final tool = _streamToolsByCallId[toolCallId];
    if (tool != 'watch_table' && tool != 'search') {
      return;
    }

    final chunk = _decodeChunk(message: message, request: request);
    if (chunk is! BinaryContent) {
      throw StateError('dataset.$tool expected binary stream input');
    }
    if (chunk.headers['kind'] == 'start') {
      _watchPullCount = 0;
      watchStarts += 1;
      await _sendResponseChunk(
        protocol,
        toolCallId,
        BinaryContent(
          data: _initialDatasetBatch.ipcBytes,
          headers: tool == 'watch_table' ? const {'kind': 'data', 'watch_event': 'data', 'phase': 'initial'} : const {'kind': 'data'},
        ),
      );
      return;
    }
    if (chunk.headers['kind'] == 'pull') {
      _watchPullCount += 1;
      if (_watchPullCount == 1 && tool == 'watch_table') {
        await _initialReadyGate?.future;
        watchReadyEvents += 1;
        await _sendResponseChunk(protocol, toolCallId, JsonContent(json: const {'kind': 'ready', 'phase': 'initial'}));
      } else if (_watchPullCount == 1 && tool == 'search') {
        await _initialReadyGate?.future;
        watchReadyEvents += 1;
        await _sendResponseChunk(protocol, toolCallId, ControlContent(method: 'close'));
      }
    }
  }

  Content _decodeInput({required Message message, required Map<String, dynamic> request}) {
    final arguments = Map<String, dynamic>.from(request['arguments'] as Map);
    return unpackContent(packMessage(arguments, message.payload.isEmpty ? null : message.payload));
  }

  Content _decodeChunk({required Message message, required Map<String, dynamic> request}) {
    final chunk = Map<String, dynamic>.from(request['chunk'] as Map);
    return unpackContent(packMessage(chunk, message.payload.isEmpty ? null : message.payload));
  }

  Future<void> _sendResponseChunk(Protocol protocol, String toolCallId, Content chunk) async {
    final packed = chunk.pack();
    final payload = splitMessagePayload(packed);
    await protocol.send(
      'room.tool_call_response_chunk',
      packMessage({
        'tool_call_id': toolCallId,
        'chunk': jsonDecode(splitMessageHeader(packed)) as Map<String, dynamic>,
      }, payload.isEmpty ? null : payload),
    );
  }
}

ArrowRecordBatch _usageRowsBatch({
  String itemId = 'usage-1',
  int sequence = 0,
  int usedTokens = 480,
  double inputTokens = 120.0,
  double outputTokens = 30.0,
}) {
  const schema = ArrowSchema([
    ArrowField(name: 'item_id', type: ArrowUtf8Type()),
    ArrowField(name: 'sequence', type: ArrowIntType(bitWidth: 64, signed: true)),
    ArrowField(name: 'data', type: ArrowUtf8Type()),
  ]);
  return ArrowRecordBatch.fromColumns(
    schema: schema,
    columns: [
      ArrowValueArray(field: schema.fields[0], values: [itemId]),
      ArrowValueArray(field: schema.fields[1], values: [BigInt.from(sequence)]),
      ArrowValueArray(
        field: schema.fields[2],
        values: [
          jsonEncode({
            'kind': 'usage',
            'status': 'completed',
            'message': {
              'type': 'meshagent.agent.usage.updated',
              'thread_id': 'dataset://threads/test',
              'message_id': itemId,
              'turn_id': 'turn-1',
              'usage': {'input_tokens': inputTokens, 'output_tokens': outputTokens},
              'context_window': {'used_tokens': usedTokens, 'total_tokens': 128000},
            },
          }),
        ],
      ),
    ],
  );
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

Future<_MessagingHarness> _startMessagingHarness({ArrowRecordBatch? initialDatasetBatch, Completer<void>? initialReadyGate}) async {
  final pair = _ProtocolPair();
  final server = _FakeMessagingServer(initialDatasetBatch: initialDatasetBatch, initialReadyGate: initialReadyGate);
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

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, {int maxPumps = 100, String Function()? describe}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(describe?.call() ?? 'condition was not met before timeout');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    File? fontFile;
    while (true) {
      final candidates = [
        File(
          '${directory.path}/cache/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto_Mono/RobotoMono-Regular.ttf',
        ),
        File(
          '${directory.path}/bin/cache/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto_Mono/RobotoMono-Regular.ttf',
        ),
      ];
      for (final candidate in candidates) {
        if (candidate.existsSync()) {
          fontFile = candidate;
          break;
        }
      }
      if (fontFile != null || directory.parent.path == directory.path) {
        break;
      }
      directory = directory.parent;
    }
    final resolvedFontFile = fontFile;
    if (resolvedFontFile == null) {
      throw StateError('Unable to locate a local monospace font for google_fonts tests.');
    }
    final fontBytes = resolvedFontFile.readAsBytesSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      if (message == null) {
        return null;
      }
      final key = utf8.decode(message.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          'google_fonts/SourceCodePro-Regular.ttf': [
            {'asset': 'google_fonts/SourceCodePro-Regular.ttf'},
          ],
        });
      }
      if (key == 'google_fonts/SourceCodePro-Regular.ttf') {
        return ByteData.sublistView(fontBytes);
      }
      return null;
    });
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.irondash.engine_context'),
    (call) async {
      if (call.method == 'getEngineHandle') {
        return 0;
      }
      return null;
    },
  );
  final nativeContext = superNativeExtensionsContext;
  if (nativeContext is MockMessageChannelContext) {
    nativeContext.registerMockMethodCallHandler('DropManager', (MethodCall call) async => null);
    nativeContext.registerMockMethodCallHandler('DragManager', (MethodCall call) async => null);
  }

  test('AgentUsageSnapshot does not double count usage detail token buckets', () {
    final usage = AgentUsageSnapshot.fromPayload({
      'type': 'meshagent.agent.usage.updated',
      'thread_id': 'tmp://threads/test',
      'usage': {'input_tokens': 11.0, 'output_tokens': 7.0, 'cached_tokens': 4.0, 'reasoning_tokens': 3.0},
      'context_window': {'used_tokens': 22, 'total_tokens': 128000},
    });

    expect(usage, isNotNull);
    expect(usage!.contextUsedTokens, 22);
    expect(usage.totalTokens, 18);
  });

  test('AgentUsageSnapshot reads model-prefixed usage token buckets', () {
    final usage = AgentUsageSnapshot.fromPayload({
      'type': 'meshagent.agent.usage.updated',
      'thread_id': 'tmp://threads/test',
      'usage': {'gpt-test.input_tokens': 11.0, 'gpt-test.output_tokens': 7.0, 'gpt-test.cached_tokens': 4.0},
      'context_window': {'used_tokens': 22, 'total_tokens': 128000},
    });

    expect(usage, isNotNull);
    expect(usage!.totalTokens, 18);
  });

  testWidgets('ChatBotView usage footer updates from direct agent-message payload', (tester) async {
    final harness = (await tester.runAsync<_MessagingHarness>(() async {
      final harness = await _startMessagingHarness();
      await harness.room.messaging.enable();
      await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);
      return harness;
    }))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatBotView(room: harness.room, agentName: 'assistant', documentPath: 'tmp://threads/test', showUsageFooter: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('context --'), findsNothing);

    await tester.runAsync(() async {
      await harness.server.sendAgentMessage(harness.pair.serverProtocol, {
        'type': 'meshagent.agent.usage.updated',
        'thread_id': 'tmp://threads/test',
        'message_id': 'usage-1',
        'turn_id': 'turn-1',
        'usage': {'input_tokens': 11.0, 'output_tokens': 7.0, 'cached_tokens': 4.0, 'reasoning_tokens': 3.0},
        'context_window': {'used_tokens': 22, 'total_tokens': 128000},
      });
    });
    await _pumpUntil(
      tester,
      () => find.text('context 22/128K').evaluate().isNotEmpty,
      describe: () {
        final texts = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ');
        return 'usage footer did not update. Rendered text: $texts';
      },
    );

    expect(find.text('context 22/128K'), findsOneWidget);
  });

  testWidgets('ChatBotView usage footer shows usage tooltip', (tester) async {
    final harness = (await tester.runAsync<_MessagingHarness>(() async {
      final harness = await _startMessagingHarness();
      await harness.room.messaging.enable();
      await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);
      return harness;
    }))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatBotView(room: harness.room, agentName: 'assistant', documentPath: 'tmp://threads/test', showUsageFooter: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await harness.server.sendAgentMessage(harness.pair.serverProtocol, {
        'type': 'meshagent.agent.usage.updated',
        'thread_id': 'tmp://threads/test',
        'message_id': 'usage-1',
        'turn_id': 'turn-1',
        'usage': {'input_tokens': 11.0, 'output_tokens': 7.0, 'cached_tokens': 4.0},
        'context_window': {'used_tokens': 22, 'total_tokens': 128000},
      });
    });
    await _pumpUntil(
      tester,
      () => find.text('context 22/128K').evaluate().isNotEmpty,
      describe: () {
        final texts = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ');
        return 'usage footer did not update. Rendered text: $texts';
      },
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.text('context 22/128K')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.textContaining('context used: 22'), findsOneWidget);
    expect(find.textContaining('cached_tokens: 4'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('ChatBotView usage footer uses compaction threshold as context denominator', (tester) async {
    final harness = (await tester.runAsync<_MessagingHarness>(() async {
      final harness = await _startMessagingHarness();
      await harness.room.messaging.enable();
      await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);
      return harness;
    }))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatBotView(room: harness.room, agentName: 'assistant', documentPath: 'tmp://threads/test', showUsageFooter: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await harness.server.sendAgentMessage(harness.pair.serverProtocol, {
        'type': 'meshagent.agent.usage.updated',
        'thread_id': 'tmp://threads/test',
        'message_id': 'usage-1',
        'turn_id': 'turn-1',
        'usage': {'input_tokens': 11.0, 'output_tokens': 7.0},
        'context_window': {'used_tokens': 480, 'total_tokens': 128000, 'compaction_mode': 'auto', 'compaction_threshold': 64000},
      });
    });
    await _pumpUntil(
      tester,
      () => find.text('context 480/64K').evaluate().isNotEmpty,
      describe: () {
        final texts = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ');
        return 'compaction threshold usage footer did not render. Rendered text: $texts';
      },
    );

    expect(find.text('context 480/64K'), findsOneWidget);
    expect(find.text('auto context 480/64K'), findsNothing);
    expect(find.text('context 480/128K'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.text('context 480/64K')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.textContaining('context management: auto'), findsOneWidget);
    expect(find.textContaining('context threshold: 64K'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('ChatBotView context-only usage footer keeps token total empty', (tester) async {
    final harness = (await tester.runAsync<_MessagingHarness>(() async {
      final harness = await _startMessagingHarness();
      await harness.room.messaging.enable();
      await _waitUntil(() => harness.room.messaging.remoteParticipants.isNotEmpty);
      return harness;
    }))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChatBotView(room: harness.room, agentName: 'assistant', documentPath: 'tmp://threads/test', showUsageFooter: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await harness.server.sendAgentMessage(harness.pair.serverProtocol, {
        'type': 'meshagent.agent.usage.updated',
        'thread_id': 'tmp://threads/test',
        'message_id': 'usage-1',
        'turn_id': 'turn-1',
        'usage': <String, dynamic>{},
        'context_window': {'used_tokens': 480, 'total_tokens': 128000},
      });
    });
    await _pumpUntil(
      tester,
      () => find.text('context 480/128K').evaluate().isNotEmpty,
      describe: () {
        final texts = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ');
        return 'context-only usage footer did not render. Rendered text: $texts';
      },
    );

    expect(find.text('context 480/128K'), findsOneWidget);
  });
}
