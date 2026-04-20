import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const double shadDialogScrollViewportVerticalInset = 18;
const EdgeInsets shadDialogScrollableListPadding = EdgeInsets.only(bottom: shadDialogScrollViewportVerticalInset);
const double shadMobileFlowDialogContentSectionGap = 12;
const EdgeInsets shadMobileFlowDialogCompactPadding = EdgeInsets.fromLTRB(24, 24, 24, 28);
const double _shadFlowDialogPrecisionErrorTolerance = 0.001;

const double _mobileFlowDialogButtonSize = 40;
const double _mobileFlowDialogIconSize = 24;

enum ShadMobileFlowDialogBodyBehavior { inherit, scrollable, formScrollable, fill }

class ShadMobileFlowDialogCenteredTitleBar extends StatelessWidget {
  const ShadMobileFlowDialogCenteredTitleBar({super.key, required this.title, this.closeIconData, this.onClose});

  final Widget title;
  final IconData? closeIconData;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _mobileFlowDialogButtonSize,
      child: Row(
        children: [
          const SizedBox(width: _mobileFlowDialogButtonSize),
          const SizedBox(width: 8),
          Expanded(child: Center(child: title)),
          const SizedBox(width: 8),
          _ShadMobileFlowDialogCloseButton(iconData: closeIconData, onPressed: onClose),
        ],
      ),
    );
  }
}

class ShadMobileFlowDialogTitleBar extends StatelessWidget {
  const ShadMobileFlowDialogTitleBar({super.key, required this.title, this.closeIconData, this.onClose});

  final Widget title;
  final IconData? closeIconData;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _mobileFlowDialogButtonSize,
      child: Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          _ShadMobileFlowDialogCloseButton(iconData: closeIconData, onPressed: onClose),
        ],
      ),
    );
  }
}

class ShadMobileFlowDialogSurface extends StatefulWidget {
  const ShadMobileFlowDialogSurface({
    super.key,
    required this.constraints,
    required this.backgroundColor,
    required this.radius,
    required this.border,
    required this.shadows,
    required this.padding,
    required this.title,
    required this.description,
    required this.body,
    required this.actions,
    required this.gap,
    required this.actionsGap,
    required this.bodyBehavior,
    required this.usesHorizontalActionRow,
    required this.keyboardInset,
    required this.hideActionsWhenKeyboardVisible,
    this.scrollableBodyPadding = shadDialogScrollableListPadding,
    this.contentSectionGap = shadMobileFlowDialogContentSectionGap,
  });

  final BoxConstraints? constraints;
  final Color backgroundColor;
  final BorderRadius radius;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry padding;
  final Widget? title;
  final Widget? description;
  final Widget? body;
  final List<Widget> actions;
  final double gap;
  final double actionsGap;
  final ShadMobileFlowDialogBodyBehavior bodyBehavior;
  final bool usesHorizontalActionRow;
  final double keyboardInset;
  final bool hideActionsWhenKeyboardVisible;
  final EdgeInsets scrollableBodyPadding;
  final double contentSectionGap;

  @override
  State<ShadMobileFlowDialogSurface> createState() => _ShadMobileFlowDialogSurfaceState();
}

class _ShadMobileFlowDialogSurfaceState extends State<ShadMobileFlowDialogSurface> {
  final _measureKey = GlobalKey();
  final _measureBodyKey = GlobalKey();
  double? _measuredContentHeight;
  double? _measuredBodyHeight;

