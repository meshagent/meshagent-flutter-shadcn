import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String defaultThreadCodeFontFamily = 'SourceCodePro';

class ThreadTypographyOverride extends InheritedWidget {
  const ThreadTypographyOverride({
    super.key,
    required super.child,
    this.textFontFamily,
    this.codeFontFamily,
    this.mineBubbleColor,
    this.agentBubbleColor,
    this.agentBubbleBorderColor,
    this.linkColor,
  });

  final String? textFontFamily;
  final String? codeFontFamily;
  final Color? mineBubbleColor;
  final Color? agentBubbleColor;
  final Color? agentBubbleBorderColor;
  final Color? linkColor;

  static ThreadTypographyOverride? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThreadTypographyOverride>();
  }

  static String? maybeTextFontFamilyOf(BuildContext context) {
    return maybeOf(context)?.textFontFamily;
  }

  static String? maybeCodeFontFamilyOf(BuildContext context) {
    return maybeOf(context)?.codeFontFamily;
  }

  static Color? maybeMineBubbleColorOf(BuildContext context) {
    return maybeOf(context)?.mineBubbleColor;
  }

  static Color? maybeAgentBubbleColorOf(BuildContext context) {
    return maybeOf(context)?.agentBubbleColor;
  }

  static Color? maybeAgentBubbleBorderColorOf(BuildContext context) {
    return maybeOf(context)?.agentBubbleBorderColor;
  }

  static Color? maybeLinkColorOf(BuildContext context) {
    return maybeOf(context)?.linkColor;
  }

  @override
  bool updateShouldNotify(ThreadTypographyOverride oldWidget) {
    return textFontFamily != oldWidget.textFontFamily ||
        codeFontFamily != oldWidget.codeFontFamily ||
        mineBubbleColor != oldWidget.mineBubbleColor ||
        agentBubbleColor != oldWidget.agentBubbleColor ||
        agentBubbleBorderColor != oldWidget.agentBubbleBorderColor ||
        linkColor != oldWidget.linkColor;
  }
}

TextStyle threadTypographyTextStyle(BuildContext context, TextStyle style) {
  final fontFamily = ThreadTypographyOverride.maybeTextFontFamilyOf(context);
  if (fontFamily == null || fontFamily.isEmpty) {
    return style;
  }
  return _plainTextStyleWithFontFamily(style, fontFamily: fontFamily);
}

TextStyle threadTypographyCodeTextStyle(
  BuildContext context, {
  TextStyle? textStyle,
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  TextBaseline? textBaseline,
  double? height,
  Locale? locale,
  Paint? foreground,
  Paint? background,
  List<Shadow>? shadows,
  List<FontFeature>? fontFeatures,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
  TextOverflow? overflow,
  bool inherit = true,
}) {
  final fontFamily = ThreadTypographyOverride.maybeCodeFontFamilyOf(context);
  if (fontFamily != null && fontFamily.isNotEmpty) {
    return _plainTextStyleWithFontFamily(
      textStyle ?? TextStyle(inherit: inherit),
      fontFamily: fontFamily,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      overflow: overflow,
      inherit: inherit,
    );
  }

  return GoogleFonts.sourceCodePro(
    textStyle: textStyle,
    color: color,
    backgroundColor: backgroundColor,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    textBaseline: textBaseline,
    height: height,
    locale: locale,
    foreground: foreground,
    background: background,
    shadows: shadows,
    fontFeatures: fontFeatures,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
  ).copyWith(overflow: overflow, inherit: inherit);
}

TextTheme threadTypographyMaterialTextTheme(TextTheme base, String fontFamily) {
  TextStyle? apply(TextStyle? style) {
    if (style == null) {
      return null;
    }
    return _plainTextStyleWithFontFamily(style, fontFamily: fontFamily);
  }

  return base.copyWith(
    displayLarge: apply(base.displayLarge),
    displayMedium: apply(base.displayMedium),
    displaySmall: apply(base.displaySmall),
    headlineLarge: apply(base.headlineLarge),
    headlineMedium: apply(base.headlineMedium),
    headlineSmall: apply(base.headlineSmall),
    titleLarge: apply(base.titleLarge),
    titleMedium: apply(base.titleMedium),
    titleSmall: apply(base.titleSmall),
    bodyLarge: apply(base.bodyLarge),
    bodyMedium: apply(base.bodyMedium),
    bodySmall: apply(base.bodySmall),
    labelLarge: apply(base.labelLarge),
    labelMedium: apply(base.labelMedium),
    labelSmall: apply(base.labelSmall),
  );
}

ShadTextTheme threadTypographyShadTextTheme(ShadTextTheme base, String fontFamily) {
  TextStyle apply(TextStyle style) => _plainTextStyleWithFontFamily(style, fontFamily: fontFamily);

  return ShadTextTheme.custom(
    canMerge: base.canMerge,
    h1Large: apply(base.h1Large),
    h1: apply(base.h1),
    h2: apply(base.h2),
    h3: apply(base.h3),
    h4: apply(base.h4),
    p: apply(base.p),
    blockquote: apply(base.blockquote),
    table: apply(base.table),
    list: apply(base.list),
    lead: apply(base.lead),
    large: apply(base.large),
    small: apply(base.small),
    muted: apply(base.muted),
    family: fontFamily,
    custom: {for (final entry in base.custom.entries) entry.key: apply(entry.value)},
  );
}

TextStyle _plainTextStyleWithFontFamily(
  TextStyle style, {
  required String fontFamily,
  bool? inherit,
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  TextBaseline? textBaseline,
  double? height,
  TextLeadingDistribution? leadingDistribution,
  Locale? locale,
  Paint? foreground,
  Paint? background,
  List<Shadow>? shadows,
  List<FontFeature>? fontFeatures,
  List<FontVariation>? fontVariations,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
  TextOverflow? overflow,
}) {
  return TextStyle(
    inherit: inherit ?? style.inherit,
    color: color ?? style.color,
    backgroundColor: backgroundColor ?? style.backgroundColor,
    fontSize: fontSize ?? style.fontSize,
    fontWeight: fontWeight ?? style.fontWeight,
    fontStyle: fontStyle ?? style.fontStyle,
    letterSpacing: letterSpacing ?? style.letterSpacing,
    wordSpacing: wordSpacing ?? style.wordSpacing,
    textBaseline: textBaseline ?? style.textBaseline,
    height: height ?? style.height,
    leadingDistribution: leadingDistribution ?? style.leadingDistribution,
    locale: locale ?? style.locale,
    foreground: foreground ?? style.foreground,
    background: background ?? style.background,
    shadows: shadows ?? style.shadows,
    fontFeatures: fontFeatures ?? style.fontFeatures,
    fontVariations: fontVariations ?? style.fontVariations,
    decoration: decoration ?? style.decoration,
    decorationColor: decorationColor ?? style.decorationColor,
    decorationStyle: decorationStyle ?? style.decorationStyle,
    decorationThickness: decorationThickness ?? style.decorationThickness,
    fontFamily: fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    overflow: overflow ?? style.overflow,
  );
}
