import 'package:flutter/material.dart';

import 'pb_colors.dart';

abstract final class PowerboardsTypography {
  static const String fontFamily = 'packages/meshagent_flutter_shadcn/Inter';
  static const String codeFontFamily = 'packages/meshagent_flutter_shadcn/DM Mono';

  static const TextStyle h1Large = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 19,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.28,
    color: PbColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle h4 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle large = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle labelStrong = label;

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static final TextStyle listEmptyState = button.copyWith(color: PbColors.textMuted);

  static const TextStyle p = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.75,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textBody,
  );

  static const TextStyle meta = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textBody,
  );

  static const TextStyle small = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textBody,
  );

  static const TextStyle smallStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: PbColors.textBody,
  );

  static const TextStyle textXSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: PbColors.textBody,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle customButtonSolid = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle customEmptyStateTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle customBrandMark = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle customAvatarInitials = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: PbColors.textInverse,
  );

  static const TextStyle customCodeDisplay = TextStyle(
    fontFamily: codeFontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textBody,
  );

  static const TextStyle buttonPrimary = button;
  static const TextStyle buttonSecondary = button;

  static const TextStyle fieldEyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.08,
    color: PbColors.textMuted,
  );

  static const TextStyle fieldValue = label;

  static const TextStyle railLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: Color(0xBDF8FAFC),
  );

  static const TextStyle avatarInitials = customAvatarInitials;
  static const TextStyle menuTitle = labelSmall;

  static const TextStyle menuSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.08,
    color: PbColors.textMuted,
  );

  static const TextStyle menuFilterText = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textPrimary,
  );

  static const TextStyle menuFilterPlaceholder = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: PbColors.textMuted,
  );
}
