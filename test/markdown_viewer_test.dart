import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';
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
    expect(table.showRowHeaders, isFalse);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('markdown table context menu wins over parent context menu', (tester) async {
    final previousVisibilityUpdateInterval = VisibilityDetectorController.instance.updateInterval;
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval = previousVisibilityUpdateInterval;
    });
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: CoordinatedShadContextMenuRegion(
            tapEnabled: false,
            items: const [ShadContextMenuItem(child: Text('Show tool calls'))],
            child: const MarkdownViewer(
              markdown: '''
| Name | Value |
| --- | --- |
| Alpha | Beta |
''',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.text('Alpha')), kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Show tool calls'), findsNothing);
  });

  testWidgets('secondary click on markdown table chrome does not open parent context menu', (tester) async {
    final previousVisibilityUpdateInterval = VisibilityDetectorController.instance.updateInterval;
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval = previousVisibilityUpdateInterval;
    });
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: CoordinatedShadContextMenuRegion(
            tapEnabled: false,
            items: const [ShadContextMenuItem(child: Text('Show tool calls'))],
            child: const MarkdownViewer(
              markdown: '''
| Name | Value |
| --- | --- |
| Alpha | Beta |
''',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(find.byType(InMemoryTable)) + const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Show tool calls'), findsNothing);
  });
}
