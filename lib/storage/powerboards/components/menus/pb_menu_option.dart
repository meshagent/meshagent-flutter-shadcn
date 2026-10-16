import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_svg_icon.dart';

enum PbMenuOptionVisualState { idle, hovered, pressed, disabled }

class PbMenuOption extends StatefulWidget {
  const PbMenuOption({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIconAssetName,
    this.leadingIconTurns = 0,
    this.leadingInitials,
    this.trailingIconAssetName,
    this.singleLine = false,
    this.selected = false,
    this.selectedSurface = false,
    this.alert = false,
    this.info = false,
    this.infoSelected = false,
    this.state,
    this.onPressed,
  }) : assert(leadingIconAssetName == null || leadingInitials == null, 'Use either a leading icon or leading initials.');

  final String title;
  final String? subtitle;
  final String? leadingIconAssetName;
  final double leadingIconTurns;
  final String? leadingInitials;
  final String? trailingIconAssetName;
  final bool singleLine;
  final bool selected;
  final bool selectedSurface;
  final bool alert;
  final bool info;
  final bool infoSelected;
  final PbMenuOptionVisualState? state;
  final VoidCallback? onPressed;

  @override
  State<PbMenuOption> createState() => _PbMenuOptionState();
}

class _PbMenuOptionState extends State<PbMenuOption> {
  static const _iconRotationDuration = Duration(milliseconds: 180);
  bool _isPointerHovered = false;
  bool _isPointerPressed = false;

  PbMenuOptionVisualState get _resolvedState {
    if (widget.state != null) {
      return widget.state!;
    }

    if (_isPointerPressed) {
      return PbMenuOptionVisualState.pressed;
    }

    if (_isPointerHovered) {
      return PbMenuOptionVisualState.hovered;
    }

    return PbMenuOptionVisualState.idle;
  }

  bool get _interactive => !widget.info;
  bool get _isHoveredState => _resolvedState == PbMenuOptionVisualState.hovered || _resolvedState == PbMenuOptionVisualState.pressed;
  bool get _isPressedState => _resolvedState == PbMenuOptionVisualState.pressed;
  bool get _disabled => _resolvedState == PbMenuOptionVisualState.disabled;
  bool get _clipCopy => widget.info;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.infoSelected
        ? PbColors.surfaceAccentSoft
        : widget.selected && widget.selectedSurface
        ? PbColors.surfaceStateSelected
        : widget.alert && _isHoveredState
        ? PbColors.alertSoft
        : (_isHoveredState && _interactive)
        ? PbColors.surfaceAccentSoft
        : Colors.transparent;
    final borderColor = _isPressedState || (widget.selected && widget.selectedSurface) ? PbColors.borderStateSelected : Colors.transparent;
    final iconColor = widget.alert ? PbColors.alert : PbColors.textPrimary;
    final titleColor = widget.alert ? PbColors.alert : PbColors.textPrimary;
    final subtitleColor = widget.alert ? PbColors.alert : PbColors.textMuted;
    final shadow = _isPressedState ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1))] : null;
    final leadingFrameSize = widget.singleLine ? 24.0 : 36.0;
    final leadingIconSize = widget.singleLine ? 20.0 : 18.0;
    final trailingIconSize = widget.singleLine ? 20.0 : 16.0;

    return MouseRegion(
      cursor: _interactive && !_disabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _interactive && widget.state == null ? (_) => setState(() => _isPointerHovered = true) : null,
      onExit: _interactive && widget.state == null
          ? (_) => setState(() {
              _isPointerHovered = false;
              _isPointerPressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive && !_disabled && widget.state == null ? (_) => setState(() => _isPointerPressed = true) : null,
        onTapUp: _interactive && !_disabled && widget.state == null
            ? (_) {
                setState(() => _isPointerPressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: _interactive && !_disabled && widget.state == null ? () => setState(() => _isPointerPressed = false) : null,
        child: Opacity(
          opacity: _disabled ? 0.45 : 1,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.singleLine ? 44 : 72),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.singleLine ? 0 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
              color: backgroundColor,
              boxShadow: shadow,
            ),
            child: Row(
              children: [
                if (widget.leadingIconAssetName != null || widget.leadingInitials != null) ...[
                  SizedBox(
                    width: leadingFrameSize,
                    height: leadingFrameSize,
                    child: Center(
                      child: widget.leadingIconAssetName != null
                          ? AnimatedRotation(
                              turns: widget.leadingIconTurns,
                              duration: _iconRotationDuration,
                              curve: Curves.easeOutCubic,
                              child: PbSvgIcon(assetName: widget.leadingIconAssetName!, size: leadingIconSize, color: iconColor),
                            )
                          : Container(
                              width: widget.singleLine ? 24 : 34,
                              height: widget.singleLine ? 24 : 34,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [PbColors.surfaceRailActive, PbColors.surfaceActionPrimary],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                widget.leadingInitials!,
                                style: widget.singleLine
                                    ? PowerboardsTypography.customAvatarInitials.copyWith(fontSize: 12)
                                    : PowerboardsTypography.customAvatarInitials,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: widget.singleLine ? MainAxisAlignment.center : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: PowerboardsTypography.labelSmall.copyWith(color: titleColor),
                        maxLines: 1,
                        softWrap: false,
                        overflow: _clipCopy ? TextOverflow.clip : TextOverflow.ellipsis,
                      ),
                      if (!widget.singleLine && widget.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          style: PowerboardsTypography.textXSmall.copyWith(fontWeight: FontWeight.w500, color: subtitleColor),
                          maxLines: 1,
                          softWrap: false,
                          overflow: _clipCopy ? TextOverflow.clip : TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailingIconAssetName != null) ...[
                  const SizedBox(width: 12),
                  PbSvgIcon(assetName: widget.trailingIconAssetName!, size: trailingIconSize, color: iconColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
