import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/thread_list_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _NoopProtocolChannel extends ProtocolChannel {
  @override
  void dispose() {}

  @override
  Future<void> sendData(Uint8List data) async {}

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {}
}

void main() {
  testWidgets('does not render a pending selected thread row before the thread list contains it', (tester) async {
    final room = RoomClient(protocolFactory: Protocol.createFactory(channel: _NoopProtocolChannel()));
    addTearDown(room.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ChatThreadListView(
              room: room,
              threadListPath: '',
              selectedThreadPath: 'agents/assistant/threads/12345678-1234-5678-1234-567812345678.thread',
              selectedThreadDisplayName: 'New Thread',
              onSelectedThreadPathChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New Thread'), findsNothing);
    expect(find.text('New thread'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.messageSquarePlus), findsNothing);
    expect(find.text('No threads yet'), findsOneWidget);
  });
}
