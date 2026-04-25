import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../config.dart' as config;
import '../core/scrolling/pointer_scroll_handler.dart';
import '../core/scrolling/sliver_scrolling_data_builder.dart';
import '../core/viewport_context/viewport_context_provider.dart';
import '../core/virtualization/virtualization_calculator.dart';
import 'headers/header.dart';
import 'internal_scope.dart';
import 'table.dart';
import 'table_body/table_body.dart';
import 'wrappers.dart';

/// A [Widget] that layouts all the three main Table elements:
/// Vertical header, horizontal header and finally the main area.
///
/// For that it uses [CustomMultiChildLayout].
///
/// It is the first visual widget in the tree under the horizontal and vertical
/// scroll views. The widget itself is not scrolled since the custom sliver
/// [SliverScrollingDataBuilder] does not displace its children directly.
///
/// The scroll effect is performed by its direct children: [Header] and
/// [TableBody] by listening to range changes and applying the displacement
/// correction.
///
/// The layout is sensitive to the vertical virtualization state, since the row
/// header width expands as far as we scroll in the table.
class TableScaffold extends StatefulWidget {
  /// The offset to translate children to achieve pixel scrolling.
  ///
  /// See also:
  /// - [VirtualizationState.displacement].
  final double horizontalDisplacement;

  /// The offset to translate children to achieve pixel scrolling.
  ///
  /// See also:
  /// - [VirtualizationState.displacement].
  final double verticalDisplacement;

  /// See [SliverSwayzeTable.wrapTableBody]
  final WrapTableBodyBuilder? wrapTableBody;

  /// See [SliverSwayzeTable.wrapHeader]
  final WrapHeaderBuilder? wrapHeader;

  /// Whether to render row-number headers on the leading edge.
  final bool showRowHeaders;

  const TableScaffold({
    Key? key,
    required this.horizontalDisplacement,
    required this.verticalDisplacement,
    this.wrapTableBody,
    this.wrapHeader,
    this.showRowHeaders = true,
  }) : super(key: key);

  @override
  _TableScaffoldState createState() => _TableScaffoldState();
}

enum _TableScaffoldSlot { headerCorner, columnHeaders, rowsHeaders, tableBody }

class _TableScaffoldState extends State<TableScaffold> {
  late final viewportContext = ViewportContextProvider.of(context);
  late final verticalRangeNotifier = viewportContext.rows.virtualizationState.rangeNotifier;

  // The state for sizes of headers
  final double columnHeaderHeight = config.kColumnHeaderHeight;
  late double rowHeaderWidth = _resolveRowHeaderWidth();

  @override
  void initState() {
    super.initState();

    verticalRangeNotifier.addListener(didChangeVerticalRange);
    didChangeVerticalRange();
  }

  @override
  void didUpdateWidget(covariant TableScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showRowHeaders != widget.showRowHeaders) {
      didChangeVerticalRange();
    }
  }

  /// The scaffold adapts to changes in the width of the row headers for large
  /// numbers.
  /// For this is subscribe to changes in the vertical visible range and save
  /// the width into the state.
  void didChangeVerticalRange() {
    final newRowHeaderWidth = _resolveRowHeaderWidth();
    if (newRowHeaderWidth == rowHeaderWidth) {
      return;
    }
    setState(() {
      rowHeaderWidth = newRowHeaderWidth;
    });
  }

  double _resolveRowHeaderWidth() {
    if (widget.showRowHeaders) {
      return config.headerWidthForRange(verticalRangeNotifier.value);
    }

    final style = InternalScope.of(context).style;
    if (!style.showLeadingOuterBorders || style.cellSeparatorColor.a == 0.0) {
      return 0.0;
    }
    return style.cellSeparatorStrokeWidth;
  }

  @override
  void dispose() {
    verticalRangeNotifier.removeListener(didChangeVerticalRange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = CustomMultiChildLayout(
      delegate: _TableScaffoldDelegate(rowHeaderWidth, columnHeaderHeight),
      children: [
        if (widget.showRowHeaders) LayoutId(id: _TableScaffoldSlot.headerCorner, child: const _HeaderCorner()),
        LayoutId(
          id: _TableScaffoldSlot.columnHeaders,
          child: Header(axis: Axis.horizontal, displacement: widget.horizontalDisplacement, wrapHeader: widget.wrapHeader),
        ),
        if (widget.showRowHeaders)
          LayoutId(
            id: _TableScaffoldSlot.rowsHeaders,
            child: Header(axis: Axis.vertical, displacement: widget.verticalDisplacement, wrapHeader: widget.wrapHeader),
          ),
        LayoutId(
          id: _TableScaffoldSlot.tableBody,
          child: TableBody(
            horizontalDisplacement: widget.horizontalDisplacement,
            verticalDisplacement: widget.verticalDisplacement,
            wrapTableBody: widget.wrapTableBody,
          ),
        ),
      ],
    );

    final style = InternalScope.of(context).style;
    if (widget.showRowHeaders || !style.showLeadingOuterBorders) {
      return table;
    }

    return Stack(
      children: [
        table,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: style.cellSeparatorStrokeWidth,
          child: IgnorePointer(child: ColoredBox(color: style.cellSeparatorColor)),
        ),
      ],
    );
  }
}

