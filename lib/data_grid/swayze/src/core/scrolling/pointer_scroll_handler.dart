import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PointerScrollHandler {
  const PointerScrollHandler._();

  static void handlePointerSignal({
    required BuildContext context,
    required PointerSignalEvent event,
    required ScrollController horizontalScrollController,
    required ScrollController verticalScrollController,
  }) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final primaryAxis = _primaryScrollAxis(event);
    if (primaryAxis == null) {
      event.respond(allowPlatformDefault: true);
      return;
    }

    final primaryPosition = _scrollPositionForAxis(
      primaryAxis,
      horizontalScrollController: horizontalScrollController,
      verticalScrollController: verticalScrollController,
    );
    final primaryDelta = _resolvedPointerSignalDelta(event, primaryPosition, primaryAxis);
    if (primaryDelta != null) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (pointerEvent) => _applyPointerScroll(pointerEvent, position: primaryPosition, delta: primaryDelta),
      );
      return;
    }

    final ancestorScrollable = _ancestorScrollableForAxis(context, primaryAxis, currentPosition: primaryPosition);
    final ancestorPosition = ancestorScrollable?.position;
    final ancestorDelta = ancestorPosition == null ? null : _resolvedPointerSignalDelta(event, ancestorPosition, primaryAxis);
    if (ancestorDelta != null && ancestorPosition != null) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (pointerEvent) => _applyPointerScroll(pointerEvent, position: ancestorPosition, delta: ancestorDelta),
      );
      return;
    }

    final secondaryAxis = flipAxis(primaryAxis);
    final secondaryPosition = _scrollPositionForAxis(
      secondaryAxis,
      horizontalScrollController: horizontalScrollController,
      verticalScrollController: verticalScrollController,
    );
    final secondaryDelta = _resolvedPointerSignalDelta(event, secondaryPosition, secondaryAxis);
    if (secondaryDelta != null) {
      GestureBinding.instance.pointerSignalResolver.register(event, (pointerEvent) => pointerEvent.respond(allowPlatformDefault: true));
    }
  }

  static double? _resolvedPointerSignalDelta(PointerScrollEvent event, ScrollPosition position, Axis axis) {
    if (!position.physics.shouldAcceptUserOffset(position)) {
      return null;
    }

    final delta = _pointerSignalEventDelta(event, axis);
    if (delta == 0.0) {
      return null;
    }

    final targetScrollOffset = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);

    if (targetScrollOffset == position.pixels) {
      return null;
    }

    return delta;
  }

  static double _pointerSignalEventDelta(PointerScrollEvent event, Axis axis) {
    final keysPressed = LogicalKeyboardKey.collapseSynonyms(HardwareKeyboard.instance.logicalKeysPressed);

    final containsShift =
        keysPressed.contains(LogicalKeyboardKey.shift) ||
        keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        keysPressed.contains(LogicalKeyboardKey.shiftRight);

    if (defaultTargetPlatform == TargetPlatform.windows && containsShift) {
      if (axis == Axis.vertical) {
        return 0.0;
      }
      return event.scrollDelta.dy;
    }

    if (axis == Axis.horizontal) {
      return event.scrollDelta.dx;
    }

    return event.scrollDelta.dy;
  }

  static Axis? _primaryScrollAxis(PointerScrollEvent event) {
    final horizontalMagnitude = _pointerSignalEventDelta(event, Axis.horizontal).abs();
    final verticalMagnitude = _pointerSignalEventDelta(event, Axis.vertical).abs();

    if (horizontalMagnitude == 0.0 && verticalMagnitude == 0.0) {
      return null;
    }

    return horizontalMagnitude > verticalMagnitude ? Axis.horizontal : Axis.vertical;
  }

  static ScrollPosition _scrollPositionForAxis(
    Axis axis, {
    required ScrollController horizontalScrollController,
    required ScrollController verticalScrollController,
  }) {
    return axis == Axis.horizontal ? horizontalScrollController.position : verticalScrollController.position;
  }

  static ScrollableState? _ancestorScrollableForAxis(BuildContext context, Axis axis, {required ScrollPosition currentPosition}) {
    ScrollableState? ancestorScrollable;
    context.visitAncestorElements((element) {
      if (element is! StatefulElement) {
        return true;
      }

      final state = element.state;
      if (state is! ScrollableState) {
        return true;
      }

      final scrollable = state;
      if (axisDirectionToAxis(scrollable.axisDirection) != axis || identical(scrollable.position, currentPosition)) {
        return true;
      }

      ancestorScrollable = scrollable;
      return false;
    });
    return ancestorScrollable;
  }

  static void _applyPointerScroll(PointerEvent event, {required ScrollPosition position, required double delta}) {
    assert(event is PointerScrollEvent);

    position.pointerScroll(delta);
  }
}
