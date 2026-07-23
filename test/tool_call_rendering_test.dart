import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/tool_call_rendering.dart';

void main() {
  group('ChatToolCallIdentity', () {
    test('uses call id for stable identity and item id as fallback', () {
      const withCallId = ChatToolCallIdentity(threadId: 'thread-1', turnId: 'turn-1', itemId: 'item-1', callId: 'call-1');
      const withoutCallId = ChatToolCallIdentity(threadId: 'thread-1', turnId: 'turn-1', itemId: 'item-1');

      expect(withCallId.stableKey, 'thread-1:call-1');
      expect(withoutCallId.stableKey, 'thread-1:item-1');
    });
  });

  group('ChatToolCallRendererRegistry', () {
    test('resolves exact, toolkit, and tool registrations in precedence order', () {
      final toolOnly = _TestRenderer('tool');
      final toolkit = _TestRenderer('toolkit');
      final exact = _TestRenderer('exact');
      final registry = ChatToolCallRendererRegistry(
        renderers: <ChatToolCallRendererKey, ChatToolCallRenderer>{
          const ChatToolCallRendererKey(tool: 'deploy'): toolOnly,
          const ChatToolCallRendererKey(toolkit: 'builder', tool: 'deploy'): toolkit,
          const ChatToolCallRendererKey(namespace: 'meshagent', toolkit: 'builder', tool: 'deploy'): exact,
        },
      );

      expect(registry.resolve(_snapshot()), same(exact));
      expect(registry.resolve(_snapshot(namespace: 'other')), same(toolkit));
      expect(registry.resolve(_snapshot(namespace: 'other', toolkit: 'other')), same(toolOnly));
      expect(registry.resolve(_snapshot(tool: 'preview')), isNull);
    });
  });
}

ChatToolCallSnapshot _snapshot({String namespace = 'meshagent', String toolkit = 'builder', String tool = 'deploy'}) {
  final now = DateTime.utc(2026, 7, 20);
  return ChatToolCallSnapshot(
    identity: const ChatToolCallIdentity(threadId: 'thread-1', turnId: 'turn-1', itemId: 'item-1', callId: 'call-1'),
    namespace: namespace,
    toolkit: toolkit,
    tool: tool,
    status: ChatToolCallStatus.running,
    arguments: const <String, Object?>{'room': 'room-1'},
    startedAt: now,
    updatedAt: now,
  );
}

class _TestRenderer implements ChatToolCallRenderer {
  const _TestRenderer(this.label);

  final String label;

  @override
  Widget build(BuildContext context, ChatToolCallRenderContext renderContext) => Text(label);
}
