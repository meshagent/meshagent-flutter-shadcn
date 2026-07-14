import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('agentTurnEndedErrorMessage', () {
    test('extracts process turn errors from turn ended payloads', () {
      final message = agentTurnEndedErrorMessage({
        'type': 'meshagent.agent.turn.ended',
        'error': {'message': 'Error from OpenAI Realtime websocket: Model "gpt-realtime-2" is only available on the GA API.'},
      });

      expect(message, 'Error from OpenAI Realtime websocket: Model "gpt-realtime-2" is only available on the GA API.');
    });

    test('ignores successful turn ended payloads', () {
      final message = agentTurnEndedErrorMessage({'type': 'meshagent.agent.turn.ended', 'error': null});

      expect(message, isNull);
    });

    test('ignores non turn ended payloads', () {
      final message = agentTurnEndedErrorMessage({
        'type': 'meshagent.agent.turn.started',
        'error': {'message': 'not a terminal error'},
      });

      expect(message, isNull);
    });
  });

  group('dataset tool call diff previews', () {
    test('renders Codex diff tool calls like apply patch previews', () {
      const diff = '''
diff --git a/lib/report.py b/lib/report.py
--- a/lib/report.py
+++ b/lib/report.py
@@
-old
+new
+extra
''';

      final blocks = datasetToolCallDiffPreviewBlocksForTesting(toolkit: 'codex', tool: 'diff_updated', arguments: {'diff': diff});

      expect(blocks, hasLength(1));
      expect(blocks.single['header'], 'lib/report.py');
      expect(blocks.single['code'], contains('-old'));
      expect(blocks.single['code'], contains('+extra'));
      expect(blocks.single['linesAdded'], 2);
      expect(blocks.single['linesRemoved'], 1);
    });

    test('does not render arbitrary diff arguments from unrelated tools', () {
      final blocks = datasetToolCallDiffPreviewBlocksForTesting(
        toolkit: 'other',
        tool: 'diff_updated',
        arguments: {'diff': '@@\n-old\n+new\n'},
      );

      expect(blocks, isEmpty);
    });
  });

  group('dataset row timestamps', () {
    test('uses top-level timestamp when present', () {
      final timestamp = datasetRowTimestampForTesting({
        'timestamp': '2026-05-01T12:30:00Z',
        'data': {'created_at': '2026-05-02T12:30:00Z'},
      });

      expect(timestamp.toUtc(), DateTime.utc(2026, 5, 1, 12, 30));
    });

    test('falls back to payload created_at when row timestamp is missing', () {
      final timestamp = datasetRowTimestampForTesting({
        'data': {'created_at': '2026-05-02T12:30:00Z'},
      });

      expect(timestamp.toUtc(), DateTime.utc(2026, 5, 2, 12, 30));
    });

    test('falls back to nested message created_at when row timestamp is empty', () {
      final timestamp = datasetRowTimestampForTesting({
        'timestamp': '',
        'data': {
          'message': {'created_at': '2026-05-03T12:30:00Z'},
        },
      });

      expect(timestamp.toUtc(), DateTime.utc(2026, 5, 3, 12, 30));
    });
  });

  group('dataset message replay', () {
    testWidgets('does not duplicate assistant text when stream and final rows replay together', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const ui.Size(1200, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const threadPath = 'dataset://agents/assistant/threads/thread-1';
      const reply = '''
Here's the webserver link:

https://test-06x.meshagent.dev

You can also open the preview/files here: [Add files here to preview](powerboards://files/webserver)''';
      final rowsController = StreamController<List<Map<String, Object?>>>.broadcast();
      addTearDown(() async {
        if (!rowsController.isClosed) {
          await rowsController.close();
        }
      });

      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 820,
              child: DatasetChatThread(path: threadPath, rowsLoader: ({required namespace, required table}) => rowsController.stream),
            ),
          ),
        ),
      );
      await tester.pump();

      rowsController.add([
        {
          'item_id': 'assistant-message-1',
          'turn_id': 'turn-1',
          'sequence': 1,
          'timestamp': '2026-06-23T19:35:00Z',
          'data': {
            'type': agent_sessions.agentTextContentDeltaType,
            'thread_id': threadPath,
            'turn_id': 'turn-1',
            'item_id': 'assistant-message-1',
            'text': reply,
            'sender_name': 'Assistant',
          },
        },
        {
          'item_id': 'assistant-message-1',
          'turn_id': 'turn-1',
          'sequence': 2,
          'timestamp': '2026-06-23T19:35:01Z',
          'data': {
            'type': agent_sessions.agentTextContentEndedType,
            'thread_id': threadPath,
            'turn_id': 'turn-1',
            'item_id': 'assistant-message-1',
            'text': reply,
            'sender_name': 'Assistant',
            'phase': 'final_answer',
          },
        },
        {
          'item_id': 'assistant-message-1',
          'turn_id': 'turn-1',
          'sequence': 3,
          'timestamp': '2026-06-23T19:35:02Z',
          'data': {
            'kind': 'message',
            'role': 'assistant',
            'status': 'completed',
            'text': reply,
            'sender_name': 'Assistant',
            'phase': 'final_answer',
          },
        },
      ]);
      await rowsController.close();

      await tester.pump();
      await tester.pump();

      expect(find.byWidgetPredicate((widget) => widget is ChatThreadMessageView && widget.text == reply), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