  void _scheduleMeasurement() {
    if (widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.fill) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMeasurement();
    });
  }

  void _updateMeasurement() {
    if (!mounted) {
      return;
    }

    final measureContext = _measureKey.currentContext;
    if (measureContext == null) {
      return;
    }

    final renderBox = measureContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }

    final nextContentHeight = renderBox.size.height;
    final nextBodyHeight = _naturalBodyHeightForBehavior();
    if ((_measuredContentHeight == nextContentHeight) && (_measuredBodyHeight == nextBodyHeight)) {
      return;
    }

    setState(() {
      _measuredContentHeight = nextContentHeight;
      _measuredBodyHeight = nextBodyHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final routeBarrierDismissible = ModalRoute.of(context)?.barrierDismissible ?? true;
    final heightConstraints = widget.constraints ?? const BoxConstraints();
    final hasFixedHeight =
        heightConstraints.hasBoundedHeight &&
        (heightConstraints.maxHeight - heightConstraints.minHeight).abs() < _shadFlowDialogPrecisionErrorTolerance;
    final requiresMeasurement = widget.bodyBehavior != ShadMobileFlowDialogBodyBehavior.fill && !hasFixedHeight;
    final pinsFooterDuringKeyboard = widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.formScrollable;
    final surfaceKeyboardInset = pinsFooterDuringKeyboard ? 0.0 : widget.keyboardInset;
    final shouldRelaxClip = pinsFooterDuringKeyboard && widget.keyboardInset > 0;
    if (requiresMeasurement) {
      _scheduleMeasurement();
    }

    final resolvedPadding = widget.padding.resolve(Directionality.of(context));
    final minHeight = heightConstraints.hasBoundedHeight ? heightConstraints.minHeight : 0.0;
    final maxHeight = heightConstraints.hasBoundedHeight ? heightConstraints.maxHeight : double.infinity;
    final measuredHeight = requiresMeasurement
        ? ((_measuredContentHeight ?? (minHeight - resolvedPadding.vertical).clamp(0.0, minHeight).toDouble()) + resolvedPadding.vertical)
        : maxHeight;
    final targetHeight = measuredHeight.clamp(minHeight, maxHeight).toDouble();
    final hideActionsForKeyboard =
        widget.hideActionsWhenKeyboardVisible &&
        widget.keyboardInset > 0 &&
        (widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.scrollable ||
            widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.formScrollable);
    final keyboardLiftOffset = pinsFooterDuringKeyboard && widget.keyboardInset > 0
        ? widget.keyboardInset.clamp(0.0, (maxHeight - targetHeight).clamp(0.0, widget.keyboardInset).toDouble()).toDouble()
        : 0.0;
    final bodyKeyboardInset = pinsFooterDuringKeyboard
        ? (widget.keyboardInset - keyboardLiftOffset).clamp(0.0, widget.keyboardInset).toDouble()
        : widget.keyboardInset;
    final visibleFrame = _ShadMobileFlowDialogFrame(
      title: widget.title,
      description: widget.description,
      body: _buildVisibleBody(keyboardInset: bodyKeyboardInset),
      actions: hideActionsForKeyboard ? const <Widget>[] : widget.actions,
      gap: widget.gap,
      actionsGap: widget.actionsGap,
      expandBody: true,
      usesHorizontalActionRow: widget.usesHorizontalActionRow,
      contentSectionGap: widget.contentSectionGap,
    );
    final provisionalFrame = requiresMeasurement
        ? _ShadMobileFlowDialogFrame(
            title: widget.title,
            description: widget.description,
            body: _buildMeasuredBody(includeMeasureKey: false),
            actions: widget.actions,
            gap: widget.gap,
            actionsGap: widget.actionsGap,
            expandBody: false,
            usesHorizontalActionRow: widget.usesHorizontalActionRow,
            contentSectionGap: widget.contentSectionGap,
          )
        : null;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: pinsFooterDuringKeyboard ? keyboardLiftOffset : surfaceKeyboardInset),
      child: SizedBox.expand(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: routeBarrierDismissible ? () => Navigator.of(context).maybePop() : null,
                child: const SizedBox.expand(),
              ),
            ),
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (requiresMeasurement)
                  Offstage(
                    child: IgnorePointer(
                      child: ExcludeFocus(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: widget.constraints?.minWidth ?? 0.0,
                            maxWidth: widget.constraints?.maxWidth ?? double.infinity,
                          ),
                          child: Padding(
                            padding: widget.padding,
                            child: NotificationListener<SizeChangedLayoutNotification>(
                              onNotification: (_) {
                                _scheduleMeasurement();
                                return false;
                              },
                              child: SizeChangedLayoutNotifier(
                                child: KeyedSubtree(
                                  key: _measureKey,
                                  child: _ShadMobileFlowDialogFrame(
                                    title: widget.title,
                                    description: widget.description,
                                    body: _buildMeasuredBody(),
                                    actions: widget.actions,
                                    gap: widget.gap,
                                    actionsGap: widget.actionsGap,
                                    expandBody: false,
                                    usesHorizontalActionRow: widget.usesHorizontalActionRow,
                                    contentSectionGap: widget.contentSectionGap,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: widget.constraints?.minWidth ?? 0.0,
                    maxWidth: widget.constraints?.maxWidth ?? double.infinity,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.backgroundColor,
                      borderRadius: widget.radius,
                      border: widget.border,
                      boxShadow: widget.shadows,
                    ),
                    child: ClipRRect(
                      borderRadius: widget.radius,
                      clipBehavior: shouldRelaxClip ? Clip.none : Clip.antiAlias,
                      child: SizedBox(
                        height: targetHeight,
                        child: Padding(
                          padding: widget.padding,
                          child: !requiresMeasurement || _measuredContentHeight != null
                              ? visibleFrame
                              : SingleChildScrollView(child: provisionalFrame!),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double? _naturalBodyHeightForBehavior() {
    if (widget.body == null) {
      return 0.0;
    }

    switch (widget.bodyBehavior) {
      case ShadMobileFlowDialogBodyBehavior.fill:
        return null;
      case ShadMobileFlowDialogBodyBehavior.inherit:
      case ShadMobileFlowDialogBodyBehavior.scrollable:
      case ShadMobileFlowDialogBodyBehavior.formScrollable:
        final bodyContext = _measureBodyKey.currentContext;
        final renderBox = bodyContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          return null;
        }
        return renderBox.size.height;
    }
  }

  Widget _buildMeasuredBody({bool includeMeasureKey = true}) {
    final body = widget.body;
    if (body == null) {
      return const SizedBox.shrink();
    }

    Widget content = includeMeasureKey ? KeyedSubtree(key: _measureBodyKey, child: body) : body;
    if (widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.scrollable ||
        widget.bodyBehavior == ShadMobileFlowDialogBodyBehavior.formScrollable) {
      content = Padding(padding: widget.scrollableBodyPadding, child: content);
    }
    return content;
  }

  Widget _buildVisibleBody({required double keyboardInset}) {
    final body = widget.body;
    if (body == null) {
      return const SizedBox.shrink();
    }

    return switch (widget.bodyBehavior) {
      ShadMobileFlowDialogBodyBehavior.inherit => Align(alignment: Alignment.topCenter, child: body),
      ShadMobileFlowDialogBodyBehavior.scrollable => ShadFlowDialogScrollableBody(
        contentHeight: _measuredBodyHeight,
        centerSparseContent: true,
        padding: widget.scrollableBodyPadding,
        child: body,
      ),
      ShadMobileFlowDialogBodyBehavior.formScrollable => ShadFlowDialogScrollableBody(
        contentHeight: _measuredBodyHeight,
        centerSparseContent: false,
        keyboardInset: keyboardInset,
        padding: widget.scrollableBodyPadding,
        child: body,
      ),
      ShadMobileFlowDialogBodyBehavior.fill => ShadFlowDialogFillBody(padding: widget.scrollableBodyPadding, child: body),
    };
  }
}

class ShadFlowDialogScrollableBody extends StatelessWidget {
  const ShadFlowDialogScrollableBody({
    super.key,
    required this.child,
    this.padding = shadDialogScrollableListPadding,
    this.maxWidth,
    this.contentHeight,
    this.centerSparseContent = false,
    this.keyboardInset = 0.0,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? maxWidth;
  final double? contentHeight;
  final bool centerSparseContent;
  final double keyboardInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectivePadding = padding.copyWith(bottom: padding.bottom + keyboardInset);
        final minContentHeight = (constraints.maxHeight - effectivePadding.vertical).clamp(0.0, constraints.maxHeight).toDouble();
        final canScroll = !centerSparseContent || contentHeight == null || contentHeight! > (minContentHeight + 1);
        final shouldCenter = centerSparseContent && contentHeight != null && contentHeight! <= (minContentHeight * 0.45);

        Widget content = child;

        if (maxWidth != null) {
          content = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: content,
            ),
          );
        }

        return SingleChildScrollView(
          physics: canScroll ? null : const NeverScrollableScrollPhysics(),
          padding: effectivePadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minContentHeight),
            child: Align(alignment: shouldCenter ? Alignment.center : Alignment.topCenter, child: content),
          ),
        );
      },
    );
  }
}

class ShadFlowDialogFillBody extends StatelessWidget {
  const ShadFlowDialogFillBody({super.key, required this.child, this.padding = shadDialogScrollableListPadding, this.maxWidth});

  final Widget child;
  final EdgeInsets padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = (constraints.maxHeight - padding.vertical).clamp(0.0, constraints.maxHeight).toDouble();

        Widget content = SizedBox(width: double.infinity, height: availableHeight, child: child);

        if (maxWidth != null) {
          content = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: content,
            ),
          );
        }

        return Padding(padding: padding, child: content);
      },
    );
  }
}

