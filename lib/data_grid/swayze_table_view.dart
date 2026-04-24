import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/controller.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/delegates.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/helpers.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/config.dart' as swayze_config;
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/core/internal_state/table_focus/table_focus_provider.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/widgets/headers/header_label_scope.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/widgets.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze_math/swayze_math.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SwayzeTableView extends StatefulWidget {
  const SwayzeTableView({
    super.key,
    required this.room,
    required this.tableName,
    required this.namespace,
    this.filter,
    this.branch,
    this.version,
    this.reloadToken = 0,
    this.autoSizeHorizontally = false,
    this.autoSizeVertically = false,
    this.autoSizeColumns = false,
    this.autoSizeRows = false,
    this.maxAutoSizeColumnExtent = 300,
    this.maxAutoSizeRowExtent = 300,
    this.showLeadingOuterBorders = false,
    this.showRowHeaders = true,
  });

  final RoomClient room;
  final String tableName;
  final List<String>? namespace;
  final String? filter;
  final String? branch;
  final int? version;
  final int reloadToken;
  final bool autoSizeHorizontally;
  final bool autoSizeVertically;
  final bool autoSizeColumns;
  final bool autoSizeRows;
  final double? maxAutoSizeColumnExtent;
  final double? maxAutoSizeRowExtent;
  final bool showLeadingOuterBorders;
  final bool showRowHeaders;

  @override
  State<SwayzeTableView> createState() => _SwayzeTableViewState();
}

class _SwayzeTableViewState extends State<SwayzeTableView> {
  StreamSubscription<List<Map<String, dynamic>>>? _rowsSubscription;
  _SharedSwayzeController? _controller;
  Object? _error;
  List<String> _columns = const [];
  int _skippedBinaryCount = 0;
  int? _rowCount;
  int _loadedRowCount = 0;
  bool _isLoadingMetadata = true;
  bool _isLoadingRows = false;
  int _loadGeneration = 0;

  String? get _normalizedFilter {
    final trimmed = widget.filter?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant SwayzeTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room ||
        oldWidget.tableName != widget.tableName ||
        !listEquals(oldWidget.namespace, widget.namespace) ||
        oldWidget.filter != widget.filter ||
        oldWidget.branch != widget.branch ||
        oldWidget.version != widget.version ||
        oldWidget.reloadToken != widget.reloadToken) {
      _reload();
    }
  }

  @override
  void dispose() {
    _rowsSubscription?.cancel();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    final previousSubscription = _rowsSubscription;
    _rowsSubscription = null;
    if (previousSubscription != null) {
      await previousSubscription.cancel();
    }
    _disposeController();

    if (mounted) {
      setState(() {
        _error = null;
        _columns = const [];
        _skippedBinaryCount = 0;
        _rowCount = null;
        _loadedRowCount = 0;
        _isLoadingMetadata = true;
        _isLoadingRows = false;
      });
    }

    try {
      final schema = await widget.room.database.inspect(
        widget.tableName,
        namespace: widget.namespace,
        branch: widget.branch,
        version: widget.version,
      );
      final columns = _selectableColumns(schema);
      final rowCount = await widget.room.database.count(
        table: widget.tableName,
        where: _normalizedFilter,
        namespace: widget.namespace,
        branch: widget.branch,
        version: widget.version,
      );

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final controller = columns.isNotEmpty && rowCount > 0
          ? _SharedSwayzeController(
              id: 'room-table:${widget.namespace?.join("/") ?? ""}:${widget.tableName}',
              columns: columns,
              rowCount: rowCount,
            )
          : null;

      setState(() {
        _controller = controller;
        _columns = columns;
        _skippedBinaryCount = _skippedBinaryColumnCount(schema);
        _rowCount = rowCount;
        _loadedRowCount = 0;
        _isLoadingMetadata = false;
        _isLoadingRows = controller != null;
      });

      if (controller == null) {
        return;
      }

      var rowOffset = 0;
      _rowsSubscription = widget.room.database
          .searchStream(
            table: widget.tableName,
            where: _normalizedFilter,
            select: columns,
            namespace: widget.namespace,
            branch: widget.branch,
            version: widget.version,
          )
          .listen(
            (chunk) {
              if (!mounted || generation != _loadGeneration || chunk.isEmpty) {
                return;
              }

              controller.cellsController.updateState((modifier) {
                for (var rowIndex = 0; rowIndex < chunk.length; rowIndex++) {
                  final absoluteRow = rowOffset + rowIndex;
                  final row = chunk[rowIndex];
                  for (var columnIndex = 0; columnIndex < columns.length; columnIndex++) {
                    final columnName = columns[columnIndex];
                    modifier.putCell(
                      _SharedSwayzeCellData(
                        id: '$absoluteRow:$columnIndex',
                        position: IntVector2(columnIndex, absoluteRow),
                        value: row[columnName],
                        dataType: schema[columnName]!,
                      ),
                    );
                  }
                }
              });

              rowOffset += chunk.length;
              setState(() {
                _loadedRowCount = rowOffset;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || generation != _loadGeneration) {
                return;
              }
              setState(() {
                _error = error;
                _isLoadingRows = false;
              });
            },
            onDone: () {
              if (!mounted || generation != _loadGeneration) {
                return;
              }
              setState(() {
                _isLoadingRows = false;
              });
            },
            cancelOnError: false,
          );
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _error = error;
        _isLoadingMetadata = false;
        _isLoadingRows = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderColor = theme.cardTheme.border?.bottom?.color ?? theme.colorScheme.border;
    final rowCount = _rowCount;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: ShadAlert.destructive(title: const Text('Unable to query table'), description: Text(_error.toString())),
        ),
      );
    }

    if (_isLoadingMetadata || rowCount == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Row Count: $rowCount'),
              if (_isLoadingRows) Text('Loaded $_loadedRowCount/$rowCount', style: theme.textTheme.muted),
              if (_isLoadingRows) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              if (_skippedBinaryCount > 0)
                Text(
                  'Skipping $_skippedBinaryCount binary ${_skippedBinaryCount == 1 ? "column" : "columns"}',
                  style: theme.textTheme.muted,
                ),
            ],
          ),
        ),
        if (_columns.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'This table only has binary columns. Query results are omitted to avoid large payloads.',
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (rowCount == 0)
          Expanded(
            child: Center(
              child: Text(_normalizedFilter == null ? 'No rows' : 'No rows match the current filter.', style: theme.textTheme.muted),
            ),
          )
        else if (_controller == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: _SharedSwayzeGrid(
              controller: _controller!,
              columns: _columns,
              availableRowCount: _loadedRowCount,
              autoSizeHorizontally: widget.autoSizeHorizontally,
              autoSizeVertically: widget.autoSizeVertically,
              autoSizeColumns: widget.autoSizeColumns,
              autoSizeRows: widget.autoSizeRows,
              maxAutoSizeColumnExtent: widget.maxAutoSizeColumnExtent,
              maxAutoSizeRowExtent: widget.maxAutoSizeRowExtent,
              showLeadingOuterBorders: widget.showLeadingOuterBorders,
              showRowHeaders: widget.showRowHeaders,
            ),
          ),
      ],
    );
  }
}

