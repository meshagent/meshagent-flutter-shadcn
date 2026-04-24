import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('auto sizing vertically fits all rows and disables vertical scrolling', (tester) async {
    final rows = List.generate(20, (index) => ['row $index']);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(columns: const ['Name'], rows: rows, autoSizeVertically: true),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final verticalScrollView = tester.widget<CustomScrollView>(
      find.byWidgetPredicate((widget) => widget is CustomScrollView && widget.scrollDirection == Axis.vertical),
    );
    expect(verticalScrollView.physics, isA<NeverScrollableScrollPhysics>());

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final expectedHeight = 20 * kDefaultCellHeight + kColumnHeaderHeight + 1 + 8;
    expect(tester.getSize(tablePadding).height, closeTo(expectedHeight, 0.1));
  });

  testWidgets('auto sizing horizontally fits all columns and disables horizontal scrolling', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Align(
                alignment: Alignment.topLeft,
                child: InMemoryTable(
                  columns: const ['A', 'B'],
                  rows: const [
                    ['1', '2'],
                  ],
                  autoSizeHorizontally: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final horizontalScrollView = tester.widget<CustomScrollView>(
      find.byWidgetPredicate((widget) => widget is CustomScrollView && widget.scrollDirection == Axis.horizontal),
    );
    expect(horizontalScrollView.physics, isA<NeverScrollableScrollPhysics>());

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final expectedWidth = kRowHeaderWidth + (2 * 160) + 1;
    expect(tester.getSize(tablePadding).width, closeTo(expectedWidth, 0.1));
  });

  testWidgets('auto sizing columns fits column extents to content', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SizedBox(
            width: 1600,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Align(
                alignment: Alignment.topLeft,
                child: InMemoryTable(
                  columns: const ['Name'],
                  rows: const [
                    ['this is a much longer value that should force the auto sized column well past the default width'],
                  ],
                  autoSizeColumns: true,
                  autoSizeHorizontally: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final defaultWidth = kRowHeaderWidth + 160 + 1;
    expect(tester.getSize(tablePadding).width, greaterThan(defaultWidth));
  });

  testWidgets('auto sizing rows fits row extents to content', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(
                columns: const ['Name'],
                rows: const [
                  ['line 1\nline 2\nline 3\nline 4'],
                ],
                autoSizeRows: true,
                autoSizeVertically: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final defaultHeight = kDefaultCellHeight + kColumnHeaderHeight + 1 + 8;
    expect(tester.getSize(tablePadding).height, greaterThan(defaultHeight));
  });

  testWidgets('auto sizing rows preserves the default padded height for short content', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(
                columns: const ['Name'],
                rows: const [
                  ['short'],
                ],
                autoSizeRows: true,
                autoSizeVertically: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final expectedHeight = kDefaultCellHeight + kColumnHeaderHeight + 1 + 8;
    expect(tester.getSize(tablePadding).height, closeTo(expectedHeight, 0.1));
  });

  testWidgets('auto sizing columns honors max width and grows rows for wrapped text', (tester) async {
    const maxColumnExtent = 120.0;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(
                columns: const ['Notes'],
                rows: const [
                  [
                    'This is a deliberately long paragraph that should wrap into multiple lines once the auto fit width hits the configured cap.',
                  ],
                ],
                autoSizeColumns: true,
                autoSizeHorizontally: true,
                autoSizeVertically: true,
                maxAutoSizeColumnExtent: maxColumnExtent,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    expect(tester.getSize(tablePadding).width, closeTo(kRowHeaderWidth + maxColumnExtent + 1, 0.1));

    final defaultHeight = kDefaultCellHeight + kColumnHeaderHeight + 1 + 8;
    expect(tester.getSize(tablePadding).height, greaterThan(defaultHeight));
  });

  testWidgets('wrapped auto sized rows preserve vertical padding when column width hits the cap', (tester) async {
    const maxColumnExtent = 120.0;
    const cellPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 20);
    const longText =
        'This paragraph should wrap after the column auto fit reaches its maximum width, while still keeping top and bottom padding.';

    await tester.pumpWidget(
      ShadApp(
        theme: ShadThemeData(tableTheme: const ShadTableTheme(cellPadding: cellPadding)),
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(
                columns: const ['Notes'],
                rows: const [
                  [longText],
                ],
                autoSizeColumns: true,
                autoSizeHorizontally: true,
                autoSizeVertically: true,
                maxAutoSizeColumnExtent: maxColumnExtent,
                maxAutoSizeRowExtent: 600,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final cellPaddingFinder = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == cellPadding);
    expect(cellPaddingFinder, findsOneWidget);

    final cellTextFinder = find.text(longText);
    expect(cellTextFinder, findsOneWidget);

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    final columnExtent = tester.getSize(tablePadding).width - kRowHeaderWidth - 1;
    expect(columnExtent, closeTo(maxColumnExtent, 0.1));

    final cellPaddingSize = tester.getSize(cellPaddingFinder);
    final textElement = tester.element(cellTextFinder);
    final textWidget = tester.widget<Text>(cellTextFinder);
    final textPainter = TextPainter(
      text: TextSpan(text: longText, style: textWidget.style),
      textDirection: Directionality.of(textElement),
      textScaler: MediaQuery.maybeTextScalerOf(textElement) ?? TextScaler.noScaling,
      maxLines: null,
    )..layout(maxWidth: columnExtent - 1 - cellPadding.horizontal);

    expect(cellPaddingSize.height, closeTo(textPainter.height.ceilToDouble() + cellPadding.vertical, 0.1));
  });

  testWidgets('auto sizing rows honors max row extent', (tester) async {
    const maxRowExtent = 80.0;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: InMemoryTable(
                columns: const ['Name'],
                rows: const [
                  ['line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7'],
                ],
                autoSizeRows: true,
                autoSizeVertically: true,
                maxAutoSizeRowExtent: maxRowExtent,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tablePadding = find.byWidgetPredicate((widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4));
    expect(tester.getSize(tablePadding).height, closeTo(kColumnHeaderHeight + maxRowExtent + 1 + 8, 0.1));
  });

  testWidgets('copy context menu item closes after copy', (tester) async {
    final platform = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final clipboardCalls = <MethodCall>[];
    platform.setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        clipboardCalls.add(methodCall);
      }
      return null;
    });
    addTearDown(() => platform.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InMemoryTable(
              columns: const ['Name'],
              rows: const [
                ['Alpha'],
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tapAt(
      const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expect(find.text('Copy'), findsNothing);
  });
}
