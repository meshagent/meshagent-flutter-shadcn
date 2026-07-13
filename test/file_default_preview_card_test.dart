import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('thread attachment card constrains long filenames inside its border', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 312.5,
              child: ThreadTypographyOverride(
                useThreadAttachmentStyle: true,
                attachmentBorderColor: Colors.grey,
                child: const FileDefaultPreviewCard(
                  icon: LucideIcons.file,
                  text: 'Screenshot 2026-06-02 at 10.06.10 AM with an unusually long attachment name.md',
                  showActionIcon: true,
                  useThreadAttachmentStyle: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Screenshot 2026-06-02'), findsOneWidget);
  });
}