class InMemoryTable extends StatefulWidget {
  const InMemoryTable({
    super.key,
    required this.columns,
    required this.rows,
    this.maxHeight = 420,
    this.autoSizeHorizontally = false,
    this.autoSizeVertically = false,
    this.autoSizeColumns = false,
    this.autoSizeRows = false,
    this.maxAutoSizeColumnExtent = 300,
    this.maxAutoSizeRowExtent = 300,
    this.showLeadingOuterBorders = false,
    this.showRowHeaders = true,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final double maxHeight;
  final bool autoSizeHorizontally;
  final bool autoSizeVertically;
  final bool autoSizeColumns;
  final bool autoSizeRows;
  final double? maxAutoSizeColumnExtent;
  final double? maxAutoSizeRowExtent;
  final bool showLeadingOuterBorders;
  final bool showRowHeaders;

  @override
  State<InMemoryTable> createState() => _InMemoryTableState();
}

class _InMemoryTableState extends State<InMemoryTable> {
  _SharedSwayzeController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant InMemoryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.columns, widget.columns) || !_rowsEqual(oldWidget.rows, widget.rows)) {
      final previousController = _controller;
      final nextController = _createController();
      setState(() {
        _controller = nextController;
      });
      previousController?.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  _SharedSwayzeController? _createController() {
    if (widget.columns.isEmpty) {
      return null;
    }

    final controller = _SharedSwayzeController(
      id: 'in-memory-table:${identityHashCode(this)}',
      columns: widget.columns,
      rowCount: widget.rows.length,
    );

    controller.cellsController.updateState((modifier) {
      for (var rowIndex = 0; rowIndex < widget.rows.length; rowIndex++) {
        final row = widget.rows[rowIndex];
        for (var columnIndex = 0; columnIndex < widget.columns.length; columnIndex++) {
          final value = columnIndex < row.length ? row[columnIndex] : '';
          modifier.putCell(
            _SharedSwayzeCellData(
              id: '$rowIndex:$columnIndex',
              position: IntVector2(columnIndex, rowIndex),
              value: value,
              dataType: TextDataType(),
            ),
          );
        }
      }
    });

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _SharedSwayzeGrid(
        controller: controller,
        columns: widget.columns,
        availableRowCount: widget.rows.length,
        maxHeight: widget.maxHeight,
        autoSizeHorizontally: widget.autoSizeHorizontally,
        autoSizeVertically: widget.autoSizeVertically,
        autoSizeColumns: widget.autoSizeColumns,
        autoSizeRows: widget.autoSizeRows,
        maxAutoSizeColumnExtent: widget.maxAutoSizeColumnExtent,
        maxAutoSizeRowExtent: widget.maxAutoSizeRowExtent,
        showLeadingOuterBorders: widget.showLeadingOuterBorders,
        showRowHeaders: widget.showRowHeaders,
      ),
    );
  }
}

class _SharedSwayzeGrid extends StatefulWidget {
  const _SharedSwayzeGrid({
    required this.controller,
    required this.columns,
    required this.availableRowCount,
    this.maxHeight,
    this.autoSizeHorizontally = false,
    this.autoSizeVertically = false,
    this.autoSizeColumns = false,
    this.autoSizeRows = false,
    this.maxAutoSizeColumnExtent = 300,
    this.maxAutoSizeRowExtent = 300,
    this.showLeadingOuterBorders = false,
    this.showRowHeaders = true,
  });

