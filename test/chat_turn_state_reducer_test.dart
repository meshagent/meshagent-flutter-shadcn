import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_agents/meshagent_agents.dart' as agent_sessions;
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/chat_turn_state_reducer.dart';

void main() {
  test('persisted final assistant message completes matching turn and clears status', () {
    final reducer = ChatTurnStateReducer();
    final changed = reducer.applyDatasetRow({
      'item_id': 'assistant-message-1',
      'turn_id': 'turn-1',
      'data': {'kind': 'message', 'role': 'assistant', 'status': 'completed', 'text': 'Done'},
    });

    expect(changed, isTrue);
    expect(reducer.isTurnComplete('turn-1'), isTrue);

    final status = reducer.reduceStatus(
      const ChatThreadStatusState(
        text: 'Preparing to write /data/website/index.html',
        mode: 'busy',
        turnId: 'turn-1',
        pendingItemId: 'tool-1',
        supportsAgentMessages: true,
      ),
    );

    expect(status.turnId, isNull);
    expect(status.text, isNull);
    expect(status.supportsAgentMessages, isTrue);
  });

  test('persisted final-answer file completes matching turn', () {
    final reducer = ChatTurnStateReducer();

    expect(
      reducer.applyDatasetRow({
        'item_id': 'file-1',
        'turn_id': 'turn-1',
        'data': {
          'kind': 'file',
          'role': 'assistant',
          'status': 'completed',
          'phase': 'final_answer',
          'urls': ['/data/website/index.html'],
        },
      }),
      isTrue,
    );

    expect(reducer.isTurnComplete('turn-1'), isTrue);
  });

  test('running persisted file does not complete turn', () {
    final reducer = ChatTurnStateReducer();

    expect(
      reducer.applyDatasetRow({
        'item_id': 'file-1',
        'turn_id': 'turn-1',
        'data': {
          'kind': 'file',
          'role': 'assistant',
          'status': 'in_progress',
          'urls': ['/data/website/index.html'],
        },
      }),
      isFalse,
    );

    expect(reducer.isTurnComplete('turn-1'), isFalse);
  });

  test('ordinary persisted file does not complete turn', () {
    final reducer = ChatTurnStateReducer();

    expect(
      reducer.applyDatasetRow({
        'item_id': 'file-1',
        'turn_id': 'turn-1',
        'data': {
          'kind': 'file',
          'role': 'assistant',
          'status': 'completed',
          'urls': ['/data/website/index.html'],
        },
      }),
      isFalse,
    );

    expect(reducer.isTurnComplete('turn-1'), isFalse);
  });

  test('persisted commentary message does not complete turn', () {
    final reducer = ChatTurnStateReducer();

    expect(
      reducer.applyDatasetRow({
        'item_id': 'assistant-message-1',
        'turn_id': 'turn-1',
        'data': {'kind': 'message', 'role': 'assistant', 'phase': 'commentary', 'text': 'I will create the files now.'},
      }),
      isFalse,
    );

    expect(reducer.isTurnComplete('turn-1'), isFalse);
  });

  test('stale status payload for completed turn is ignored', () {
    final reducer = ChatTurnStateReducer();
    reducer.applyDatasetRow({
      'item_id': 'assistant-message-1',
      'turn_id': 'turn-1',
      'data': {'kind': 'message', 'role': 'assistant', 'text': 'Done'},
    });

    expect(
      reducer.shouldIgnoreStatusPayload({
        'type': agent_sessions.agentThreadStatusType,
        'thread_id': 'dataset://agents/assistant/threads/thread-1',
        'turn_id': 'turn-1',
        'status': 'Preparing to write /data/website/index.html',
      }),
      isTrue,
    );
    expect(
      reducer.shouldIgnoreStatusPayload({
        'type': agent_sessions.agentThreadStatusType,
        'thread_id': 'dataset://agents/assistant/threads/thread-1',
        'turn_id': 'turn-2',
        'status': 'Working',
      }),
      isFalse,
    );
  });
}
