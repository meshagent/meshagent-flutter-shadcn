import 'package:flutter/material.dart';

import 'pb_colors.dart';

abstract final class PbBreakpoints {
  static const shellCompact = 780.0;
  static const shellMobile = 680.0;
  static const roomPanelStack = 920.0;
}

abstract final class PbSizes {
  static const primaryRailWidth = 64.0;
  static const mobileRailHeight = 72.0;
  static const roomPanelDefault = 348.0;
  static const roomPanelResizeHandle = 16.0;
  static const workspaceTopbarHeight = 82.0;
  static const topbarChevron = 18.0;
  static const buttonTertiaryHeight = 36.0;
}

abstract final class PbRadii {
  static const shell = 28.0;
  static const large = 18.0;
  static const medium = 14.0;
  static const small = 10.0;
}

abstract final class PbMotion {
  static const state = Duration(milliseconds: 160);
  static const chevron = Duration(milliseconds: 180);
}

abstract final class PbShadows {
  static const shell = [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 80, offset: Offset(0, 30))];

  static const card = [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.06), blurRadius: 30, offset: Offset(0, 12))];

  static const stateHover = [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))];

  static const statePressedInset = [
    BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.inner),
  ];

  static const railSelected = [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.22), blurRadius: 24, offset: Offset(0, 10))];

  static const avatarSelected = [
    BoxShadow(color: Color.fromARGB(214, 199, 216, 255), blurRadius: 0, spreadRadius: 2),
    BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static BoxShadow softFromTextMuted(double opacity) {
    return BoxShadow(
      color: PbColors.textMuted.withValues(alpha: opacity),
      blurRadius: 18,
      offset: const Offset(0, 6),
    );
  }
}