  final _SharedSwayzeController controller;
  final List<String> columns;
  final int availableRowCount;
  final double? maxHeight;
  final bool autoSizeHorizontally;
  final bool autoSizeVertically;
  final bool autoSizeColumns;
  final bool autoSizeRows;
  final double? maxAutoSizeColumnExtent;
  final double? maxAutoSizeRowExtent;
  final bool showLeadingOuterBorders;
  final bool showRowHeaders;

  @override
  State<_SharedSwayzeGrid> createState() => _SharedSwayzeGridState();
}

class _SharedSwayzeGridState extends State<_SharedSwayzeGrid> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'swayze-grid');
  final ScrollController _verticalScrollController = ScrollController();
  int? _lastAutoFitSignature;

  bool get _effectiveAutoSizeRows => widget.autoSizeRows || widget.autoSizeColumns;

  bool get _wrapCellText => _effectiveAutoSizeRows;

  int _buildAutoFitSignature(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tableTheme = theme.tableTheme;
    final headerTextStyle = tableTheme.cellHeaderStyle ?? theme.textTheme.muted.copyWith(fontWeight: FontWeight.w500);
    final cellTextStyle = tableTheme.cellStyle ?? theme.textTheme.muted.copyWith(color: theme.colorScheme.foreground);
    final cellPadding = _resolveGridCellPadding(context, tableTheme);
    final columnHeaderPadding = _resolveColumnHeaderPadding(cellPadding);
    return Object.hash(
      widget.controller,
      widget.availableRowCount,
      widget.autoSizeColumns,
      widget.autoSizeRows,
      widget.maxAutoSizeColumnExtent,
      widget.maxAutoSizeRowExtent,
      Object.hashAll(widget.columns),
      headerTextStyle,
      cellTextStyle,
      cellPadding,
      columnHeaderPadding,
      Directionality.of(context),
      MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    );
  }

  _SharedSwayzeCellDelegate get _cellDelegate {
    return _SharedSwayzeCellDelegate(controller: widget.controller, onCopySelection: _copySelectionToClipboard, wrapText: _wrapCellText);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyAutoSizingIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant _SharedSwayzeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.availableRowCount != widget.availableRowCount ||
        oldWidget.autoSizeColumns != widget.autoSizeColumns ||
        oldWidget.autoSizeRows != widget.autoSizeRows ||
        oldWidget.maxAutoSizeColumnExtent != widget.maxAutoSizeColumnExtent ||
        oldWidget.maxAutoSizeRowExtent != widget.maxAutoSizeRowExtent ||
        !listEquals(oldWidget.columns, widget.columns)) {
      _applyAutoSizingIfNeeded(force: true);
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelectionToClipboard() {
    return _copyControllerSelectionToClipboard(widget.controller, availableRowCount: widget.availableRowCount);
  }

  void _applyAutoSizingIfNeeded({bool force = false}) {
    final autoFitEnabled = widget.autoSizeColumns || _effectiveAutoSizeRows;
    final signature = _buildAutoFitSignature(context);
    if (!force && _lastAutoFitSignature == signature) {
      return;
    }

    _lastAutoFitSignature = signature;
    if (!autoFitEnabled) {
      return;
    }

    final style = _buildSwayzeStyle(
      context,
      showLeadingOuterBorders: widget.showLeadingOuterBorders,
      maxAutoFitColumnExtent: widget.maxAutoSizeColumnExtent,
      maxAutoFitRowExtent: widget.maxAutoSizeRowExtent,
    );
    List<double>? resolvedColumnExtents;
    if (widget.autoSizeColumns) {
      resolvedColumnExtents = _applyAutoSizeColumns(style);
    }
    if (_effectiveAutoSizeRows) {
      _applyAutoSizeRows(style, resolvedColumnExtents: resolvedColumnExtents);
    }
  }

  List<double> _applyAutoSizeColumns(SwayzeStyle style) {
    final columnCount = widget.columns.length;
    if (columnCount <= 0) {
      return const [];
    }

    final theme = ShadTheme.of(context);
    final tableTheme = theme.tableTheme;
    final cellTextStyle = tableTheme.cellStyle ?? theme.textTheme.muted.copyWith(color: theme.colorScheme.foreground);
    final cellPadding = _resolveGridCellPadding(context, tableTheme);
    final columnExtents = List<double>.generate(
      columnCount,
      (index) => _measureHeaderMainAxisExtent(_headerLabelFor(Axis.horizontal, index), style, Axis.horizontal),
      growable: false,
    );

    widget.controller.cellsController.cellMatrixReadOnly.forEach((item, colIndex, rowIndex) {
      if (rowIndex >= widget.availableRowCount || colIndex >= columnCount) {
        return;
      }

      final cellData = item;
      if (!cellData.hasVisibleContent) {
        return;
      }

      final cellExtent = _measureSingleLineCellMainAxisExtent(cellData.preview, cellTextStyle, cellPadding, Axis.horizontal);
      if (cellExtent > columnExtents[colIndex]) {
        columnExtents[colIndex] = cellExtent;
      }
    });

    final resolvedColumnExtents = _resolveMeasuredExtents(
      axis: Axis.horizontal,
      extents: columnExtents,
      lineWidth: style.cellSeparatorStrokeWidth,
      maxExtent: widget.maxAutoSizeColumnExtent,
    );
    _applyResolvedExtents(axis: Axis.horizontal, extents: resolvedColumnExtents);
    return resolvedColumnExtents;
  }

  void _applyAutoSizeRows(SwayzeStyle style, {List<double>? resolvedColumnExtents}) {
    final rowCount = math.min(widget.availableRowCount, widget.controller.tableDataController.rows.value.count);
    if (rowCount <= 0) {
      return;
    }

    final theme = ShadTheme.of(context);
    final tableTheme = theme.tableTheme;
    final cellTextStyle = tableTheme.cellStyle ?? theme.textTheme.muted.copyWith(color: theme.colorScheme.foreground);
    final cellPadding = _resolveGridCellPadding(context, tableTheme);
    final minimumRowContentExtent = math.max(
      widget.controller.tableDataController.rows.value.defaultHeaderExtent - style.cellSeparatorStrokeWidth,
      _measureSingleLineCellMainAxisExtent(_kAutoFitMeasurementSampleText, cellTextStyle, cellPadding, Axis.vertical),
    );
    final rowExtents = List<double>.generate(
      rowCount,
      (index) =>
          math.max(_measureHeaderMainAxisExtent(_headerLabelFor(Axis.vertical, index), style, Axis.vertical), minimumRowContentExtent),
      growable: false,
    );

    widget.controller.cellsController.cellMatrixReadOnly.forEach((item, colIndex, rowIndex) {
      if (rowIndex >= rowCount || colIndex >= widget.columns.length) {
        return;
      }

      final cellData = item;
      if (!cellData.hasVisibleContent) {
        return;
      }

      final columnExtent = resolvedColumnExtents != null && colIndex < resolvedColumnExtents.length
          ? resolvedColumnExtents[colIndex]
          : widget.controller.tableDataController.columns.value.getHeaderExtentFor(index: colIndex);
      final cellExtent = _measureWrappedCellHeight(
        cellData.preview,
        style: cellTextStyle,
        padding: cellPadding,
        columnExtent: columnExtent,
        lineWidth: style.cellSeparatorStrokeWidth,
      );
      if (cellExtent > rowExtents[rowIndex]) {
        rowExtents[rowIndex] = cellExtent;
      }
    });

    final resolvedRowExtents = _resolveMeasuredExtents(
      axis: Axis.vertical,
      extents: rowExtents,
      lineWidth: style.cellSeparatorStrokeWidth,
      maxExtent: widget.maxAutoSizeRowExtent,
    );
    _applyResolvedExtents(axis: Axis.vertical, extents: resolvedRowExtents);
  }

  List<double> _resolveMeasuredExtents({
    required Axis axis,
    required List<double> extents,
    required double lineWidth,
    required double? maxExtent,
  }) {
    return [
      for (final extent in extents)
        (maxExtent == null ? extent + lineWidth : math.min(extent + lineWidth, maxExtent)).clamp(
          minimumResizableExtentForAxis(axis),
          double.infinity,
        ),
    ];
  }

  void _applyResolvedExtents({required Axis axis, required List<double> extents}) {
    final headerController = widget.controller.tableDataController.getHeaderControllerFor(axis: axis);
    headerController.updateState((state) {
      var nextState = state;
      for (var index = 0; index < extents.length; index++) {
        final extent = extents[index];
        final currentExtent = nextState.getHeaderExtentFor(index: index);
        if ((currentExtent - extent).abs() < 0.001) {
          continue;
        }
        nextState = nextState.setHeaderExtent(index, extent);
      }
      return nextState;
    });
  }

  String _headerLabelFor(Axis axis, int index) {
    if (axis == Axis.horizontal) {
      return widget.columns[index];
    }
    return generateLabelForIndex(axis, index);
  }

  double _measureHeaderMainAxisExtent(String text, SwayzeStyle style, Axis axis) {
    final size = _measureText(text, style.headerTextStyle);
    final padding = axis == Axis.horizontal ? style.columnHeaderPadding : style.rowHeaderPadding;
    return axis == Axis.horizontal ? size.width + padding.horizontal : size.height + padding.vertical;
  }

  double _measureSingleLineCellMainAxisExtent(String text, TextStyle? style, EdgeInsets padding, Axis axis) {
    final size = _measureText(text, style);
    return axis == Axis.horizontal ? size.width + padding.horizontal : size.height.ceilToDouble() + padding.vertical;
  }

  double _measureWrappedCellHeight(
    String text, {
    required TextStyle? style,
    required EdgeInsets padding,
    required double columnExtent,
    required double lineWidth,
  }) {
    final displayText = _displayTextForAvailableWidth(text, columnExtent);
    final shouldWrapText = displayText != '...' && _wrapCellText;
    final effectivePadding = _resolveGridCellPaddingForTextLayout(
      context,
      text: displayText,
      style: style,
      padding: padding,
      maxWidth: math.max(0.0, columnExtent - lineWidth),
      shouldWrapText: shouldWrapText,
    );
    final availableTextWidth = math.max(0.0, columnExtent - lineWidth - effectivePadding.horizontal);
    final size = _measureText(
      displayText,
      style,
      maxWidth: availableTextWidth,
      maxLines: shouldWrapText ? null : 1,
      ellipsis: shouldWrapText ? null : '...',
    );
    return size.height.ceilToDouble() + effectivePadding.vertical;
  }

  String _displayTextForAvailableWidth(String text, double width) {
    if (width.isFinite && width <= _kMinimumReadableCellWidth && text.isNotEmpty) {
      return '...';
    }
    return text;
  }

  Size _measureText(String text, TextStyle? style, {double maxWidth = double.infinity, int? maxLines = 1, String? ellipsis = '...'}) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: maxLines,
      ellipsis: ellipsis,
    )..layout(maxWidth: maxWidth);
    return textPainter.size;
  }

  @override
  Widget build(BuildContext context) {
    final style = _buildSwayzeStyle(
      context,
      showLeadingOuterBorders: widget.showLeadingOuterBorders,
      maxAutoFitColumnExtent: widget.maxAutoSizeColumnExtent,
      maxAutoFitRowExtent: widget.maxAutoSizeRowExtent,
    );
    final controllerAnimation = Listenable.merge([
      widget.controller.tableDataController.columns,
      widget.controller.tableDataController.rows,
    ]);

    final grid = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          unawaited(_copySelectionToClipboard());
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          unawaited(_copySelectionToClipboard());
        },
      },
      child: SwayzeHeaderLabelScope(
        columnLabels: {for (var index = 0; index < widget.columns.length; index++) index: widget.columns[index]},
        child: CustomScrollView(
          controller: _verticalScrollController,
          primary: false,
          physics: widget.autoSizeVertically ? const NeverScrollableScrollPhysics() : null,
          slivers: [
            SliverSwayzeTable<_SharedSwayzeCellData>(
              controller: widget.controller,
              focusNode: _focusNode,
              verticalScrollController: _verticalScrollController,
              horizontalScrollPhysics: widget.autoSizeHorizontally ? const NeverScrollableScrollPhysics() : null,
              style: style,
              showRowHeaders: widget.showRowHeaders,
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
              cellDelegate: _cellDelegate,
            ),
          ],
        ),
      ),
    );

    if (!widget.autoSizeHorizontally && !widget.autoSizeVertically && widget.maxHeight == null) {
      return grid;
    }

    return AnimatedBuilder(
      animation: controllerAnimation,
      builder: (context, _) {
        final resolvedWidth = _resolveGridWidth(
          controller: widget.controller,
          style: style,
          autoSizeHorizontally: widget.autoSizeHorizontally,
          showRowHeaders: widget.showRowHeaders,
        );
        final resolvedHeight = _resolveGridHeight(
          controller: widget.controller,
          lineWidth: style.cellSeparatorStrokeWidth,
          maxHeight: widget.maxHeight,
          autoSizeVertically: widget.autoSizeVertically,
        );

        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: resolvedWidth, height: resolvedHeight, child: grid),
        );
      },
    );
  }
}

