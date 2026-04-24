import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'pointer_scroll_handler.dart';
import 'sliver_two_axis_scroll.dart';

/// A [StatelessWidget] that wraps a [Listener] and intercepts
/// mousewheel/trackpad events and apply the scrolling deltas to both scroll
/// controllers keeping a non stuttering two axis scroll.
///
/// See also:
/// [SliverTwoAxisScroll] that contains this widget.
class PointerScrollDetector extends StatelessWidget {
  final ScrollController horizontalScrollController;
  final ScrollController verticalScrollController;

  final Widget child;

  const PointerScrollDetector({
    Key? key,
    required this.horizontalScrollController,
    required this.verticalScrollController,
    required this.child,
  }) : super(key: key);

  /// Handle the [PointerScrollEvent] event from a [Listener].
  void handlePointerSignal(BuildContext context, PointerSignalEvent event) {
    PointerScrollHandler.handlePointerSignal(
      context: context,
      event: event,
      horizontalScrollController: horizontalScrollController,
      verticalScrollController: verticalScrollController,
    );
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerSignal: (event) => handlePointerSignal(context, event), behavior: HitTestBehavior.opaque, child: child);
}
