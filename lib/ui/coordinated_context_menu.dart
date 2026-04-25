import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ShadTopLevelContextMenuCoordinator {
  static final Set<ShadContextMenuController> _controllers = <ShadContextMenuController>{};
  static bool _synchronizing = false;
  static Offset? _suppressedSecondaryTapPosition;
  static DateTime? _suppressedSecondaryTapAt;

  static void register(ShadContextMenuController controller) {
    _controllers.add(controller);
  }

  static void unregister(ShadContextMenuController controller) {
    _controllers.remove(controller);
  }

  static void handleChanged(ShadContextMenuController controller) {
    if (_synchronizing || !controller.isOpen) {
      return;
    }

    _synchronizing = true;
    try {
      for (final other in _controllers.toList(growable: false)) {
        if (!identical(other, controller) && other.isOpen) {
          other.hide();
        }
      }
    } finally {
      _synchronizing = false;
    }
  }

  static void suppressSecondaryTapAt(Offset globalPosition) {
    _suppressedSecondaryTapPosition = globalPosition;
    _suppressedSecondaryTapAt = DateTime.now();
  }

  static bool shouldSuppressSecondaryTapAt(Offset globalPosition) {
    final suppressedPosition = _suppressedSecondaryTapPosition;
    final suppressedAt = _suppressedSecondaryTapAt;
    if (suppressedPosition == null || suppressedAt == null) {
      return false;
    }

    final isCurrentTap = DateTime.now().difference(suppressedAt) < const Duration(milliseconds: 750);
    return isCurrentTap && (suppressedPosition - globalPosition).distance <= 2;
  }
}

class CoordinatedSecondaryTapBarrier extends StatelessWidget {
  const CoordinatedSecondaryTapBarrier({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final isMouse = event.kind == PointerDeviceKind.mouse;
        final isSecondaryMouseButton = event.buttons == kSecondaryMouseButton;
        if (isMouse && isSecondaryMouseButton) {
          ShadTopLevelContextMenuCoordinator.suppressSecondaryTapAt(event.position);
        }
      },
      child: child,
    );
  }
}

enum ShadMenuHorizontalPosition { automatic, left, right }

enum ShadMenuVerticalPosition { automatic, down, up }

RenderBox? _safeRenderBox(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }

  try {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
      return null;
    }

    return renderObject;
  } catch (_) {
    return null;
  }
}

ShadAnchor resolveAdaptiveShadMenuAnchor(
  BuildContext context, {
  BuildContext? boundaryContext,
  double viewportVerticalSplit = 2 / 3,
  double gap = 8,
  double? estimatedMenuWidth,
  double? estimatedMenuHeight,
  double viewportEdgePadding = 12,
  bool centerHorizontallyInBoundary = false,
  ShadMenuHorizontalPosition horizontalPosition = ShadMenuHorizontalPosition.automatic,
  ShadMenuVerticalPosition verticalPosition = ShadMenuVerticalPosition.automatic,
}) {
  const fallbackAnchor = ShadAnchor(childAlignment: Alignment.topLeft, overlayAlignment: Alignment.bottomLeft, offset: Offset(0, 8));
  final renderBox = _safeRenderBox(context);
  if (renderBox == null) {
    return fallbackAnchor;
  }

  final overlayRenderBox = _safeRenderBox(Overlay.maybeOf(context)?.context);
  final boundaryRenderBox = _safeRenderBox(boundaryContext) ?? overlayRenderBox;

  try {
    final viewportSize = boundaryRenderBox?.size ?? MediaQuery.sizeOf(context);
    final triggerOrigin = boundaryRenderBox != null
        ? renderBox.localToGlobal(Offset.zero, ancestor: boundaryRenderBox)
        : renderBox.localToGlobal(Offset.zero);
    final triggerBottom = triggerOrigin.dy + renderBox.size.height;
    final triggerRight = triggerOrigin.dx + renderBox.size.width;
    final triggerCenter = triggerOrigin + Offset(renderBox.size.width / 2, renderBox.size.height / 2);
    final viewportCenterX = viewportSize.width / 2;

    final openDown = switch (verticalPosition) {
      ShadMenuVerticalPosition.down => true,
      ShadMenuVerticalPosition.up => false,
      ShadMenuVerticalPosition.automatic => _shouldOpenMenuDown(
        triggerOriginY: triggerOrigin.dy,
        triggerBottomY: triggerBottom,
        triggerCenterY: triggerCenter.dy,
        viewportHeight: viewportSize.height,
        viewportVerticalSplit: viewportVerticalSplit,
        estimatedMenuHeight: estimatedMenuHeight,
        viewportEdgePadding: viewportEdgePadding,
      ),
    };

    if (centerHorizontallyInBoundary) {
      return ShadAnchor(
        childAlignment: Alignment(0, openDown ? -1 : 1),
        overlayAlignment: Alignment(0, openDown ? 1 : -1),
        offset: Offset(viewportCenterX - triggerCenter.dx, openDown ? gap : -gap),
      );
    }

    final alignLeft = _shouldAlignMenuLeft(
      triggerOriginX: triggerOrigin.dx,
      triggerRightX: triggerRight,
      triggerCenterX: triggerCenter.dx,
      viewportWidth: viewportSize.width,
      viewportEdgePadding: viewportEdgePadding,
      estimatedMenuWidth: estimatedMenuWidth,
      horizontalPosition: horizontalPosition,
    );

    return ShadAnchor(
      childAlignment: Alignment(alignLeft ? -1 : 1, openDown ? -1 : 1),
      overlayAlignment: Alignment(alignLeft ? -1 : 1, openDown ? 1 : -1),
      offset: Offset(0, openDown ? gap : -gap),
    );
  } catch (_) {
    return fallbackAnchor;
  }
}