SwayzeStyle _buildSwayzeStyle(
  BuildContext context, {
  required bool showLeadingOuterBorders,
  required double? maxAutoFitColumnExtent,
  required double? maxAutoFitRowExtent,
}) {
  final theme = ShadTheme.of(context);
  final tableTheme = theme.tableTheme;
  final borderColor = theme.cardTheme.border?.bottom?.color ?? theme.colorScheme.border;
  final mutedForeground = theme.colorScheme.mutedForeground;
  final foreground = theme.colorScheme.foreground;
  final chromeBackground = _tableChromeBackground(theme);
  final cellBackground = _tableCellBackground(theme);
  final headerTextStyle = tableTheme.cellHeaderStyle ?? theme.textTheme.muted.copyWith(fontWeight: FontWeight.w500);
  final cellPadding = _resolveGridCellPadding(context, tableTheme);

  return SwayzeStyle.defaultSwayzeStyle.copyWith(
    defaultHeaderPalette: SwayzeHeaderPalette(background: chromeBackground, foreground: mutedForeground),
    selectedHeaderPalette: SwayzeHeaderPalette(background: theme.colorScheme.primary.withValues(alpha: 0.18), foreground: foreground),
    highlightedHeaderPalette: SwayzeHeaderPalette(background: theme.colorScheme.accent.withValues(alpha: 0.12), foreground: foreground),
    headerSeparatorColor: borderColor,
    headerTextStyle: headerTextStyle,
    columnHeaderPadding: _resolveColumnHeaderPadding(cellPadding),
    maxAutoFitColumnExtent: maxAutoFitColumnExtent,
    maxAutoFitRowExtent: maxAutoFitRowExtent,
    showLeadingOuterBorders: showLeadingOuterBorders,
    defaultCellBackground: cellBackground,
    cellSeparatorColor: borderColor,
    userSelectionStyle: SelectionStyle.semiTransparent(color: theme.colorScheme.primary),
    // Immediate updates keep range selection visually attached to the pointer
    // and avoid lag when the viewport scrolls.
    selectionAnimationDuration: Duration.zero,
  );
}

