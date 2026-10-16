import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import 'pb_spinning_icon.dart';
import 'pb_svg_icon.dart';

enum PbButtonVariant { primary, secondary }

class PbButton extends StatefulWidget {
  const PbButton({
    super.key,
    this.iconAssetName,
    required this.label,
    required this.variant,
    this.iconOnly = false,
    this.iconOnlySize = 48,
    this.height = 40,
    this.horizontalPadding = 18,
    this.iconSize = 18,
    this.iconGap = 10,
    this.iconSpinning = false,
    this.contentOffset = Offset.zero,
    this.backgroundColor,
    this.pressedBackgroundColor,
    this.borderColor,
    this.pressedBorderColor,
    this.foregroundColor,
    this.onPressed,
  });

  final String? iconAssetName;
  final String label;
  final PbButtonVariant variant;
  final bool iconOnly;
  final double iconOnlySize;
  final double height;
  final double horizontalPadding;
  final double iconSize;
  final double iconGap;
  final bool iconSpinning;
  final Offset contentOffset;
  final Color? backgroundColor;
  final Color? pressedBackgroundColor;
  final Color? borderColor;
  final Color? pressedBorderColor;
  final Color? foregroundColor;
  final VoidCallback? onPressed;

  @override
  State<PbButton> createState() => _PbButtonState();
}

class _PbButtonState extends State<PbButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isPrimary => widget.variant == PbButtonVariant.primary;
  bool get _lifted => _hovered && !_pressed;
  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final idleBorderColor = widget.borderColor ?? (_isPrimary ? PbColors.surfaceActionPrimary : PbColors.borderSoft);
    final activeBorderColor =
        widget.pressedBorderColor ?? widget.borderColor ?? (_isPrimary ? PbColors.surfaceActionPrimary : PbColors.borderStateSelected);
    final borderColor = _pressed ? activeBorderColor : idleBorderColor;
    final idleGradientColors = widget.backgroundColor != null
        ? [widget.backgroundColor!, widget.backgroundColor!]
        : (_isPrimary
              ? const [PbColors.surfaceRailActive, PbColors.surfaceActionPrimary]
              : const [PbColors.surfacePanel, PbColors.surfacePanelSoft]);
    final pressedGradientColors = widget.pressedBackgroundColor != null
        ? [widget.pressedBackgroundColor!, widget.pressedBackgroundColor!]
        : widget.backgroundColor != null
        ? [widget.backgroundColor!, widget.backgroundColor!]
        : (_isPrimary
              ? const [PbColors.surfaceActionPrimary, PbColors.surfaceActionPrimary]
              : const [PbColors.surfaceStateSelected, PbColors.surfaceStateSelected]);
    final gradientColors = _pressed ? pressedGradientColors : idleGradientColors;
    final boxShadow = _pressed
        ? PbShadows.statePressedInset
        : _lifted
        ? PbShadows.stateHover
        : null;
    final textColor = widget.foregroundColor ?? (_isPrimary ? PbColors.textInverse : PbColors.textPrimary);

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        child: Transform.translate(
          offset: Offset(0, _lifted ? -1 : 0),
          child: Opacity(
            opacity: _enabled ? 1 : 0.42,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: widget.iconOnly ? widget.iconOnlySize : widget.height,
              constraints: BoxConstraints(minWidth: widget.iconOnly ? widget.iconOnlySize : 0),
              padding: EdgeInsets.symmetric(horizontal: widget.iconOnly ? 0 : widget.horizontalPadding),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.iconOnly ? PbRadii.medium : PbRadii.small),
                border: Border.all(color: borderColor),
                gradient: LinearGradient(colors: gradientColors, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                boxShadow: boxShadow,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final label = Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: PowerboardsTypography.button.copyWith(color: textColor),
                  );
                  final shouldFlexLabel = constraints.maxWidth.isFinite && constraints.maxWidth < 180;

                  return Transform.translate(
                    offset: widget.contentOffset,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.iconAssetName != null)
                          widget.iconSpinning
                              ? PbSpinningIcon(
                                  assetName: widget.iconAssetName!,
                                  size: widget.iconOnly ? 20 : widget.iconSize,
                                  color: textColor,
                                )
                              : PbSvgIcon(assetName: widget.iconAssetName!, size: widget.iconOnly ? 20 : widget.iconSize, color: textColor),
                        if (!widget.iconOnly && widget.iconAssetName != null) SizedBox(width: widget.iconGap),
                        if (!widget.iconOnly) shouldFlexLabel ? Flexible(child: label) : label,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PbTertiaryButton extends StatelessWidget {
  const PbTertiaryButton({super.key, this.iconAssetName, required this.label, this.solid = false, this.onPressed});

  const PbTertiaryButton.solid({super.key, this.iconAssetName, required this.label, this.onPressed}) : solid = true;

  final String? iconAssetName;
  final String label;
  final bool solid;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PbButton(
      iconAssetName: iconAssetName,
      label: label,
      variant: solid ? PbButtonVariant.primary : PbButtonVariant.secondary,
      height: PbSizes.buttonTertiaryHeight,
      horizontalPadding: 14,
      iconSize: 16,
      iconGap: 8,
      onPressed: onPressed,
    );
  }
}