bool _shouldAlignMenuLeft({
  required double triggerOriginX,
  required double triggerRightX,
  required double triggerCenterX,
  required double viewportWidth,
  required double viewportEdgePadding,
  required ShadMenuHorizontalPosition horizontalPosition,
  double? estimatedMenuWidth,
}) {
  switch (horizontalPosition) {
    case ShadMenuHorizontalPosition.left:
      return true;
    case ShadMenuHorizontalPosition.right:
      return false;
    case ShadMenuHorizontalPosition.automatic:
      if (estimatedMenuWidth != null) {
        final availableRight = viewportWidth - triggerOriginX - viewportEdgePadding;
        final availableLeft = triggerRightX - viewportEdgePadding;
        final fitsLeftAligned = estimatedMenuWidth <= availableRight;
        final fitsRightAligned = estimatedMenuWidth <= availableLeft;

        if (fitsLeftAligned != fitsRightAligned) {
          return fitsLeftAligned;
        }

        if (!fitsLeftAligned && !fitsRightAligned) {
          return availableRight >= availableLeft;
        }
      }

      return triggerCenterX <= viewportWidth / 2;
  }
}

bool _shouldOpenMenuDown({
  required double triggerOriginY,
  required double triggerBottomY,
  required double triggerCenterY,
  required double viewportHeight,
  required double viewportVerticalSplit,
  required double viewportEdgePadding,
  double? estimatedMenuHeight,
}) {
  if (estimatedMenuHeight != null) {
    final availableBelow = viewportHeight - triggerBottomY - viewportEdgePadding;
    final availableAbove = triggerOriginY - viewportEdgePadding;
    final fitsBelow = estimatedMenuHeight <= availableBelow;
    final fitsAbove = estimatedMenuHeight <= availableAbove;

    if (fitsBelow != fitsAbove) {
      return fitsBelow;
    }

    if (!fitsBelow && !fitsAbove) {
      return availableBelow >= availableAbove;
    }
  }

  return triggerCenterY <= viewportHeight * viewportVerticalSplit;
}

Offset _pointForAlignment(Alignment alignment, Size size) {
  return Offset((alignment.x + 1) * size.width / 2, (alignment.y + 1) * size.height / 2);
}

double? _resolveEstimatedMenuWidth(BoxConstraints? constraints, double? estimatedMenuWidth) {
  if (estimatedMenuWidth != null && estimatedMenuWidth > 0) {
    return estimatedMenuWidth;
  }
  if (constraints == null) {
    return null;
  }
  if (constraints.minWidth > 0) {
    return constraints.minWidth;
  }
  if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
    return constraints.maxWidth;
  }
  return null;
}