Color _tableChromeBackground(ShadThemeData theme) {
  return theme.decoration.color ?? theme.colorScheme.background;
}

Color _tableCellBackground(ShadThemeData theme) {
  return theme.cardTheme.backgroundColor ?? theme.colorScheme.background;
}

double _resolveTableLeadingWidth(_SharedSwayzeController controller, SwayzeStyle style, {required bool showRowHeaders}) {
  if (showRowHeaders) {
    return swayze_config.headerWidthForRange(Range(0, controller.tableDataController.rows.value.totalCount));
  }

  if (!style.showLeadingOuterBorders || style.cellSeparatorColor.a == 0.0) {
    return 0.0;
  }
  return style.cellSeparatorStrokeWidth;
}

double? _resolveGridWidth({
  required _SharedSwayzeController controller,
  required SwayzeStyle style,
  required bool autoSizeHorizontally,
  required bool showRowHeaders,
}) {
  if (!autoSizeHorizontally) {
    return null;
  }

  return controller.tableDataController.columns.value.extent +
      _resolveTableLeadingWidth(controller, style, showRowHeaders: showRowHeaders) +
      style.cellSeparatorStrokeWidth;
}

double? _resolveGridHeight({
  required _SharedSwayzeController controller,
  required double lineWidth,
  required double? maxHeight,
  required bool autoSizeVertically,
}) {
  final minimumHeight = swayze_config.kColumnHeaderHeight + lineWidth;
  final contentHeight = controller.tableDataController.rows.value.extent + minimumHeight;

  if (autoSizeVertically) {
    return math.max(minimumHeight, contentHeight);
  }

  if (maxHeight == null) {
    return null;
  }

  return math.min(maxHeight, math.max(minimumHeight, contentHeight));
}