class _ShadMobileFlowDialogCloseButton extends StatelessWidget {
  const _ShadMobileFlowDialogCloseButton({this.iconData, this.onPressed});

  final IconData? iconData;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadIconButton.ghost(
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      width: _mobileFlowDialogButtonSize,
      height: _mobileFlowDialogButtonSize,
      padding: EdgeInsets.zero,
      foregroundColor: theme.colorScheme.foreground.withValues(alpha: .5),
      hoverBackgroundColor: Colors.transparent,
      hoverForegroundColor: theme.colorScheme.foreground,
      pressedForegroundColor: theme.colorScheme.foreground,
      icon: Icon(iconData ?? LucideIcons.x, size: _mobileFlowDialogIconSize),
    );
  }
}

class _ShadMobileFlowDialogFrame extends StatelessWidget {
  const _ShadMobileFlowDialogFrame({
    required this.title,
    required this.description,
    required this.body,
    required this.actions,
    required this.gap,
    required this.actionsGap,
    required this.expandBody,
    required this.usesHorizontalActionRow,
    required this.contentSectionGap,
  });

  final Widget? title;
  final Widget? description;
  final Widget? body;
  final List<Widget> actions;
  final double gap;
  final double actionsGap;
  final bool expandBody;
  final bool usesHorizontalActionRow;
  final double contentSectionGap;