double? _resolveEstimatedMenuHeight(BoxConstraints? constraints, double? estimatedMenuHeight) {
  if (estimatedMenuHeight != null && estimatedMenuHeight > 0) {
    return estimatedMenuHeight;
  }
  if (constraints == null) {
    return null;
  }
  if (constraints.minHeight > 0) {
    return constraints.minHeight;
  }
  if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
    return constraints.maxHeight;
  }
  return null;
}

Rect? _globalRectForRenderBox(RenderBox? renderBox) {
  if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
    return null;
  }
  return renderBox.localToGlobal(Offset.zero) & renderBox.size;
}

Rect? _computeGlobalMenuRect({
  required BuildContext triggerContext,
  required ShadAnchorBase anchor,
  required BuildContext? boundaryContext,
  required double menuWidth,
  required double menuHeight,
}) {
  if (anchor is! ShadAnchor) {
    return null;
  }

  final triggerRenderBox = _safeRenderBox(triggerContext);
  if (triggerRenderBox == null) {
    return null;
  }

  final boundaryRenderBox = _safeRenderBox(boundaryContext);
  final localTriggerOrigin = boundaryRenderBox != null
      ? triggerRenderBox.localToGlobal(Offset.zero, ancestor: boundaryRenderBox)
      : triggerRenderBox.localToGlobal(Offset.zero);
  final boundaryGlobalOrigin = boundaryRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

  final triggerRect = localTriggerOrigin & triggerRenderBox.size;
  final menuSize = Size(menuWidth, menuHeight);
  final childAlignment = anchor.childAlignment.resolve(TextDirection.ltr);
  final overlayAlignment = anchor.overlayAlignment.resolve(TextDirection.ltr);
  final childPoint = triggerRect.topLeft + _pointForAlignment(childAlignment, triggerRect.size);
  final menuTopLeftLocal = childPoint + anchor.offset - _pointForAlignment(overlayAlignment, menuSize);
  return (boundaryGlobalOrigin + menuTopLeftLocal) & menuSize;
}

class ShadContextMenuBoundary extends StatelessWidget {
  const ShadContextMenuBoundary({super.key, required this.child});

  final Widget child;

  static BuildContext? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShadContextMenuBoundaryScope>()?.boundaryContext;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (boundaryContext) {
        return _ShadContextMenuBoundaryScope(boundaryContext: boundaryContext, child: child);
      },
    );
  }
}

class _ShadContextMenuBoundaryScope extends InheritedWidget {
  const _ShadContextMenuBoundaryScope({required this.boundaryContext, required super.child});

  final BuildContext boundaryContext;

  @override
  bool updateShouldNotify(_ShadContextMenuBoundaryScope oldWidget) {
    return !identical(boundaryContext, oldWidget.boundaryContext);
  }
}

class CoordinatedShadContextMenu extends StatefulWidget {
  const CoordinatedShadContextMenu({
    super.key,
    required this.child,
    required this.items,
    this.anchor,
    this.visible,
    this.constraints,
    this.onHoverArea,
    this.padding,
    this.groupId,
    this.shadows,
    this.decoration,
    this.filter,
    this.controller,
    this.onTapOutside,
    this.onTapInside,
    this.onTapUpInside,
    this.onTapUpOutside,
    this.popoverReverseDuration,
    this.horizontalPosition = ShadMenuHorizontalPosition.automatic,
    this.verticalPosition = ShadMenuVerticalPosition.automatic,
    this.boundaryContext,
    this.estimatedMenuWidth,
    this.estimatedMenuHeight,
    this.anchorGap = 8,
    this.viewportVerticalSplit = 2 / 3,
    this.viewportEdgePadding = 12,
    this.centerHorizontallyInBoundary = false,
  });

