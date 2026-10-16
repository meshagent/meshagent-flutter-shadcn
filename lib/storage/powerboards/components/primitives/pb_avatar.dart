import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';

class PbAvatar extends StatelessWidget {
  const PbAvatar({
    super.key,
    required this.initials,
    this.size = 34,
    this.borderColor,
    this.boxShadow,
    this.textStyle,
    this.textOffset = Offset.zero,
    this.backgroundColor = const LinearGradient(
      colors: [PbColors.surfaceRailActive, PbColors.surfaceActionPrimary],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  });

  final String initials;
  final double size;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final TextStyle? textStyle;
  final Offset textOffset;
  final Gradient backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: backgroundColor,
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: boxShadow,
      ),
      alignment: Alignment.center,
      child: Transform.translate(
        offset: textOffset,
        child: Text(initials, style: textStyle ?? PowerboardsTypography.avatarInitials),
      ),
    );
  }
}
