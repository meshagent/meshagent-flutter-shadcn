import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze_math/swayze_math.dart';

import '../../../../controller.dart';
import '../../../../intents.dart';
import '../../../core/style/style.dart';
import '../../../core/viewport_context/viewport_context.dart';
import '../../../core/viewport_context/viewport_context_provider.dart';
import '../../../helpers/label_generator.dart';
import '../../../helpers/scroll/auto_scroll.dart';
import '../../internal_scope.dart';
import '../header_label_scope.dart';
import '../../shared/auto_fit.dart';

const _kHeaderResizeHandleExtent = 6.0;
const _kHeaderAutoFitTapSlop = 24.0;
const _kHeaderAutoFitTapTimeout = Duration(milliseconds: 500);

/// A transport class for auxiliary data about a header gesture and it's
/// position.
@immutable
class _HeaderGestureDetails {
  final Offset localPosition;
  final int headerPosition;

  const _HeaderGestureDetails({required this.localPosition, required this.headerPosition});
}

@immutable
class _HeaderResizeGestureDetails {
  final int headerPosition;
  final double initialExtent;
  final double originAxisPosition;

  const _HeaderResizeGestureDetails({required this.headerPosition, required this.initialExtent, required this.originAxisPosition});
}

@immutable
class _HeaderResizeTapDetails {
  final int headerPosition;
  final Offset globalPosition;
  final DateTime timestamp;

  const _HeaderResizeTapDetails({required this.headerPosition, required this.globalPosition, required this.timestamp});
}

double _getAxisOffset(Offset offset, Axis axis) {
  return axis == Axis.horizontal ? offset.dx : offset.dy;
}

MouseCursor _getResizeCursor(Axis axis) {
  return axis == Axis.horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;
}

/// Return the [Range] edge to expand according to the given [ScrollDirection].
int _getRangeEdgeOnAutoScroll(Range range, ScrollDirection scrolDirection) {
  if (scrolDirection == ScrollDirection.forward) {
    return range.start;
  }

  return range.end - 1;
}

/// Given a globalPosition [Offset] and the [Axis] it creates a
/// [_HeaderGestureDetails] with the converted localPosition [Offset] and the
/// corresponding header position.
///
/// It considers the offscreen details to ensure that we can properly expand
/// the table with the "elastic" table feature.
_HeaderGestureDetails _getHeaderGestureDetails({required BuildContext context, required Axis axis, required Offset globalPosition}) {
  final box = context.findRenderObject()! as RenderBox;
  final localPosition = box.globalToLocal(globalPosition);

  final viewportContext = ViewportContextProvider.of(context);
  final tableDataController = InternalScope.of(context).controller.tableDataController;
  final offset = axis == Axis.horizontal ? localPosition.dx : localPosition.dy;
  final headerPositionResult = viewportContext.pixelToPosition(offset, axis);

  var result = headerPositionResult.position;
  if (headerPositionResult.overflow == OffscreenDetails.trailing) {
    final diff = offset - viewportContext.getAxisContextFor(axis: axis).value.extent;
    final defaultExtent = tableDataController.getHeaderControllerFor(axis: axis).value.defaultHeaderExtent;

    if (tableDataController.allowElasticExpansion) {
      final additionalAmount = (diff / defaultExtent).ceil();
      result += additionalAmount;
    }
  }

  if (!tableDataController.allowElasticExpansion) {
    result = tableDataController.clampHeaderIndexToTable(axis: axis, index: result);
  }

  return _HeaderGestureDetails(localPosition: localPosition, headerPosition: result);
}

_HeaderResizeGestureDetails? _getHeaderResizeGestureDetails({
  required BuildContext context,
  required Axis axis,
  required double displacement,
  required Offset globalPosition,
}) {
  final tableDataController = InternalScope.of(context).controller.tableDataController;
  if (!tableDataController.allowHeaderResize) {
    return null;
  }

  final box = context.findRenderObject()! as RenderBox;
  final localPosition = box.globalToLocal(globalPosition);
  final localAxisPosition = _getAxisOffset(localPosition, axis);
  final viewportContext = ViewportContextProvider.of(context);
  final axisContextState = viewportContext.getAxisContextFor(axis: axis).value;
  final headerController = tableDataController.getHeaderControllerFor(axis: axis);

  _HeaderResizeGestureDetails? bestHit;
  double? bestDistance;

  void inspectHeaders(Iterable<int> indices, {required bool isFrozen}) {
    for (final index in indices) {
      if (index < 0 || index >= headerController.value.count) {
        continue;
      }

      final leading = isFrozen
          ? axisContextState.frozenOffsets[index] + displacement.abs()
          : axisContextState.offsets[index - axisContextState.scrollableRange.start];
      final extent = headerController.value.getHeaderExtentFor(index: index);
      final trailing = leading + extent;
      final distance = (localAxisPosition - trailing).abs();

      if (distance > _kHeaderResizeHandleExtent) {
        continue;
      }

      if (bestDistance == null || distance < bestDistance!) {
        bestDistance = distance;
        bestHit = _HeaderResizeGestureDetails(headerPosition: index, initialExtent: extent, originAxisPosition: localAxisPosition);
      }
    }
  }

  inspectHeaders(axisContextState.visibleFrozenIndices, isFrozen: true);
  inspectHeaders(axisContextState.visibleIndices, isFrozen: false);

  return bestHit;
}