bool _isLikelyBinaryPayloadColumn({required String columnName, required DataType dataType}) {
  if (dataType is BinaryDataType) {
    return true;
  }

  final json = dataType.toJson();
  final type = json['type'];
  if (type is String) {
    final normalizedType = type.toLowerCase();
    if (normalizedType.contains('binary') || normalizedType.contains('blob')) {
      return true;
    }
  }

  if (dataType is ListDataType && dataType.elementType is IntDataType) {
    final normalizedName = columnName.toLowerCase();
    if (normalizedName == 'data' ||
        normalizedName == 'bytes' ||
        normalizedName.endsWith('_data') ||
        normalizedName.endsWith('_bytes') ||
        normalizedName.contains('binary') ||
        normalizedName.contains('blob')) {
      return true;
    }
  }

  return false;
}

List<String> _selectableColumns(Map<String, DataType> schema) {
  return schema.entries
      .where((entry) => !_isLikelyBinaryPayloadColumn(columnName: entry.key, dataType: entry.value))
      .map((entry) => entry.key)
      .toList(growable: false);
}

int _skippedBinaryColumnCount(Map<String, DataType> schema) {
  return schema.entries.where((entry) => _isLikelyBinaryPayloadColumn(columnName: entry.key, dataType: entry.value)).length;
}

class _SharedSwayzeController extends SwayzeController {
  _SharedSwayzeController({required String id, required List<String> columns, required int rowCount}) {
    tableDataController = SwayzeTableDataController<_SharedSwayzeController>(
      parent: this,
      id: id,
      columnCount: columns.length,
      rowCount: rowCount,
      columns: [
        for (var index = 0; index < columns.length; index++)
          SwayzeHeaderData(index: index, extent: _estimateColumnExtent(columns[index]), hidden: false),
      ],
      rows: const [],
      frozenColumns: 0,
      frozenRows: 0,
      allowElasticExpansion: false,
    );
    cellsController = SwayzeCellsController<_SharedSwayzeCellData>(
      parent: this,
      cellParser: (rawCell) {
        if (rawCell is! _SharedSwayzeCellData) {
          throw ArgumentError.value(rawCell, 'rawCell', 'Unexpected cell payload for Swayze.');
        }
        return rawCell;
      },
      initialRawCells: const [],
    );
  }

  @override
  late final SwayzeCellsController<_SharedSwayzeCellData> cellsController;

  @override
  late final SwayzeTableDataController<_SharedSwayzeController> tableDataController;

  @override
  void dispose() {
    cellsController.dispose();
    tableDataController.dispose();
    super.dispose();
  }
}

double _estimateColumnExtent(String columnName) {
  return math.min(320, math.max(160, columnName.length * 12 + 40)).toDouble();
}

class _SharedSwayzeCellData extends SwayzeCellData {
  const _SharedSwayzeCellData({required super.id, required super.position, required this.value, required this.dataType});

  final Object? value;
  final DataType dataType;

  bool get isNull => value == null;

  String get preview {
    final text = _stringifyTableValue(value, pretty: false);
    if (text.length <= 160) {
      return text;
    }
    return '${text.substring(0, 160)}...';
  }

  @override
  Alignment get contentAlignment {
    if (dataType is BoolDataType) {
      return Alignment.center;
    }
    if (dataType is IntDataType || dataType is FloatDataType) {
      return Alignment.centerRight;
    }
    return Alignment.centerLeft;
  }

  @override
  bool get hasVisibleContent {
    if (value == null) {
      return true;
    }
    return preview.isNotEmpty;
  }
}

const _kMinimumReadableCellWidth = 50.0;
const _kAutoFitMeasurementSampleText = 'Mg';

class _SharedSwayzeCellDelegate extends CellDelegate<_SharedSwayzeCellData> {
  _SharedSwayzeCellDelegate({required this.controller, required this.onCopySelection, required this.wrapText});

  final _SharedSwayzeController controller;
  final Future<void> Function() onCopySelection;
  final bool wrapText;

