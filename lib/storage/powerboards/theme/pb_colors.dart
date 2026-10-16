import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PbRuntimePalette {
  const PbRuntimePalette({required this.primary, required this.secondary, required this.tertiary, required this.accent});

  const PbRuntimePalette.defaults()
    : primary = const Color(0xFF04172B),
      secondary = const Color(0xFFDCE8FF),
      tertiary = const Color(0xFFFEFEFF),
      accent = const Color(0xFF2563EB);

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color accent;

  PbRuntimePalette copyWith({Color? primary, Color? secondary, Color? tertiary, Color? accent}) {
    return PbRuntimePalette(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      accent: accent ?? this.accent,
    );
  }
}

abstract final class PbColors {
  static final ValueNotifier<PbRuntimePalette> _runtimePaletteNotifier = ValueNotifier(const PbRuntimePalette.defaults());

  static const surfaceApp = Color(0xFFF6F7FB);
  static const surfacePanel = Color(0xFFFFFFFF);
  static const surfacePanelSoft = Color(0xFFFAFBFD);
  static const surfacePanelWash = Color(0xFFFBFCFE);
  static const surfaceAccentSoft = Color(0xFFEDF3FF);
  static const surfaceRail = Color(0xFF04172B);
  static const surfaceRailActive = Color(0xFF173257);
  static const surfaceActionPrimary = Color(0xFF081A2F);
  static const surfaceSelected = Color(0xFFEAF1FF);
  static const surfaceStateSelected = Color(0xFFEEF4FF);
  static const surfaceRailSelected = Color(0xFF2563EB);

  static const borderSoft = Color(0xFFDFE5EF);
  static const borderFaint = Color(0xFFECF0F5);
  static const borderStateSelected = Color(0xFFC7D8FF);
  static const menuCardBorder = Color.fromARGB(20, 17, 24, 39);
  static const textPrimary = Color(0xFF16181D);
  static const textBody = Color(0xFF2B3445);
  static const textMuted = Color(0xFF687286);
  static const textInverse = Color(0xFFFFFFFF);
  static const textSubtle = Color(0xFF8A93A5);
  static const statusOnline = Color(0xFF28B446);
  static const customGray = Color(0xFF98A2B3);
  static const customBlue = Color(0xFF2563EB);
  static const customAmber = Color(0xFFD98A0F);
  static const customTeal = Color(0xFF0D9488);
  static const customViolet = Color(0xFF7C3AED);
  static const customRose = Color(0xFFE11D48);
  static const customBadgeBg = Color(0xFFEEF9EE);
  static const customBadgeBorder = Color(0xFFD7EDD8);
  static const customBadgeText = Color(0xFF48834C);
  static const customStateSelectedBorder = borderStateSelected;
  static const customStateSelectedSurface = surfaceStateSelected;
  static const customRailSelectedSurface = surfaceRailSelected;
  static const customStateSelectedSurfaceStart = Color(0xFFF8FBFF);
  static const customStateSelectedSurfaceEnd = surfaceStateSelected;
  static const customBrandInk = Color(0xFF111827);
  static const customAlert = Color(0xFFC83B3B);
  static const customAlertSoft = Color(0xFFFFF1F1);
  static const customCodeSurface = Color(0xFF0B1020);
  static const customCodeInlineText = Color(0xFF31588F);
  static const customMenuOpenSurface = Color(0xFFF5F8FF);
  static const meetCameraSurface = Color(0xFF222222);
  static const meetControlAvailable = Color(0xFF0DAE4E);
  static const meetControlUnavailable = Color(0xFFE5484D);

  static const brandInk = customBrandInk;
  static const alert = customAlert;
  static const alertSoft = customAlertSoft;
  static const statusPositive = statusOnline;

  static ValueListenable<PbRuntimePalette> get runtimePaletteListenable => _runtimePaletteNotifier;

  static PbRuntimePalette get runtimePalette => _runtimePaletteNotifier.value;

  static void updateRuntimePalette(PbRuntimePalette palette) {
    _runtimePaletteNotifier.value = palette;
  }

  static Color get dynamicSurfaceWorkspace => runtimePalette.tertiary;

  static Color get dynamicSurfaceApp => dynamicSurfaceWorkspace;

  static Color get dynamicSurfacePanel => surfacePanel;
  static Color get dynamicSurfacePanelSoft => surfacePanelSoft;
  static Color get dynamicSurfacePanelWash => surfacePanelWash;
  static Color get dynamicSurfaceAccentSoft => runtimePalette.secondary;
  static Color get dynamicSurfaceSelected => _shiftRgb(runtimePalette.secondary, red: 14, green: 9);
  static Color get dynamicSurfaceStateSelected => _shiftRgb(runtimePalette.secondary, red: 18, green: 12);
  static Color get dynamicSurfaceRailSelected => runtimePalette.accent;
  static Color get dynamicBorderSoft => borderSoft;
  static Color get dynamicBorderFaint => borderFaint;
  static Color get dynamicBorderStateSelected => _shiftRgb(runtimePalette.secondary, red: -21, green: -16);
  static Color get dynamicSurfaceRailActive => _shiftRgb(runtimePalette.primary, red: 19, green: 27, blue: 44);
  static Color get dynamicSurfaceActionPrimary => _shiftRgb(runtimePalette.primary, red: 4, green: 3, blue: 4);
  static Color get dynamicSurfaceRail => runtimePalette.primary;
  static Color get dynamicCustomBlue => runtimePalette.accent;
  static Color get dynamicCustomStateSelectedBorder => dynamicBorderStateSelected;
  static Color get dynamicCustomStateSelectedSurface => dynamicSurfaceStateSelected;
  static Color get dynamicCustomStateSelectedSurfaceStart => dynamicSurfaceSelected;
  static Color get dynamicCustomStateSelectedSurfaceEnd => dynamicSurfaceStateSelected;
  static Color get dynamicCustomMenuOpenSurface => Color.alphaBlend(dynamicSurfaceSelected.withValues(alpha: 0.5), surfacePanel);
  static Color get dynamicCustomRailSelectedSurface => dynamicSurfaceRailSelected;
  static Color get dynamicOverlay => dynamicSurfaceRailActive.withValues(alpha: 0.52);

  static List<Color> get dynamicPrimaryGradient => [dynamicSurfaceRailActive, dynamicSurfaceActionPrimary];

  static List<Color> get dynamicRailGradient => [dynamicSurfaceActionPrimary, dynamicSurfaceRail, dynamicSurfaceActionPrimary];

  static Color _shiftRgb(Color color, {int red = 0, int green = 0, int blue = 0}) {
    final value = color.toARGB32();
    final alpha = (value >> 24) & 0xFF;
    final baseRed = (value >> 16) & 0xFF;
    final baseGreen = (value >> 8) & 0xFF;
    final baseBlue = value & 0xFF;

    return Color.fromARGB(alpha, (baseRed + red).clamp(0, 255), (baseGreen + green).clamp(0, 255), (baseBlue + blue).clamp(0, 255));
  }
}
