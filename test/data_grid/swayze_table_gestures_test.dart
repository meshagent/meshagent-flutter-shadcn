import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/controller.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/delegates.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/widgets/table_body/selections/primary_selection/primary_selection.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/widgets/headers/header_label_scope.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/widgets.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze_math/swayze_math.dart';

void main() {
  testWidgets('table does not render an initial visible selection', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PrimarySelectionPainter), findsNothing);
  });

  testWidgets('single click in the body selects the cell', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20));
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection;
    expect(selection, isA<CellUserSelectionModel>());

    final cellSelection = selection as CellUserSelectionModel;
    expect(cellSelection.anchor, const IntVector2(0, 0));
    expect(cellSelection.focus, const IntVector2(0, 0));
  });

  testWidgets('single click in the row header selects the row', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, kColumnHeaderHeight + 20));
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection;
    expect(selection, isA<HeaderUserSelectionModel>());

    final rowSelection = selection as HeaderUserSelectionModel;
    expect(rowSelection.axis, Axis.vertical);
    expect(rowSelection.anchor, 0);
    expect(rowSelection.focus, 0);
  });

  testWidgets('secondary click in the body does not replace the current selection', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final outsideFocusNode = FocusNode(debugLabel: 'outside-focus');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      outsideFocusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        outsideFocusNode: outsideFocusNode,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(kRowHeaderWidth + kDefaultCellWidth + 20, kColumnHeaderHeight + kDefaultCellHeight + 20));
    await tester.pumpAndSettle();

    await tester.tapAt(
      const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection;
    expect(selection, isA<CellUserSelectionModel>());

    final cellSelection = selection as CellUserSelectionModel;
    expect(cellSelection.anchor, const IntVector2(1, 1));
    expect(cellSelection.focus, const IntVector2(1, 1));
  });

  testWidgets('losing focus preserves the selected cell', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final outsideFocusNode = FocusNode(debugLabel: 'outside-focus');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      outsideFocusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        outsideFocusNode: outsideFocusNode,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(kRowHeaderWidth + kDefaultCellWidth + 20, kColumnHeaderHeight + kDefaultCellHeight + 20));
    await tester.pumpAndSettle();

    expect(find.byType(PrimarySelectionPainter), findsOneWidget);

    outsideFocusNode.requestFocus();
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection;
    expect(selection, isA<CellUserSelectionModel>());

    final cellSelection = selection as CellUserSelectionModel;
    expect(cellSelection.anchor, const IntVector2(1, 1));
    expect(cellSelection.focus, const IntVector2(1, 1));
    expect(find.byType(PrimarySelectionPainter), findsOneWidget);
  });

  testWidgets('dragging a column header separator resizes the column', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final start = const Offset(kRowHeaderWidth + kDefaultCellWidth - 1, 20);

    await tester.timedDragFrom(start, const Offset(30, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final resizedWidth = controller.tableDataController.columns.value.getHeaderExtentFor(index: 0);
    expect(resizedWidth, closeTo(kDefaultCellWidth + 30, 0.1));
  });

  testWidgets('dragging a row header separator resizes the row', (tester) async {
    final controller = _TestSwayzeController(columnCount: 3, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final start = const Offset(20, kColumnHeaderHeight + kDefaultCellHeight - 1);

    await tester.timedDragFrom(start, const Offset(0, 24), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final resizedHeight = controller.tableDataController.rows.value.getHeaderExtentFor(index: 0);
    expect(resizedHeight, closeTo(kDefaultCellHeight + 24, 0.1));
  });

  testWidgets('dragging a column separator after horizontal scroll resizes the visible column', (tester) async {
    final controller = _TestSwayzeController(columnCount: 10, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    controller.scroll.horizontalScrollController!.jumpTo(150);
    await tester.pumpAndSettle();

    final start = const Offset(kRowHeaderWidth + 89, 20);

    await tester.timedDragFrom(start, const Offset(20, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final resizedWidth = controller.tableDataController.columns.value.getHeaderExtentFor(index: 1);
    expect(resizedWidth, closeTo(kDefaultCellWidth + 20, 0.1));
  });

  testWidgets('dragging in the body selects a cell range from the drag origin', (tester) async {
    final controller = _TestSwayzeController(columnCount: 4, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final start = const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20);
    final end = const Offset(kRowHeaderWidth + 150, kColumnHeaderHeight + 70);

    await tester.timedDragFrom(start, end - start, const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection;
    expect(selection, isA<CellUserSelectionModel>());

    final cellSelection = selection as CellUserSelectionModel;
    expect(cellSelection.anchor, const IntVector2(0, 0));
    expect(cellSelection.focus, const IntVector2(1, 1));
  });

  testWidgets('dragging past the table edge expands when elastic expansion is enabled', (tester) async {
    final controller = _TestSwayzeController(columnCount: 4, rowCount: 4);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final start = const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20);
    final end = const Offset(kRowHeaderWidth + 650, kColumnHeaderHeight + 350);

    await tester.timedDragFrom(start, end - start, const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection as CellUserSelectionModel;
    expect(selection.focus.dx, greaterThan(3));
    expect(selection.focus.dy, greaterThan(3));
    expect(controller.tableDataController.columns.value.totalCount, greaterThan(4));
    expect(controller.tableDataController.rows.value.totalCount, greaterThan(4));
  });

  testWidgets('dragging past the table edge does not expand when elastic expansion is disabled', (tester) async {
    final controller = _TestSwayzeController(columnCount: 4, rowCount: 4, allowElasticExpansion: false);
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final start = const Offset(kRowHeaderWidth + 20, kColumnHeaderHeight + 20);
    final end = const Offset(kRowHeaderWidth + 650, kColumnHeaderHeight + 350);

    await tester.timedDragFrom(start, end - start, const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final selection = controller.selection.userSelectionState.primarySelection as CellUserSelectionModel;
    expect(selection.focus, const IntVector2(3, 3));
    expect(controller.tableDataController.columns.value.totalCount, 4);
    expect(controller.tableDataController.rows.value.totalCount, 4);
  });

  testWidgets('double tapping a column header auto fits the column', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [
        _TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'short'),
        _TestCellData(
          id: '1:0',
          position: IntVector2(0, 1),
          label: 'a much longer value that should grow the auto fit width well past the default size',
        ),
      ],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final header = const Offset(kRowHeaderWidth + 24, 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedWidth = controller.tableDataController.columns.value.getHeaderExtentFor(index: 0);
    expect(fittedWidth, greaterThan(kDefaultCellWidth));
  });

  testWidgets('double tapping a row header auto fits the row', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [_TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'line 1\nline 2\nline 3\nline 4\nline 5')],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final header = const Offset(20, kColumnHeaderHeight + 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedHeight = controller.tableDataController.rows.value.getHeaderExtentFor(index: 0);
    expect(fittedHeight, greaterThan(kDefaultCellHeight));
  });

  testWidgets('double tapping a column header auto fits using the header label width', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [_TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'x')],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        columnLabels: const {0: 'a very long header label that should drive auto fit width'},
      ),
    );
    await tester.pumpAndSettle();

    final header = const Offset(kRowHeaderWidth + 24, 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedWidth = controller.tableDataController.columns.value.getHeaderExtentFor(index: 0);
    expect(fittedWidth, greaterThan(kDefaultCellWidth));
  });

  testWidgets('double tapping a row header auto fit includes cell padding', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [_TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'padded')],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        cellDelegate: _TestCellDelegate(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18)),
      ),
    );
    await tester.pumpAndSettle();

    final header = const Offset(20, kColumnHeaderHeight + 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedHeight = controller.tableDataController.rows.value.getHeaderExtentFor(index: 0);
    expect(fittedHeight, greaterThan(kDefaultCellHeight));
  });

  testWidgets('double tapping a short row header auto fit keeps the default padded height', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [_TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'short')],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(controller: controller, focusNode: focusNode, verticalScrollController: verticalScrollController),
    );
    await tester.pumpAndSettle();

    final header = const Offset(20, kColumnHeaderHeight + 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedHeight = controller.tableDataController.rows.value.getHeaderExtentFor(index: 0);
    expect(fittedHeight, closeTo(kDefaultCellHeight, 0.1));
  });

  testWidgets('double tapping a column header auto fit honors the configured max extent', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [
        _TestCellData(
          id: '0:0',
          position: IntVector2(0, 0),
          label: 'a much longer value that should exceed the configured auto fit cap for the column',
        ),
      ],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        style: SwayzeStyle.defaultSwayzeStyle.copyWith(selectionAnimationDuration: Duration.zero, maxAutoFitColumnExtent: 90),
      ),
    );
    await tester.pumpAndSettle();

    final header = const Offset(kRowHeaderWidth + 24, 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedWidth = controller.tableDataController.columns.value.getHeaderExtentFor(index: 0);
    expect(fittedWidth, lessThanOrEqualTo(90.1));
    expect(fittedWidth, greaterThan(80));
  });

  testWidgets('double tapping a row header auto fit honors the configured max extent', (tester) async {
    final controller = _TestSwayzeController(
      columnCount: 3,
      rowCount: 4,
      initialCells: const [
        _TestCellData(id: '0:0', position: IntVector2(0, 0), label: 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7'),
      ],
    );
    final focusNode = FocusNode(debugLabel: 'swayze-test');
    final verticalScrollController = ScrollController();

    addTearDown(() {
      verticalScrollController.dispose();
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestTableApp(
        controller: controller,
        focusNode: focusNode,
        verticalScrollController: verticalScrollController,
        style: SwayzeStyle.defaultSwayzeStyle.copyWith(selectionAnimationDuration: Duration.zero, maxAutoFitRowExtent: 70),
      ),
    );
    await tester.pumpAndSettle();

    final header = const Offset(20, kColumnHeaderHeight + 20);

    await _doubleTapAt(tester, header);
    await tester.pumpAndSettle();

    final fittedHeight = controller.tableDataController.rows.value.getHeaderExtentFor(index: 0);
    expect(fittedHeight, lessThanOrEqualTo(70.1));
    expect(fittedHeight, greaterThan(60));
  });
}

class _TestTableApp extends StatelessWidget {
  _TestTableApp({
    required this.controller,
    required this.focusNode,
    required this.verticalScrollController,
    CellDelegate<_TestCellData>? cellDelegate,
    this.outsideFocusNode,
    this.columnLabels,
    this.style,
  }) : cellDelegate = cellDelegate ?? _TestCellDelegate();

  final _TestSwayzeController controller;
  final FocusNode focusNode;
  final ScrollController verticalScrollController;
  final CellDelegate<_TestCellData> cellDelegate;
  final FocusNode? outsideFocusNode;
  final Map<int, String>? columnLabels;
  final SwayzeStyle? style;

  @override
  Widget build(BuildContext context) {
    final table = SliverSwayzeTable<_TestCellData>(
      controller: controller,
      focusNode: focusNode,
      verticalScrollController: verticalScrollController,
      style: style ?? SwayzeStyle.defaultSwayzeStyle.copyWith(selectionAnimationDuration: Duration.zero),
      inlineEditorBuilder:
          (
            BuildContext context,
            IntVector2 coordinate,
            VoidCallback requestClose, {
            required bool overlapCell,
            required bool overlapTable,
            String? initialText,
          }) {
            return const SizedBox.shrink();
          },
      cellDelegate: cellDelegate,
    );

    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (outsideFocusNode != null) Focus(focusNode: outsideFocusNode, child: const SizedBox(width: 1, height: 1)),
            Expanded(
              child: CustomScrollView(
                controller: verticalScrollController,
                slivers: [columnLabels == null ? table : SwayzeHeaderLabelScope(columnLabels: columnLabels!, child: table)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
}

class _TestSwayzeController extends SwayzeController {
  _TestSwayzeController({
    required int columnCount,
    required int rowCount,
    this.allowElasticExpansion = true,
    Iterable<_TestCellData>? initialCells,
  }) {
    tableDataController = SwayzeTableDataController<_TestSwayzeController>(
      parent: this,
      id: 'test-table',
      columnCount: columnCount,
      rowCount: rowCount,
      columns: const [],
      rows: const [],
      frozenColumns: 0,
      frozenRows: 0,
      allowElasticExpansion: allowElasticExpansion,
    );
    cellsController = SwayzeCellsController<_TestCellData>(
      parent: this,
      cellParser: (rawCell) => rawCell as _TestCellData,
      initialRawCells:
          initialCells ??
          [
            for (var row = 0; row < rowCount; row++)
              for (var column = 0; column < columnCount; column++)
                _TestCellData(id: '$row:$column', position: IntVector2(column, row), label: '$row:$column'),
          ],
    );
  }

  final bool allowElasticExpansion;

  @override
  late final SwayzeCellsController<_TestCellData> cellsController;

  @override
  late final SwayzeTableDataController<_TestSwayzeController> tableDataController;

  @override
  void dispose() {
    cellsController.dispose();
    tableDataController.dispose();
    super.dispose();
  }
}

class _TestCellData extends SwayzeCellData {
  const _TestCellData({required super.id, required super.position, required this.label});

  final String label;

  @override
  Alignment get contentAlignment => Alignment.centerLeft;

  @override
  bool get hasVisibleContent => label.isNotEmpty;
}

class _TestCellDelegate extends CellDelegate<_TestCellData> {
  _TestCellDelegate({this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  CellLayout getCellLayout(_TestCellData data) => _TestCellLayout(data, padding);
}

class _TestCellLayout extends CellLayout {
  _TestCellLayout(this.data, this.padding);

  final _TestCellData data;
  final EdgeInsets padding;

  @override
  Widget buildCell(BuildContext context, {bool isHover = false, bool isActive = false}) {
    return Padding(
      padding: padding,
      child: Align(alignment: data.contentAlignment, child: Text(data.label)),
    );
  }

  @override
  Iterable<Widget> buildOverlayWidgets(BuildContext context, {bool isHover = false, bool isActive = false}) {
    return const [];
  }

  @override
  bool get isActiveCellAware => false;

  @override
  bool get isHoverAware => false;
}