  @override
  CellLayout getCellLayout(_SharedSwayzeCellData data) {
    return _SharedSwayzeCellLayout(data, controller: controller, onCopySelection: onCopySelection, wrapText: wrapText);
  }
}

class _SharedSwayzeCellLayout extends CellLayout {
  _SharedSwayzeCellLayout(this.data, {required this.controller, required this.onCopySelection, required this.wrapText});

  final _SharedSwayzeCellData data;
  final _SharedSwayzeController controller;
  final Future<void> Function() onCopySelection;
  final bool wrapText;

  @override
  Widget buildCell(BuildContext context, {bool isHover = false, bool isActive = false}) {
    final theme = ShadTheme.of(context);
    final tableTheme = theme.tableTheme;
    final baseTextStyle = tableTheme.cellStyle ?? theme.textTheme.muted.copyWith(color: theme.colorScheme.foreground);
    final cellPadding = _resolveGridCellPadding(context, tableTheme);
    final textColor = data.isNull ? theme.colorScheme.mutedForeground : (baseTextStyle.color ?? theme.colorScheme.foreground);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldShowCompactIndicator =
            constraints.maxWidth.isFinite && constraints.maxWidth <= _kMinimumReadableCellWidth && data.preview.isNotEmpty;
        final displayText = shouldShowCompactIndicator ? '...' : data.preview;
        final shouldWrapText = wrapText && !shouldShowCompactIndicator && constraints.maxWidth.isFinite;
        final textStyle = baseTextStyle.copyWith(color: textColor);
        final effectivePadding = _resolveGridCellPaddingForTextLayout(
          context,
          text: displayText,
          style: textStyle,
          padding: cellPadding,
          maxWidth: constraints.maxWidth,
          shouldWrapText: shouldWrapText,
        );
        final wrappedTextLayout = _resolveWrappedTextLayout(
          context,
          text: displayText,
          style: textStyle,
          padding: effectivePadding,
          constraints: constraints,
          shouldWrapText: shouldWrapText,
        );
        final text = Text(
          displayText,
          maxLines: wrappedTextLayout.maxLines,
          overflow: wrappedTextLayout.overflow,
          softWrap: shouldWrapText,
          style: textStyle,
        );

        return _SharedSwayzeCellContextMenuRegion(
          data: data,
          controller: controller,
          onCopySelection: onCopySelection,
          child: SizedBox.expand(
            child: Padding(
              padding: effectivePadding,
              child: Align(alignment: data.contentAlignment, child: text),
            ),
          ),
        );
      },
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

class _WrappedTextLayout {
  const _WrappedTextLayout({required this.maxLines, required this.overflow});