  @override
  Widget build(BuildContext context) {
    final headerChildren = <Widget>[if (title != null) title!, if (description != null) description!];
    final headerSection = headerChildren.isEmpty
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildVerticalSection(headerChildren, spacing: gap),
          );

    final bodyContent = body ?? const SizedBox.shrink();
    final bodySection = expandBody ? Expanded(child: bodyContent) : bodyContent;
    final actionSection = actions.isEmpty
        ? null
        : usesHorizontalActionRow
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _buildHorizontalSection(actions, spacing: actionsGap),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildVerticalSection(actions, spacing: actionsGap),
          );

    final contentSections = <Widget>[];
    if (headerSection != null) {
      contentSections.add(headerSection);
      contentSections.add(SizedBox(height: contentSectionGap));
    }
    contentSections.add(bodySection);
    if (actionSection != null) {
      contentSections.add(SizedBox(height: gap * 2));
      contentSections.add(actionSection);
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: contentSections,
      ),
    );
  }

  List<Widget> _buildVerticalSection(List<Widget> children, {required double spacing}) {
    final built = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        built.add(SizedBox(height: spacing));
      }
      built.add(children[i]);
    }
    return built;
  }

  List<Widget> _buildHorizontalSection(List<Widget> children, {required double spacing}) {
    final built = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        built.add(SizedBox(width: spacing));
      }
      built.add(children[i]);
    }
    return built;
  }
}
