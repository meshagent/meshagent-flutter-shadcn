import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import 'pb_svg_icon.dart';

const double pbEmptyStateReferenceTopFactor = 0.334;
const double pbEmptyStateReferenceHeaderHeight = 76.0;
const double pbEmptyStateReferenceTopOffset = -pbEmptyStateReferenceHeaderHeight * (1 - pbEmptyStateReferenceTopFactor);

class PbEmptyState extends StatelessWidget {
  const PbEmptyState({
    super.key,
    required this.iconAssetName,
    required this.title,
    required this.subtitle,
    this.topFactor,
    this.iconColor = PbColors.customGray,
    this.titleMaxWidth = 360,
    this.subtitleMaxWidth = 360,
    this.topOffset = 0,
    this.action,
    this.actionTopGap = 12,
  });

  final String iconAssetName;
  final String title;
  final String subtitle;
  final double? topFactor;
  final Color iconColor;
  final double titleMaxWidth;
  final double subtitleMaxWidth;
  final double topOffset;
  final Widget? action;
  final double actionTopGap;

  @override
  Widget build(BuildContext context) {
    final content = _PbEmptyStateContent(
      iconAssetName: iconAssetName,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      titleMaxWidth: titleMaxWidth,
      subtitleMaxWidth: subtitleMaxWidth,
      action: action,
      actionTopGap: actionTopGap,
    );
    final factor = topFactor;

    if (factor == null) {
      return Center(child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final top = math.max(0.0, constraints.maxHeight * factor + topOffset);
        return Stack(
          fit: StackFit.expand,
          children: [Positioned(top: top, left: 0, right: 0, child: content)],
        );
      },
    );
  }
}

class _PbEmptyStateContent extends StatelessWidget {
  const _PbEmptyStateContent({
    required this.iconAssetName,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.titleMaxWidth,
    required this.subtitleMaxWidth,
    required this.action,
    required this.actionTopGap,
  });

  final String iconAssetName;
  final Color iconColor;
  final String title;
  final String subtitle;
  final double titleMaxWidth;
  final double subtitleMaxWidth;
  final Widget? action;
  final double actionTopGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PbSvgIcon(assetName: iconAssetName, size: 46, color: iconColor),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: titleMaxWidth),
          child: Text(title, textAlign: TextAlign.center, style: PowerboardsTypography.customEmptyStateTitle),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: subtitleMaxWidth),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: PowerboardsTypography.p.copyWith(color: PbColors.textMuted),
          ),
        ),
        if (action != null) ...[SizedBox(height: actionTopGap), action!],
      ],
    );
  }
}