  final Widget child;
  final List<Widget> items;
  final ShadAnchorBase? anchor;
  final bool? visible;
  final BoxConstraints? constraints;
  final ValueChanged<bool>? onHoverArea;
  final EdgeInsetsGeometry? padding;
  final Object? groupId;
  final List<BoxShadow>? shadows;
  final ShadDecoration? decoration;
  final ImageFilter? filter;
  final ShadContextMenuController? controller;
  final TapRegionCallback? onTapOutside;
  final TapRegionCallback? onTapInside;
  final TapRegionUpCallback? onTapUpInside;
  final TapRegionUpCallback? onTapUpOutside;
  final Duration? popoverReverseDuration;
  final ShadMenuHorizontalPosition horizontalPosition;
  final ShadMenuVerticalPosition verticalPosition;
  final BuildContext? boundaryContext;
  final double? estimatedMenuWidth;
  final double? estimatedMenuHeight;
  final double anchorGap;
  final double viewportVerticalSplit;
  final double viewportEdgePadding;
  final bool centerHorizontallyInBoundary;

  @override
  State<CoordinatedShadContextMenu> createState() => _CoordinatedShadContextMenuState();
}

class _CoordinatedShadContextMenuState extends State<CoordinatedShadContextMenu> with WidgetsBindingObserver {
  final GlobalKey _triggerKey = GlobalKey();
  late final ShadContextMenuController _internalController = ShadContextMenuController(isOpen: widget.visible ?? false);
  ShadAnchorBase? _frozenAnchor;
  bool _globalPointerRouteAttached = false;
  bool _anchorRefreshScheduled = false;

