import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../helpers/label_generator.dart';

class SwayzeHeaderLabelScope extends InheritedWidget {
  const SwayzeHeaderLabelScope({super.key, required this.columnLabels, required super.child});

  final Map<int, String> columnLabels;

  static SwayzeHeaderLabelScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SwayzeHeaderLabelScope>();
  }

  String labelFor({required Axis axis, required int index}) {
    if (axis == Axis.horizontal) {
      return columnLabels[index] ?? generateLabelForIndex(axis, index);
    }
    return generateLabelForIndex(axis, index);
  }

  @override
  bool updateShouldNotify(SwayzeHeaderLabelScope oldWidget) {
    return !mapEquals(columnLabels, oldWidget.columnLabels);
  }
}
