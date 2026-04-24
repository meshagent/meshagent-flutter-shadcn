import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  testWidgets('markdown tables render with InMemoryTable', (tester) async {
    final previousVisibilityUpdateInterval = VisibilityDetectorController.instance.updateInterval;
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval = previousVisibilityUpdateInterval;
    });
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    await tester.pumpWidget(
      ShadApp(
        home: const Scaffold(
          body: MarkdownViewer(
            markdown: '''
| Name | Value |
| --- | --- |
| Alpha | Beta |
''',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(InMemoryTable), findsOneWidget);
    final table = tester.widget<InMemoryTable>(find.byType(InMemoryTable));
    expect(table.autoSizeColumns, isTrue);
    expect(table.autoSizeRows, isTrue);
    expect(table.autoSizeVertically, isTrue);
    expect(table.showLeadingOuterBorders, isTrue);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });
}
