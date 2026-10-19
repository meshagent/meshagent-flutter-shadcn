import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_button.dart';
import '../primitives/pb_svg_icon.dart';

class PbDialogShell extends StatelessWidget {
  const PbDialogShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onClose,
    this.actions,
    this.iconAssetName,
    this.iconColor = PbColors.customBrandInk,
    this.bodyExpanded = false,
    this.maxWidth = 425,
    this.maxHeight = 720,
    this.viewportVerticalInset = 96,
    this.showBackdrop = true,
    this.blurBackdrop = true,
    this.surfacePadding = const EdgeInsets.all(28),
    this.headerPadding = EdgeInsets.zero,
    this.bodyPadding = EdgeInsets.zero,
    this.actionsPadding = EdgeInsets.zero,
    this.headerBodySpacing = 24,
    this.bodyActionsSpacing = 22,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onClose;
  final Widget? actions;
  final String? iconAssetName;
  final Color iconColor;
  final bool bodyExpanded;
  final double maxWidth;
  final double maxHeight;
  final double viewportVerticalInset;
  final bool showBackdrop;
  final bool blurBackdrop;
  final EdgeInsetsGeometry surfacePadding;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsetsGeometry actionsPadding;
  final double headerBodySpacing;
  final double bodyActionsSpacing;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogMaxHeight = math.min(maxHeight, viewport.height - viewportVerticalInset);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: showBackdrop
                ? blurBackdrop
                      ? BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(color: PbColors.surfaceRailActive.withValues(alpha: 0.52)),
                        )
                      : Container(color: PbColors.surfaceRailActive.withValues(alpha: 0.52))
                : const SizedBox.expand(),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: dialogMaxHeight),
                child: Container(
                  padding: surfacePadding,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: PbColors.borderSoft),
                    gradient: const LinearGradient(
                      colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 80, offset: Offset(0, 30))],
                  ),
                  child: Column(
                    mainAxisSize: bodyExpanded ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      Padding(
                        padding: headerPadding,
                        child: _PbDialogHeader(
                          title: title,
                          subtitle: subtitle,
                          iconAssetName: iconAssetName,
                          iconColor: iconColor,
                          onClose: onClose,
                        ),
                      ),
                      if (headerBodySpacing > 0) SizedBox(height: headerBodySpacing),
                      if (bodyExpanded)
                        Expanded(
                          child: Padding(padding: bodyPadding, child: body),
                        )
                      else
                        Padding(padding: bodyPadding, child: body),
                      if (actions != null) ...[
                        if (bodyActionsSpacing > 0) SizedBox(height: bodyActionsSpacing),
                        Padding(padding: actionsPadding, child: actions!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PbDialogActions extends StatelessWidget {
  const PbDialogActions({
    super.key,
    required this.secondaryLabel,
    required this.primaryLabel,
    required this.onSecondaryPressed,
    required this.onPrimaryPressed,
    this.primaryIconAssetName,
  });

  final String secondaryLabel;
  final String primaryLabel;
  final VoidCallback onSecondaryPressed;
  final VoidCallback? onPrimaryPressed;
  final String? primaryIconAssetName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PbButton(label: secondaryLabel, variant: PbButtonVariant.secondary, onPressed: onSecondaryPressed),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Opacity(
            opacity: onPrimaryPressed == null ? 0.42 : 1,
            child: IgnorePointer(
              ignoring: onPrimaryPressed == null,
              child: PbButton(
                label: primaryLabel,
                iconAssetName: primaryIconAssetName,
                variant: PbButtonVariant.primary,
                horizontalPadding: primaryIconAssetName == null ? 18 : 12,
                onPressed: onPrimaryPressed,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PbDialogHeader extends StatelessWidget {
  const _PbDialogHeader({
    required this.title,
    required this.subtitle,
    required this.iconAssetName,
    required this.iconColor,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final String? iconAssetName;
  final Color iconColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (iconAssetName != null) ...[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: PbColors.surfacePanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PbColors.borderSoft),
            ),
            alignment: Alignment.center,
            child: PbSvgIcon(assetName: iconAssetName!, size: 24, color: iconColor),
          ),
          const SizedBox(width: 13),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PowerboardsTypography.h2),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(6, -6),
          child: _PbDialogCloseButton(onPressed: onClose),
        ),
      ],
    );
  }
}

class _PbDialogCloseButton extends StatefulWidget {
  const _PbDialogCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PbDialogCloseButton> createState() => _PbDialogCloseButtonState();
}

class _PbDialogCloseButtonState extends State<_PbDialogCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: Opacity(
              opacity: _hovered ? 1 : 0.3,
              child: const PbSvgIcon(assetName: 'x', size: 18, color: PbColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