class HeaderGestureDetector extends StatefulWidget {
  final Axis axis;
  final double displacement;

  const HeaderGestureDetector({Key? key, required this.axis, required this.displacement}) : super(key: key);

  @override
  _HeaderGestureDetectorState createState() => _HeaderGestureDetectorState();
}

class _HeaderGestureDetectorState extends State<HeaderGestureDetector> {
  late final internalScope = InternalScope.of(context);
  late final viewportContext = ViewportContextProvider.of(context);

  /// Cache to make the position of the start of a drag gesture acessible in
  /// the drag updates.
  Offset? dragOriginOffsetCache;
  _HeaderResizeGestureDetails? pressedResizeGestureCache;
  _HeaderResizeGestureDetails? activeResizeGesture;
  _HeaderResizeTapDetails? lastAutoFitTap;
  MouseCursor cursor = MouseCursor.defer;
  bool isAutoFittingHeader = false;

  bool _handleHeaderAutoFitTap({required int headerPosition, required Offset globalPosition}) {
    final now = DateTime.now();
    final lastAutoFitTap = this.lastAutoFitTap;
    final isDoubleTap =
        lastAutoFitTap != null &&
        lastAutoFitTap.headerPosition == headerPosition &&
        now.difference(lastAutoFitTap.timestamp) <= _kHeaderAutoFitTapTimeout &&
        (globalPosition - lastAutoFitTap.globalPosition).distance <= _kHeaderAutoFitTapSlop;

    if (isDoubleTap) {
      this.lastAutoFitTap = null;
      unawaited(_autoFitHeader(headerPosition));
      return true;
    }

    this.lastAutoFitTap = _HeaderResizeTapDetails(headerPosition: headerPosition, globalPosition: globalPosition, timestamp: now);
    return false;
  }

  void _setCursor(MouseCursor nextCursor) {
    if (cursor == nextCursor) {
      return;
    }

    setState(() {
      cursor = nextCursor;
    });
  }

  void _updateCursorForPosition(Offset globalPosition) {
    final nextCursor =
        _getHeaderResizeGestureDetails(
              axis: widget.axis,
              context: context,
              displacement: widget.displacement,
              globalPosition: globalPosition,
            ) !=
            null
        ? _getResizeCursor(widget.axis)
        : MouseCursor.defer;
    _setCursor(nextCursor);
  }

  void _stopDragSelection({Offset? globalPosition}) {
    dragOriginOffsetCache = null;
    pressedResizeGestureCache = null;
    activeResizeGesture = null;
    internalScope.controller.scroll.stopAutoScroll(widget.axis);
    if (globalPosition == null) {
      _setCursor(MouseCursor.defer);
      return;
    }
    _updateCursorForPosition(globalPosition);
  }

  void _updateHeaderResize(Offset globalPosition) {
    final activeResizeGesture = this.activeResizeGesture;
    if (activeResizeGesture == null) {
      return;
    }

    final box = context.findRenderObject()! as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);
    final localAxisPosition = _getAxisOffset(localPosition, widget.axis);
    final minExtent = minimumResizableExtentForAxis(widget.axis);
    final resizedExtent =
        (activeResizeGesture.initialExtent + localAxisPosition - activeResizeGesture.originAxisPosition).clamp(minExtent, double.infinity)
            as double;
    final headerController = internalScope.controller.tableDataController.getHeaderControllerFor(axis: widget.axis);
    final currentExtent = headerController.value.getHeaderExtentFor(index: activeResizeGesture.headerPosition);
    if ((currentExtent - resizedExtent).abs() < 0.001) {
      return;
    }

