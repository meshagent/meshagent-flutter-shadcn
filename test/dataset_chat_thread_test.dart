import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/dataset_chat_thread.dart';

void main() {
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
}