  final int? maxLines;
  final TextOverflow overflow;
}

_WrappedTextLayout _resolveWrappedTextLayout(
  BuildContext context, {
  required String text,
  required TextStyle style,
  required EdgeInsets padding,
  required BoxConstraints constraints,
  required bool shouldWrapText,
}) {
  if (!shouldWrapText) {
    return const _WrappedTextLayout(maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  if (!constraints.maxHeight.isFinite) {
    return const _WrappedTextLayout(maxLines: null, overflow: TextOverflow.clip);
  }

  final availableTextWidth = math.max(0.0, constraints.maxWidth - padding.horizontal);
  final availableTextHeight = math.max(0.0, constraints.maxHeight - padding.vertical);
  if (availableTextWidth <= 0 || availableTextHeight <= 0) {
    return const _WrappedTextLayout(maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    maxLines: null,
  )..layout(maxWidth: availableTextWidth);

  if (textPainter.height <= availableTextHeight + 0.001) {
    return const _WrappedTextLayout(maxLines: null, overflow: TextOverflow.clip);
  }

  final lineMetrics = textPainter.computeLineMetrics();
  var fittingLineCount = 0;
  var usedHeight = 0.0;
  for (final lineMetric in lineMetrics) {
    final nextHeight = usedHeight + lineMetric.height;
    if (nextHeight > availableTextHeight + 0.001) {
      break;
    }
    usedHeight = nextHeight;
    fittingLineCount++;
  }

  return _WrappedTextLayout(maxLines: math.max(1, fittingLineCount), overflow: TextOverflow.ellipsis);
}

EdgeInsets _resolveGridCellPadding(BuildContext context, ShadTableTheme tableTheme) {
  return (tableTheme.cellPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)).resolve(Directionality.of(context));
}

EdgeInsets _resolveColumnHeaderPadding(EdgeInsets cellPadding) {
  return EdgeInsets.fromLTRB(cellPadding.left, 8, cellPadding.right, 8);
}

EdgeInsets _resolveGridCellPaddingForTextLayout(
  BuildContext context, {
  required String text,
  required TextStyle? style,
  required EdgeInsets padding,
  required double maxWidth,
  required bool shouldWrapText,
}) {
  if (!shouldWrapText || (padding.top > 0 || padding.bottom > 0)) {
    return padding;
  }

  final inferredVerticalInset = padding.horizontal / 2;
  if (inferredVerticalInset <= 0) {
    return padding;
  }

  final availableTextWidth = math.max(0.0, maxWidth - padding.horizontal);
  if (availableTextWidth <= 0) {
    return padding;
  }

  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    maxLines: null,
  )..layout(maxWidth: availableTextWidth);

  if (textPainter.computeLineMetrics().length <= 1) {
    return padding;
  }

  return EdgeInsets.fromLTRB(padding.left, inferredVerticalInset, padding.right, inferredVerticalInset);
}

class _SharedSwayzeCellContextMenuRegion extends StatefulWidget {
  const _SharedSwayzeCellContextMenuRegion({
    required this.data,
    required this.controller,
    required this.onCopySelection,
    required this.child,
  });

  final _SharedSwayzeCellData data;
  final _SharedSwayzeController controller;
  final Future<void> Function() onCopySelection;
  final Widget child;

  @override
  State<_SharedSwayzeCellContextMenuRegion> createState() => _SharedSwayzeCellContextMenuRegionState();
}

class _SharedSwayzeCellContextMenuRegionState extends State<_SharedSwayzeCellContextMenuRegion> {
  late final ShadContextMenuController _controller = ShadContextMenuController();
  Offset? _offset;
  bool _opening = false;
  final bool _isContextMenuAlreadyDisabled = kIsWeb && !BrowserContextMenu.enabled;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _primarySelectionContainsCell() {
    if (!widget.controller.selection.userSelectionState.hasVisibleSelection) {
      return false;
    }
    final selection = widget.controller.selection.userSelectionState.primarySelection.bound(
      to: widget.controller.tableDataController.tableRange,
    );
    return !selection.isNil && selection.containsVector(widget.data.position);
  }

  Future<void> _prepareSelection() async {
    TableFocus.of(context).requestFocus();

    if (_primarySelectionContainsCell()) {
      return;
    }

    widget.controller.selection.updateUserSelections(
      (state) => state.resetSelectionsToACellSelection(anchor: widget.data.position, focus: widget.data.position),
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _openAt(Offset offset) async {
    if (!mounted || _opening) {
      return;
    }

    _opening = true;
    setState(() {
      _offset = offset;
    });

    try {
      await _prepareSelection();
      if (!mounted) {
        return;
      }

      _controller.show();
    } finally {
      _opening = false;
    }
  }

  void _hide() {
    if (_controller.isOpen) {
      _controller.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final longPressEnabled = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    return CoordinatedShadContextMenu(
      anchor: _offset == null ? null : ShadGlobalAnchor(_offset!),
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 160),
      estimatedMenuWidth: 160,
      estimatedMenuHeight: 48,
      items: [
        ShadContextMenuItem(
          leading: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            _hide();
            await widget.onCopySelection();
          },
          child: const Text('Copy'),
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _hide(),
        onSecondaryTapDown: isWindows
            ? null
            : (details) async {
                if (kIsWeb && !_isContextMenuAlreadyDisabled) {
                  await BrowserContextMenu.disableContextMenu();
                }

                await _openAt(details.globalPosition);
              },
        onSecondaryTapUp: (details) async {
          if (isWindows) {
            await _openAt(details.globalPosition);
          }

          if (kIsWeb && !_isContextMenuAlreadyDisabled) {
            await BrowserContextMenu.enableContextMenu();
          }
        },
        onLongPressStart: longPressEnabled
            ? (details) {
                _offset = details.globalPosition;
              }
            : null,
        onLongPress: longPressEnabled
            ? () async {
                final offset = _offset;
                if (offset == null) {
                  return;
                }

                await _openAt(offset);
              }
            : null,
        child: widget.child,
      ),
    );
  }
}

Future<void> _copyControllerSelectionToClipboard(_SharedSwayzeController controller, {required int availableRowCount}) async {
  if (!controller.selection.userSelectionState.hasVisibleSelection) {
    return;
  }
  final selection = controller.selection.userSelectionState.primarySelection;
  final boundedSelection = selection.bound(to: controller.tableDataController.tableRange);

  if (boundedSelection.isNil) {
    return;
  }

  final rowRange = boundedSelection.yRange;
  final columnRange = boundedSelection.xRange;
  final rowLimit = math.min(rowRange.end, availableRowCount);

  if (rowLimit <= rowRange.start || columnRange.isNil) {
    return;
  }

  final cellMatrix = controller.cellsController.cellMatrixReadOnly;
  final lines = <String>[];
  for (var row = rowRange.start; row < rowLimit; row++) {
    final fields = <String>[];
    for (var column = columnRange.start; column < columnRange.end; column++) {
      final cell = cellMatrix[IntVector2(column, row)];
      fields.add(_clipboardFieldText(cell));
    }
    lines.add(fields.join('\t'));
  }

  if (lines.isEmpty) {
    return;
  }

  await Clipboard.setData(ClipboardData(text: lines.join('\n')));
}

String _stringifyTableValue(Object? value, {required bool pretty}) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
  try {
    return encoder.convert(value);
  } catch (_) {
    return '$value';
  }
}

String _clipboardFieldText(_SharedSwayzeCellData? cell) {
  if (cell == null) {
    return '';
  }

  final text = _stringifyTableValue(cell.value, pretty: false);
  if (text.contains('\t') || text.contains('\n') || text.contains('"')) {
    return '"${text.replaceAll('"', '""')}"';
  }

  return text;
}

bool _rowsEqual(List<List<String>> a, List<List<String>> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (!listEquals(a[index], b[index])) {
      return false;
    }
  }
  return true;
}