  ShadContextMenuController get _controller => widget.controller ?? _internalController;
  BuildContext? get _effectiveBoundaryContext => widget.boundaryContext ?? ShadContextMenuBoundary.maybeOf(context);
  double? get _effectiveEstimatedMenuWidth => _resolveEstimatedMenuWidth(widget.constraints, widget.estimatedMenuWidth);
  double? get _effectiveEstimatedMenuHeight => _resolveEstimatedMenuHeight(widget.constraints, widget.estimatedMenuHeight);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleChanged);
    _controller.addListener(_syncFrozenAnchor);
    _controller.addListener(_syncGlobalPointerRoute);
    ShadTopLevelContextMenuCoordinator.register(_controller);
  }

  @override
  void didUpdateWidget(covariant CoordinatedShadContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldController = oldWidget.controller ?? _internalController;
    final newController = _controller;
    if (!identical(oldController, newController)) {
      oldController.removeListener(_handleChanged);
      oldController.removeListener(_syncFrozenAnchor);
      oldController.removeListener(_syncGlobalPointerRoute);
      ShadTopLevelContextMenuCoordinator.unregister(oldController);
      newController.addListener(_handleChanged);
      newController.addListener(_syncFrozenAnchor);
      newController.addListener(_syncGlobalPointerRoute);
      ShadTopLevelContextMenuCoordinator.register(newController);
    }

    if (widget.visible != null) {
      newController.setOpen(widget.visible!);
    }

    _scheduleFrozenAnchorRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleFrozenAnchorRefresh();
  }

  @override
  void didChangeMetrics() {
    _scheduleFrozenAnchorRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachGlobalPointerRoute();
    ShadTopLevelContextMenuCoordinator.unregister(_controller);
    _controller.removeListener(_handleChanged);
    _controller.removeListener(_syncFrozenAnchor);
    _controller.removeListener(_syncGlobalPointerRoute);
    if (widget.controller == null) {
      _internalController.dispose();
    }
    super.dispose();
  }

  void _handleChanged() {
    ShadTopLevelContextMenuCoordinator.handleChanged(_controller);
  }

  void _syncGlobalPointerRoute() {
    final shouldAttach = _controller.isOpen && _effectiveEstimatedMenuWidth != null && _effectiveEstimatedMenuHeight != null;
    if (shouldAttach) {
      _attachGlobalPointerRoute();
    } else {
      _detachGlobalPointerRoute();
    }
  }

  void _attachGlobalPointerRoute() {
    if (_globalPointerRouteAttached) {
      return;
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointerEvent);
    _globalPointerRouteAttached = true;
  }

  void _detachGlobalPointerRoute() {
    if (!_globalPointerRouteAttached) {
      return;
    }
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handleGlobalPointerEvent);
    _globalPointerRouteAttached = false;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (!_controller.isOpen || event is! PointerDownEvent) {
      return;
    }

    final triggerRenderBox = _safeRenderBox(_triggerKey.currentContext);
    final triggerRect = _globalRectForRenderBox(triggerRenderBox);
    if (triggerRect != null && triggerRect.inflate(1).contains(event.position)) {
      return;
    }

    final menuWidth = _effectiveEstimatedMenuWidth;
    final menuHeight = _effectiveEstimatedMenuHeight;
    final triggerContext = _triggerKey.currentContext;
    if (menuWidth == null || menuHeight == null || triggerContext == null) {
      return;
    }

    final menuRect = _computeGlobalMenuRect(
      triggerContext: triggerContext,
      anchor: _effectiveAnchor,
      boundaryContext: _effectiveBoundaryContext,
      menuWidth: menuWidth,
      menuHeight: menuHeight,
    );
    if (menuRect != null && menuRect.inflate(8).contains(event.position)) {
      return;
    }

    _controller.hide();
  }

  void _syncFrozenAnchor() {
    if (!mounted) {
      return;
    }
    final controller = _controller;

    if (controller.isOpen) {
      final anchor = _resolveDynamicAnchor();
      if (_frozenAnchor != anchor) {
        setState(() {
          _frozenAnchor = anchor;
        });
      }
    }
  }

  void _scheduleFrozenAnchorRefresh() {
    if (!mounted || !_controller.isOpen || _anchorRefreshScheduled) {
      return;
    }

    _anchorRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorRefreshScheduled = false;
      if (!mounted || !_controller.isOpen) {
        return;
      }

      _syncFrozenAnchor();
    });
  }

  ShadAnchorBase _resolveDynamicAnchor() {
    final explicitAnchor = widget.anchor;
    if (explicitAnchor != null) {
      return explicitAnchor;
    }

    final triggerContext = _triggerKey.currentContext;
    return resolveAdaptiveShadMenuAnchor(
      triggerContext ?? context,
      boundaryContext: _effectiveBoundaryContext,
      gap: widget.anchorGap,
      estimatedMenuWidth: widget.estimatedMenuWidth,
      estimatedMenuHeight: widget.estimatedMenuHeight,
      horizontalPosition: widget.horizontalPosition,
      verticalPosition: widget.verticalPosition,
      viewportVerticalSplit: widget.viewportVerticalSplit,
      viewportEdgePadding: widget.viewportEdgePadding,
      centerHorizontallyInBoundary: widget.centerHorizontallyInBoundary,
    );
  }

  ShadAnchorBase get _effectiveAnchor {
    return _frozenAnchor ?? _resolveDynamicAnchor();
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenu(
      anchor: _effectiveAnchor,
      visible: widget.visible,
      constraints: widget.constraints,
      onHoverArea: widget.onHoverArea,
      padding: widget.padding,
      groupId: widget.groupId,
      shadows: widget.shadows,
      decoration: widget.decoration,
      filter: widget.filter,
      controller: _controller,
      onTapOutside: widget.onTapOutside,
      onTapInside: widget.onTapInside,
      onTapUpInside: widget.onTapUpInside,
      onTapUpOutside: widget.onTapUpOutside,
      popoverReverseDuration: widget.popoverReverseDuration,
      items: widget.items,
      child: SizedBox(key: _triggerKey, child: widget.child),
    );
  }
}

class CoordinatedShadContextMenuRegion extends StatefulWidget {
  const CoordinatedShadContextMenuRegion({
    super.key,
    required this.child,
    required this.items,
    this.visible,
    this.constraints,
    this.onHoverArea,
    this.padding,
    this.groupId,
    this.shadows,
    this.decoration,
    this.filter,
    this.controller,
    this.supportedDevices,
    this.longPressEnabled,
    this.tapEnabled,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.popoverReverseDuration,
  });

  final Widget child;
  final List<Widget> items;
  final bool? visible;
  final BoxConstraints? constraints;
  final ValueChanged<bool>? onHoverArea;
  final EdgeInsetsGeometry? padding;
  final Object? groupId;
  final List<BoxShadow>? shadows;
  final ShadDecoration? decoration;
  final ImageFilter? filter;
  final ShadContextMenuController? controller;
  final Set<PointerDeviceKind>? supportedDevices;
  final bool? longPressEnabled;
  final bool? tapEnabled;
  final HitTestBehavior hitTestBehavior;
  final Duration? popoverReverseDuration;

