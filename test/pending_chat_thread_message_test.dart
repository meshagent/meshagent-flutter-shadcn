import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  testWidgets('pending file renderer can replace an encoded attachment card', (tester) async {
    final previousVisibilityUpdateInterval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() => VisibilityDetectorController.instance.updateInterval = previousVisibilityUpdateInterval);
    const attachmentUrl = 'data:text/plain;base64,encoded-folder-context';
    String? openedPath;

    await tester.pumpWidget(
      ShadApp(
        home: PendingChatThreadMessage(
          room: null,
          message: const PendingAgentMessage(
            messageId: 'message-1',
            messageType: 'turn_start',
            threadPath: 'threads/thread-1',
            text: 'What is here?',
            attachments: <AgentFileContent>[AgentFileContent(url: attachmentUrl)],
          ),
          pendingFileInThreadBuilder: (context, path) {
            return path == attachmentUrl ? const Text('Files folder card') : null;
          },
          openFile: (path) => openedPath = path,
        ),
      ),
    );

    expect(find.text('Files folder card'), findsOneWidget);
    expect(find.textContaining('encoded-folder-context'), findsNothing);

    await tester.tap(find.text('Files folder card'));
    await tester.pump();
    expect(openedPath, attachmentUrl);
  });
}