    headerController.updateState((state) => state.setHeaderExtent(activeResizeGesture.headerPosition, resizedExtent));
  }

  Future<void> _autoFitHeader(int headerPosition) async {
    if (isAutoFittingHeader) {
      return;
    }

    isAutoFittingHeader = true;
    try {
      final fittedExtent = await _computeAutoFitExtent(headerPosition);
      if (!mounted || fittedExtent == null) {
        return;
      }

      final headerController = internalScope.controller.tableDataController.getHeaderControllerFor(axis: widget.axis);
      final currentExtent = headerController.value.getHeaderExtentFor(index: headerPosition);
      if ((currentExtent - fittedExtent).abs() < 0.001) {
        return;
      }

      headerController.updateState((state) => state.setHeaderExtent(headerPosition, fittedExtent));
    } finally {
      isAutoFittingHeader = false;
    }
  }

  Future<double?> _computeAutoFitExtent(int headerPosition) async {
    final style = internalScope.style;
    final label =
        SwayzeHeaderLabelScope.maybeOf(context)?.labelFor(axis: widget.axis, index: headerPosition) ??
        generateLabelForIndex(widget.axis, headerPosition);
    return computeHeaderAutoFitExtent<SwayzeCellData>(
      context: context,
      axis: widget.axis,
      headerPosition: headerPosition,
      tableDataController: internalScope.controller.tableDataController,
      cellDelegate: internalScope.cellDelegate,
      cellMatrix: internalScope.controller.cellsController.cellMatrixReadOnly,
      style: style,
      headerLabel: label,
    );
  }

  @override
  void initState() {
    super.initState();

    viewportContext.getAxisContextFor(axis: widget.axis).addListener(onRangesChanged);
  }

  @override
  void dispose() {
    viewportContext.getAxisContextFor(axis: widget.axis).removeListener(onRangesChanged);

    super.dispose();
  }

  /// Listen for [ViewportContext] range changes to update selections in case
  /// a [AutoScrollActivity] is in progress.
  void onRangesChanged() {
    final scrollController = internalScope.controller.scroll;
    final selectionController = internalScope.controller.selection;

    final primarySelection = selectionController.userSelectionState.primarySelection;
    if (primarySelection is! HeaderUserSelectionModel || !scrollController.isAutoScrollOn) {
      return;
    }

    final headerNotifier = viewportContext.getAxisContextFor(axis: widget.axis);

    final scrollPosition = scrollController.getScrollControllerFor(axis: widget.axis)!.position;

    selectionController.updateUserSelections(
      (state) => state.updateLastSelectionToHeaderSelection(
        axis: widget.axis,
        focus: scrollPosition.userScrollDirection != ScrollDirection.idle
            ? _getRangeEdgeOnAutoScroll(headerNotifier.value.scrollableRange, scrollPosition.userScrollDirection)
            : primarySelection.focus,
      ),
    );
  }

  /// Given the current [localOffset] and [globalOffset] check if a
  /// [AutoScrollActivity] should be triggered and which direction.
  ///
  /// When moving to the trailing edge of each axis (up or left) the scroll
  /// activity kicks in when the mouse is before the displacement, ie. in
  /// practical terms, the scroll starts when we hover one of the headers.
  ///
  /// When moving to the leading edge (right or down) theres a
  /// scrollThreshold where the scroll kicks in before we reach the edge of
  /// the table.
  ///
  /// When moving down it checks if the [globalOffset] is within the
  /// scrollThreshold gap at the screen's height edge.
  ///
  /// When moving right, since there might other elements to the right, it
  /// cannot follow the same approach as when moving down. It checks if the
  /// [localOffset] is within the [kRowHeaderWidth] + scrollThreshold gap
  /// at the [ViewportContext] extend.
  ///
  /// See also:
  /// - TableBodyGestureDetector's updateAutoScroll, which is similar to this
  /// method but its related to cells and can create scroll activities in
  /// both axis at the same time.
  void updateDragScroll({required Offset localOffset, required Offset globalOffset, required Offset originOffset}) {
    final screenSize = MediaQuery.of(context).size;
    final scrollController = internalScope.controller.scroll;
    final DragScrollData scrollData;

    if (widget.axis == Axis.horizontal) {
      scrollData = getHorizontalDragScrollData(
        displacement: widget.displacement,
        globalOffset: globalOffset.dx,
        localOffset: localOffset.dx,
        gestureOriginOffset: originOffset.dx,
        screenWidth: screenSize.width,
        viewportExtent: viewportContext.columns.value.extent,
        frozenExtent: viewportContext.columns.value.frozenExtent,
      );
    } else {
      scrollData = getVerticalDragScrollData(
        displacement: widget.displacement,
        globalOffset: globalOffset.dy,
        localOffset: localOffset.dy,
        gestureOriginOffset: originOffset.dy,
        positionPixel: scrollController.verticalScrollController!.position.pixels,
        screenHeight: screenSize.height,
        scrollingData: viewportContext.rows.virtualizationState.scrollingData,
        viewportExtent: viewportContext.rows.value.extent,
        frozenExtent: viewportContext.rows.value.frozenExtent,
      );
    }

    if (scrollData is AutoScrollDragScrollData) {
      // auto scroll
      scrollController.startOrUpdateAutoScroll(
        direction: scrollData.direction,
        maxToScroll: scrollData.maxToScroll,
        pointerDistance: scrollData.pointerDistance,
      );
    } else if (scrollData is ResetScrollDragScrollData) {
      // reset scroll

      scrollController.jumpToHeader(viewportContext.getAxisContextFor(axis: widget.axis).value.frozenRange.end, widget.axis);
    } else {
      // do not scroll
      scrollController.stopAutoScroll(widget.axis);
    }
  }

  /// Handles taps/drag starts that should start a selection.
  /// Given a [_HeaderGestureDetails] it creates or updates a selection
  /// based on the modifiers that the user is pressing.
  void handleStartSelection(_HeaderGestureDetails details) {
    Actions.invoke(context, HeaderSelectionStartIntent(header: details.headerPosition, axis: widget.axis));
  }

  /// Handles updates to a ongoing drag operation. It updates the last selection
  /// to a header selection.
  void handleUpdateSelection(_HeaderGestureDetails details) {
    Actions.invoke(context, HeaderSelectionUpdateIntent(header: details.headerPosition, axis: widget.axis));
  }

  void _configureDragRecognizer(DragGestureRecognizer instance) {
    instance.onStart = (DragStartDetails details) {
      final resizeGestureDetails = pressedResizeGestureCache;
      if (resizeGestureDetails != null) {
        lastAutoFitTap = null;
        activeResizeGesture = resizeGestureDetails;
        _setCursor(_getResizeCursor(widget.axis));
        return;
      }

      final headerGestureDetails = _getHeaderGestureDetails(axis: widget.axis, context: context, globalPosition: details.globalPosition);

      handleStartSelection(headerGestureDetails);

      dragOriginOffsetCache = headerGestureDetails.localPosition;
    };
    instance.onUpdate = (DragUpdateDetails details) {
      if (activeResizeGesture != null) {
        _updateHeaderResize(details.globalPosition);
        return;
      }

      final headerGestureDetails = _getHeaderGestureDetails(axis: widget.axis, context: context, globalPosition: details.globalPosition);

      updateDragScroll(
        localOffset: headerGestureDetails.localPosition,
        globalOffset: details.globalPosition,
        originOffset: dragOriginOffsetCache!,
      );

      handleUpdateSelection(headerGestureDetails);
    };
    instance.onEnd = (DragEndDetails details) {
      _stopDragSelection();
    };
    instance.onCancel = () {
      _stopDragSelection();
    };
  }

  @override
  Widget build(BuildContext context) {
    final dragGestureType = widget.axis == Axis.horizontal ? HorizontalDragGestureRecognizer : VerticalDragGestureRecognizer;
    final GestureRecognizerFactory dragGestureFactory = widget.axis == Axis.horizontal
        ? GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(debugOwner: this),
            _configureDragRecognizer,
          )
        : GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(debugOwner: this),
            _configureDragRecognizer,
          );

    return MouseRegion(
      cursor: cursor,
      onHover: (event) {
        _updateCursorForPosition(event.position);
      },
      onExit: (_) {
        _setCursor(MouseCursor.defer);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          pressedResizeGestureCache = _getHeaderResizeGestureDetails(
            axis: widget.axis,
            context: context,
            displacement: widget.displacement,
            globalPosition: event.position,
          );
          if (pressedResizeGestureCache != null) {
            _setCursor(_getResizeCursor(widget.axis));
          }
        },
        onPointerUp: (event) {
          _stopDragSelection(globalPosition: event.position);
        },
        onPointerCancel: (_) {
          _stopDragSelection();
        },
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            dragGestureType: dragGestureFactory,
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(() => TapGestureRecognizer(debugOwner: this), (
              TapGestureRecognizer instance,
            ) {
              instance.onTapDown = (TapDownDetails details) {
                final resizeGestureDetails = _getHeaderResizeGestureDetails(
                  axis: widget.axis,
                  context: context,
                  displacement: widget.displacement,
                  globalPosition: details.globalPosition,
                );
                if (resizeGestureDetails != null) {
                  _handleHeaderAutoFitTap(headerPosition: resizeGestureDetails.headerPosition, globalPosition: details.globalPosition);
                  return;
                }

                final headerGestureDetails = _getHeaderGestureDetails(
                  axis: widget.axis,
                  context: context,
                  globalPosition: details.globalPosition,
                );

                if (_handleHeaderAutoFitTap(headerPosition: headerGestureDetails.headerPosition, globalPosition: details.globalPosition)) {
                  return;
                }

                handleStartSelection(headerGestureDetails);
              };
            }),
          },
          behavior: HitTestBehavior.translucent,
        ),
      ),
    );
  }
}