/// A [MultiChildLayoutDelegate] that describe the layout rules for the three
/// main table elements: Vertical header, horizontal header and finally the main
/// table area.
class _TableScaffoldDelegate extends MultiChildLayoutDelegate {
  final double headerWidth;
  final double headerHeight;

  _TableScaffoldDelegate(this.headerWidth, this.headerHeight);

  @override
  void performLayout(Size size) {
    // The dimensions of the table area excluding the space covered by headers
    final remainingHeight = (size.height - headerHeight).clamp(0.0, size.height);
    final remainingWidth = (size.width - headerWidth).clamp(0.0, size.width);

    if (hasChild(_TableScaffoldSlot.headerCorner)) {
      layoutChild(_TableScaffoldSlot.headerCorner, BoxConstraints.tight(Size(headerWidth, headerHeight)));
      positionChild(_TableScaffoldSlot.headerCorner, Offset.zero);
    }

    if (hasChild(_TableScaffoldSlot.columnHeaders)) {
      final columnsSize = Size(remainingWidth, headerHeight);
      layoutChild(_TableScaffoldSlot.columnHeaders, BoxConstraints.tight(columnsSize));
      positionChild(_TableScaffoldSlot.columnHeaders, Offset(headerWidth, 0.0));
    }

    if (hasChild(_TableScaffoldSlot.rowsHeaders)) {
      final rowSize = Size(headerWidth, remainingHeight);

      layoutChild(_TableScaffoldSlot.rowsHeaders, BoxConstraints.tight(rowSize));
      positionChild(_TableScaffoldSlot.rowsHeaders, Offset(0, headerHeight));
    }

    if (hasChild(_TableScaffoldSlot.tableBody)) {
      final tableSize = Size(remainingWidth, remainingHeight);
      layoutChild(_TableScaffoldSlot.tableBody, BoxConstraints.tight(tableSize));
      positionChild(_TableScaffoldSlot.tableBody, Offset(headerWidth, headerHeight));
    }
  }

  @override
  bool shouldRelayout(_TableScaffoldDelegate oldDelegate) {
    return oldDelegate.headerWidth != headerWidth || oldDelegate.headerHeight != headerHeight;
  }
}

class _HeaderCorner extends StatelessWidget {
  const _HeaderCorner();

  @override
  Widget build(BuildContext context) {
    final style = InternalScope.of(context).style;
    final scrollController = InternalScope.of(context).controller.scroll;
    final horizontalScrollController = scrollController.horizontalScrollController;
    final verticalScrollController = scrollController.verticalScrollController;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (PointerSignalEvent event) {
        if (horizontalScrollController == null || verticalScrollController == null) {
          return;
        }

        PointerScrollHandler.handlePointerSignal(
          context: context,
          event: event,
          horizontalScrollController: horizontalScrollController,
          verticalScrollController: verticalScrollController,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.defaultHeaderPalette.background,
          border: Border(
            top: style.showLeadingOuterBorders
                ? BorderSide(color: style.cellSeparatorColor, width: style.cellSeparatorStrokeWidth)
                : BorderSide.none,
            left: style.showLeadingOuterBorders
                ? BorderSide(color: style.cellSeparatorColor, width: style.cellSeparatorStrokeWidth)
                : BorderSide.none,
            right: BorderSide(color: style.cellSeparatorColor, width: style.cellSeparatorStrokeWidth),
            bottom: BorderSide(color: style.cellSeparatorColor, width: style.cellSeparatorStrokeWidth),
          ),
        ),
      ),
    );
  }
}