  @override
  State<CoordinatedShadContextMenuRegion> createState() => _CoordinatedShadContextMenuRegionState();
}

class _CoordinatedShadContextMenuRegionState extends State<CoordinatedShadContextMenuRegion> {
  late final ShadContextMenuController _internalController = ShadContextMenuController(isOpen: widget.visible ?? false);
  Offset? _offset;

  ShadContextMenuController get _controller => widget.controller ?? _internalController;
  final isContextMenuAlreadyDisabled = kIsWeb && !BrowserContextMenu.enabled;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
    ShadTopLevelContextMenuCoordinator.register(_controller);
  }

  @override
  void didUpdateWidget(covariant CoordinatedShadContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldController = oldWidget.controller ?? _internalController;
    final newController = _controller;
    if (!identical(oldController, newController)) {
      oldController.removeListener(_handleChanged);
      ShadTopLevelContextMenuCoordinator.unregister(oldController);
      newController.addListener(_handleChanged);
      ShadTopLevelContextMenuCoordinator.register(newController);
    }

    if (widget.visible != null) {
      newController.setOpen(widget.visible!);
    }
  }

  @override
  void dispose() {
    ShadTopLevelContextMenuCoordinator.unregister(_controller);
    _controller.removeListener(_handleChanged);
    if (widget.controller == null) {
      _internalController.dispose();
    }
    super.dispose();
  }

  void _handleChanged() {
    ShadTopLevelContextMenuCoordinator.handleChanged(_controller);
  }

  void _showAtOffset(Offset offset) {
    if (!mounted) {
      return;
    }
    setState(() {
      _offset = offset;
    });
    _controller.show();
  }

  void _hide() {
    _controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLongPressEnabled =
        widget.longPressEnabled ?? (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final effectiveTapEnabled =
        widget.tapEnabled ?? (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    return ShadContextMenu(
      anchor: _offset == null ? null : ShadGlobalAnchor(_offset!),
      visible: widget.visible,
      constraints: widget.constraints,
      onHoverArea: widget.onHoverArea,
      padding: widget.padding,
      groupId: widget.groupId,
      shadows: widget.shadows,
      decoration: widget.decoration,
      filter: widget.filter,
      controller: _controller,
      popoverReverseDuration: widget.popoverReverseDuration,
      items: widget.items,
      child: ShadGestureDetector(
        behavior: widget.hitTestBehavior,
        supportedDevices: widget.supportedDevices,
        onTapDown: (details) {
          if (effectiveTapEnabled) {
            if (_controller.isOpen) {
              _hide();
            } else {
              _showAtOffset(details.globalPosition);
            }
          } else {
            _hide();
          }
        },
        onSecondaryTapDown: (details) async {
          if (ShadTopLevelContextMenuCoordinator.shouldSuppressSecondaryTapAt(details.globalPosition)) {
            return;
          }
          if (kIsWeb && !isContextMenuAlreadyDisabled) {
            await BrowserContextMenu.disableContextMenu();
          }
          if (!isWindows) {
            _showAtOffset(details.globalPosition);
          }
        },
        onSecondaryTapUp: (details) async {
          if (ShadTopLevelContextMenuCoordinator.shouldSuppressSecondaryTapAt(details.globalPosition)) {
            if (kIsWeb && !isContextMenuAlreadyDisabled) {
              await BrowserContextMenu.enableContextMenu();
            }
            return;
          }
          if (isWindows) {
            _showAtOffset(details.globalPosition);
            await Future<void>.delayed(Duration.zero);
          }
          if (kIsWeb && !isContextMenuAlreadyDisabled) {
            await BrowserContextMenu.enableContextMenu();
          }
        },
        onLongPressStart: effectiveLongPressEnabled
            ? (details) {
                _offset = details.globalPosition;
              }
            : null,
        onLongPress: effectiveLongPressEnabled
            ? () {
                final offset = _offset;
                if (offset != null) {
                  _showAtOffset(offset);
                }
              }
            : null,
        child: widget.child,
      ),
    );
  }
}
