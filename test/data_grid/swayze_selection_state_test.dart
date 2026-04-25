import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/core/controller/selection/user_selections/model.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze/src/core/controller/selection/user_selections/user_selection_state.dart';
import 'package:meshagent_flutter_shadcn/data_grid/swayze_math/swayze_math.dart';

void main() {
  test('initial state starts hidden until the user selects something', () {
    final state = UserSelectionState.initial;

    expect(state.hasVisibleSelection, isFalse);
    expect(state.visibleSelections, isEmpty);
    expect(state.activeCellCoordinate, const IntVector2(0, 0));
  });

  test('cell selection updates replace the active selection', () {
    final state = UserSelectionState.initial.resetSelectionsToACellSelection(anchor: const IntVector2(2, 3), focus: const IntVector2(2, 3));

    final updated = state.updateLastSelectionToCellSelection(focus: const IntVector2(5, 7));

    expect(updated.selections, hasLength(1));
    expect(updated.hasVisibleSelection, isTrue);

    final selection = updated.primarySelection as CellUserSelectionModel;
    expect(selection.anchor, const IntVector2(2, 3));
    expect(selection.focus, const IntVector2(5, 7));
  });

  test('header selection updates replace the active selection', () {
    final state = UserSelectionState.initial.resetSelectionsToHeaderSelection(axis: Axis.horizontal, anchor: 1, focus: 1);

    final updated = state.updateLastSelectionToHeaderSelection(axis: Axis.horizontal, focus: 4);

    expect(updated.selections, hasLength(1));
    expect(updated.hasVisibleSelection, isTrue);

    final selection = updated.primarySelection as HeaderUserSelectionModel;
    expect(selection.anchor, 1);
    expect(selection.focus, 4);
  });
}
