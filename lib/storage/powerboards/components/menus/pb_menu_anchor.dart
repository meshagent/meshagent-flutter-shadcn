import 'package:flutter/material.dart';

enum PbMenuAnchorPlacement { bottomLeft, bottomRight, rightTop }

class PbMenuAnchor extends StatefulWidget {
  const PbMenuAnchor({
    super.key,
    required this.child,
    this.panel,
    this.placement = PbMenuAnchorPlacement.bottomLeft,
    this.gap = 10,
    this.triggerWidth,
    this.triggerHeight = 48,
    this.preferAboveWhenOverflow = false,
    this.onDismiss,
    this.onDismissRequested,
  });

  final Widget child;
  final Widget? panel;
  final PbMenuAnchorPlacement placement;
  final double gap;
  final double? triggerWidth;
  final double triggerHeight;
  final bool preferAboveWhenOverflow;
  final VoidCallback? onDismiss;
  final VoidCallback? onDismissRequested;

  @override
  State<PbMenuAnchor> createState() => _PbMenuAnchorState();
}

class _PbMenuAnchorState extends State<PbMenuAnchor> {
  static const double _viewportPadding = 16;
  static const double _mobileBreakpoint = 680;
  final OverlayPortalController _controller = OverlayPortalController();
  final Object _tapRegionGroupId = Object();

  @override
  void initState() {
    super.initState();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(covariant PbMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisibility();
  }

  void _syncVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (widget.panel != null) {
        if (!_controller.isShowing) {
          _controller.show();
        }
      } else if (_controller.isShowing) {
        _controller.hide();
      }
    });
  }

  void _handleTapOutside(PointerDownEvent event) {
    if (widget.panel == null) {
      return;
    }

    (widget.onDismiss ?? widget.onDismissRequested)?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapRegionGroupId,
      onTapOutside: widget.onDismiss == null && widget.onDismissRequested == null ? null : _handleTapOutside,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _controller,
        overlayChildBuilder: (context, info) {
          final panel = widget.panel;

          if (panel == null) {
            return const SizedBox.shrink();
          }

          final childRect = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
          final maxPanelWidth = info.overlaySize.width - (_viewportPadding * 2);
          final maxPanelHeight = info.overlaySize.height - (_viewportPadding * 2);
          final mobileRailStretch = info.overlaySize.width <= _mobileBreakpoint && widget.placement == PbMenuAnchorPlacement.bottomRight;

          return TapRegion(
            groupId: _tapRegionGroupId,
            child: CustomSingleChildLayout(
              delegate: _PbMenuAnchorLayoutDelegate(
                childRect: childRect,
                overlaySize: info.overlaySize,
                placement: widget.placement,
                gap: widget.gap,
                viewportPadding: _viewportPadding,
                mobileRailStretch: mobileRailStretch,
                preferAboveWhenOverflow: widget.preferAboveWhenOverflow,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxPanelWidth, maxHeight: maxPanelHeight),
                child: SingleChildScrollView(
                  primary: false,
                  child: mobileRailStretch ? SizedBox(width: maxPanelWidth, child: panel) : panel,
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _PbMenuAnchorLayoutDelegate extends SingleChildLayoutDelegate {
  const _PbMenuAnchorLayoutDelegate({
    required this.childRect,
    required this.overlaySize,
    required this.placement,
    required this.gap,
    required this.viewportPadding,
    required this.mobileRailStretch,
    required this.preferAboveWhenOverflow,
  });

  final Rect childRect;
  final Size overlaySize;
  final PbMenuAnchorPlacement placement;
  final double gap;
  final double viewportPadding;
  final bool mobileRailStretch;
  final bool preferAboveWhenOverflow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(Size(overlaySize.width - (viewportPadding * 2), overlaySize.height - (viewportPadding * 2)));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double left;
    double top;

    switch (placement) {
      case PbMenuAnchorPlacement.bottomLeft:
        left = childRect.left;
        top = childRect.bottom + gap;
      case PbMenuAnchorPlacement.bottomRight:
        left = mobileRailStretch ? viewportPadding : childRect.right - childSize.width;
        top = childRect.bottom + gap;
      case PbMenuAnchorPlacement.rightTop:
        left = childRect.right + gap;
        top = childRect.top;
    }

    if (preferAboveWhenOverflow && placement != PbMenuAnchorPlacement.rightTop) {
      final panelBottom = top + childSize.height;
      final maxBottom = size.height - viewportPadding;
      final aboveTop = childRect.top - gap - childSize.height;
      final canFitAbove = aboveTop >= viewportPadding;
      if (panelBottom > maxBottom && canFitAbove) {
        top = aboveTop;
      }
    }

    final maxLeft = size.width - viewportPadding - childSize.width;
    final maxTop = size.height - viewportPadding - childSize.height;

    return Offset(
      left.clamp(viewportPadding, maxLeft < viewportPadding ? viewportPadding : maxLeft),
      top.clamp(viewportPadding, maxTop < viewportPadding ? viewportPadding : maxTop),
    );
  }

  @override
  bool shouldRelayout(covariant _PbMenuAnchorLayoutDelegate oldDelegate) {
    return childRect != oldDelegate.childRect ||
        overlaySize != oldDelegate.overlaySize ||
        placement != oldDelegate.placement ||
        gap != oldDelegate.gap ||
        viewportPadding != oldDelegate.viewportPadding ||
        mobileRailStretch != oldDelegate.mobileRailStretch ||
        preferAboveWhenOverflow != oldDelegate.preferAboveWhenOverflow;
  }
}
