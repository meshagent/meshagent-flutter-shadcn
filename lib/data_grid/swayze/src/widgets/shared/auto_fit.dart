import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/controller.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/delegates.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/core/controller/table/table_controller.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/core/style/style.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze_math/swayze_math.dart';

const kMinimumResizableColumnExtent = 40.0;
const kMinimumResizableRowExtent = 24.0;
const kHeaderAutoFitHorizontalPadding = 8.0;
const kHeaderAutoFitVerticalPadding = 8.0;

class SwayzeAutoFitMeasurementRequest {
  const SwayzeAutoFitMeasurementRequest({required this.builder, this.width});

  final WidgetBuilder builder;
  final double? width;
}

class _SwayzeAutoFitMeasurementHost extends StatelessWidget {
  const _SwayzeAutoFitMeasurementHost({required this.requests, required this.keys});

  final List<SwayzeAutoFitMeasurementRequest> requests;
  final List<GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < requests.length; index++)
                SizedBox(
                  key: keys[index],
                  width: requests[index].width,
                  child: Builder(builder: requests[index].builder),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

double minimumResizableExtentForAxis(Axis axis) {
  return axis == Axis.horizontal ? kMinimumResizableColumnExtent : kMinimumResizableRowExtent;
}

double? maxAutoFitExtentForAxis(SwayzeStyle style, Axis axis) {
  return axis == Axis.horizontal ? style.maxAutoFitColumnExtent : style.maxAutoFitRowExtent;
}

SwayzeAutoFitMeasurementRequest createHeaderAutoFitMeasurementRequest({required String label, required SwayzeStyle style}) {
  return SwayzeAutoFitMeasurementRequest(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHeaderAutoFitHorizontalPadding, vertical: kHeaderAutoFitVerticalPadding),
      child: Text(label, maxLines: 1, softWrap: false, style: style.headerTextStyle),
    ),
  );
}

Future<List<Size>> measureAutoFitLayouts(BuildContext context, List<SwayzeAutoFitMeasurementRequest> requests) async {
  if (requests.isEmpty) {
    return const [];
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return List<Size>.filled(requests.length, Size.zero);
  }

  final keys = List.generate(requests.length, (_) => GlobalKey());
  final textDirection = Directionality.of(context);
  final mediaQuery = MediaQuery.maybeOf(context);

  late final OverlayEntry overlayEntry;
  overlayEntry = OverlayEntry(
    builder: (_) {
      Widget child = _SwayzeAutoFitMeasurementHost(requests: requests, keys: keys);
      child = Directionality(textDirection: textDirection, child: child);

      if (mediaQuery != null) {
        child = MediaQuery(data: mediaQuery, child: child);
      }

      return IgnorePointer(child: InheritedTheme.captureAll(context, child));
    },
  );

  overlay.insert(overlayEntry);
  await WidgetsBinding.instance.endOfFrame;

  final sizes = [for (final key in keys) ((key.currentContext?.findRenderObject()) as RenderBox?)?.size ?? Size.zero];

  overlayEntry.remove();

  return sizes;
}

Future<double?> computeHeaderAutoFitExtent<CellDataType extends SwayzeCellData>({
  required BuildContext context,
  required Axis axis,
  required int headerPosition,
  required SwayzeTableDataController tableDataController,
  required CellDelegate<CellDataType> cellDelegate,
  required MatrixMapReadOnly<CellDataType> cellMatrix,
  required SwayzeStyle style,
  required String headerLabel,
}) async {
  final requests = <SwayzeAutoFitMeasurementRequest>[createHeaderAutoFitMeasurementRequest(label: headerLabel, style: style)];

  if (axis == Axis.horizontal) {
    cellMatrix.forEach((item, colIndex, rowIndex) {
      if (colIndex != headerPosition) {
        return;
      }

      final cellData = item as CellDataType;
      if (!cellData.hasVisibleContent) {
        return;
      }

      final cellLayout = cellDelegate.getCellLayout(cellData);
      requests.add(SwayzeAutoFitMeasurementRequest(builder: (context) => cellLayout.buildCell(context)));
    });
  } else {
    cellMatrix.forEachInRow(headerPosition, (item, colIndex, rowIndex) {
      final cellData = item as CellDataType;
      if (!cellData.hasVisibleContent) {
        return;
      }

      final columnExtent = tableDataController.columns.value.getHeaderExtentFor(index: colIndex);
      final constrainedWidth = (columnExtent - style.cellSeparatorStrokeWidth).clamp(0.0, double.infinity) as double;
      final cellLayout = cellDelegate.getCellLayout(cellData);

      requests.add(SwayzeAutoFitMeasurementRequest(builder: (context) => cellLayout.buildCell(context), width: constrainedWidth));
    });
  }

  final sizes = await measureAutoFitLayouts(context, requests);
  if (!context.mounted) {
    return null;
  }

  final contentExtent = sizes.fold<double>(0.0, (currentMax, size) {
    final nextExtent = axis == Axis.horizontal ? size.width : size.height;
    return nextExtent > currentMax ? nextExtent : currentMax;
  });
  final maxExtent = maxAutoFitExtentForAxis(style, axis);
  final minimumExtent = axis == Axis.vertical ? tableDataController.rows.value.defaultHeaderExtent : minimumResizableExtentForAxis(axis);
  final fittedExtent = math.max(contentExtent + style.cellSeparatorStrokeWidth, minimumExtent);
  return (maxExtent == null ? fittedExtent : math.min(fittedExtent, maxExtent)).clamp(minimumResizableExtentForAxis(axis), double.infinity)
      as double;
}

Future<Map<int, double>> computeHeaderAutoFitExtents<CellDataType extends SwayzeCellData>({
  required BuildContext context,
  required Axis axis,
  required Iterable<int> headerPositions,
  required SwayzeTableDataController tableDataController,
  required CellDelegate<CellDataType> cellDelegate,
  required MatrixMapReadOnly<CellDataType> cellMatrix,
  required SwayzeStyle style,
  required String Function(int headerPosition) headerLabelFor,
}) async {
  final result = <int, double>{};
  for (final headerPosition in headerPositions) {
    if (!context.mounted) {
      break;
    }

    final extent = await computeHeaderAutoFitExtent<CellDataType>(
      context: context,
      axis: axis,
      headerPosition: headerPosition,
      tableDataController: tableDataController,
      cellDelegate: cellDelegate,
      cellMatrix: cellMatrix,
      style: style,
      headerLabel: headerLabelFor(headerPosition),
    );
    if (extent != null) {
      result[headerPosition] = extent;
    }
  }

  return result;
}
