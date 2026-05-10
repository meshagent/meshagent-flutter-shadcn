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
}
