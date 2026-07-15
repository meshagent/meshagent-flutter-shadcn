import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String defaultThreadCodeFontFamily = 'SourceCodePro';

typedef ThreadAttachmentIconBuilder =
    Widget Function(
      BuildContext context, {
      required String fileName,
      required IconData fallbackIcon,
      required Color? color,
      required bool hovered,
    });

typedef ThreadAttachmentActionIconBuilder = Widget Function(BuildContext context, {required Color? color, required bool hovered});

typedef ThreadMarkdownHeadingPaddingResolver = EdgeInsets? Function(String tag);
typedef ThreadMarkdownHeadingStyleResolver = TextStyle? Function(String tag, TextStyle defaultStyle);
typedef ThreadMarkdownLinkHandler = bool Function(BuildContext context, String url);
typedef ThreadErrorTextResolver = String Function(String errorMessage);

class ThreadTypographyOverride extends InheritedWidget {
  const ThreadTypographyOverride({
    super.key,
    required super.child,
    this.textFontFamily,
    this.codeFontFamily,
    this.threadParagraphBaseFontSize,
    this.threadParagraphLineHeight,
    this.narrowDesktopParagraphBaseFontSize,
    this.bubbleContentPadding,
    this.threadFeedItemSpacing,
    this.useThreadAttachmentStyle = false,
    this.normalizeParticipantDisplayName = false,
    this.showInlineDisclosureCue = false,
    this.useDesktopAuthorHeaderAtNarrowWidths = false,
    this.mineBubbleColor,
    this.mineBubbleTextColor,
    this.mineBubbleLinkColor,
    this.otherHumanBubbleColor,
    this.otherHumanBubbleTextColor,
    this.agentBubbleColor,
    this.agentBubbleBorderColor,
    this.linkColor,
    this.attachmentSurfaceColor,
    this.attachmentBorderColor,
    this.attachmentIconColor,
    this.attachmentActionColor,
    this.attachmentHoverSurfaceColor,
    this.attachmentHoverShadows,
    this.alignAttachmentEdgesWithBubbles = false,
    this.attachmentIconBuilder,
    this.attachmentActionIconBuilder,
    this.codeBlockSurfaceColor,
    this.codeBlockHeaderSurfaceColor,
    this.codeBlockBorderColor,
    this.codeBlockTextColor,
    this.codeBlockHeaderTextColor,
    this.codeBlockHighlightTheme,
    this.codeBlockFontSize,
    this.codeBlockLineHeight,
    this.codeBlockUseTextFontSize = false,
    this.codeBlockWrapLines = false,
    this.codeBlockHeaderFontSize,
    this.codeBlockActionIconSize,
    this.codeBlockActionButtonSize,
    this.inlineCodeTextColor,
    this.inlineCodeBackgroundColor,
    this.inlineCodeHorizontalPadding = false,
    this.suppressRepeatedChatBubbleText = false,
    this.suppressAgentOnlyChatContext = false,
    this.threadErrorSurfaceColor,
    this.threadErrorTextColor,
    this.threadErrorTextResolver,
    this.markdownHorizontalRuleColor,
    this.markdownBlockquoteSideColor,
    this.markdownBlockquoteBackgroundColor,
    this.markdownSuppressHeadingDividers = false,
    this.markdownHeadingPaddingResolver,
    this.markdownHeadingStyleResolver,
    this.markdownLinkHandler,
  });

  final String? textFontFamily;
  final String? codeFontFamily;
  final double? threadParagraphBaseFontSize;
  final double? threadParagraphLineHeight;
  final double? narrowDesktopParagraphBaseFontSize;
  final EdgeInsets? bubbleContentPadding;
  final double? threadFeedItemSpacing;
  final bool useThreadAttachmentStyle;
  final bool normalizeParticipantDisplayName;
  final bool showInlineDisclosureCue;
  final bool useDesktopAuthorHeaderAtNarrowWidths;
  final Color? mineBubbleColor;
  final Color? mineBubbleTextColor;
  final Color? mineBubbleLinkColor;
  final Color? otherHumanBubbleColor;
  final Color? otherHumanBubbleTextColor;
  final Color? agentBubbleColor;
  final Color? agentBubbleBorderColor;
  final Color? linkColor;
  final Color? attachmentSurfaceColor;
  final Color? attachmentBorderColor;
  final Color? attachmentIconColor;
  final Color? attachmentActionColor;
  final Color? attachmentHoverSurfaceColor;
  final List<BoxShadow>? attachmentHoverShadows;
  final bool alignAttachmentEdgesWithBubbles;
  final ThreadAttachmentIconBuilder? attachmentIconBuilder;
  final ThreadAttachmentActionIconBuilder? attachmentActionIconBuilder;
  final Color? codeBlockSurfaceColor;
  final Color? codeBlockHeaderSurfaceColor;
  final Color? codeBlockBorderColor;
  final Color? codeBlockTextColor;
  final Color? codeBlockHeaderTextColor;
  final Map<String, TextStyle>? codeBlockHighlightTheme;
  final double? codeBlockFontSize;
  final double? codeBlockLineHeight;
  final bool codeBlockUseTextFontSize;
  final bool codeBlockWrapLines;
  final double? codeBlockHeaderFontSize;
  final double? codeBlockActionIconSize;
  final double? codeBlockActionButtonSize;
  final Color? inlineCodeTextColor;
  final Color? inlineCodeBackgroundColor;
  final bool inlineCodeHorizontalPadding;
  final bool suppressRepeatedChatBubbleText;
  final bool suppressAgentOnlyChatContext;
  final Color? threadErrorSurfaceColor;
  final Color? threadErrorTextColor;
  final ThreadErrorTextResolver? threadErrorTextResolver;
  final Color? markdownHorizontalRuleColor;
  final Color? markdownBlockquoteSideColor;
  final Color? markdownBlockquoteBackgroundColor;
  final bool markdownSuppressHeadingDividers;
  final ThreadMarkdownHeadingPaddingResolver? markdownHeadingPaddingResolver;
  final ThreadMarkdownHeadingStyleResolver? markdownHeadingStyleResolver;
  final ThreadMarkdownLinkHandler? markdownLinkHandler;

  static ThreadTypographyOverride? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThreadTypographyOverride>();
  }

  static String? maybeTextFontFamilyOf(BuildContext context) {
    return maybeOf(context)?.textFontFamily;
  }

  static String? maybeCodeFontFamilyOf(BuildContext context) {
    return maybeOf(context)?.codeFontFamily;
  }

  static double? maybeNarrowDesktopParagraphBaseFontSizeOf(BuildContext context) {
    return maybeOf(context)?.narrowDesktopParagraphBaseFontSize;
  }

  static double? maybeThreadParagraphBaseFontSizeOf(BuildContext context) {
    return maybeOf(context)?.threadParagraphBaseFontSize;
  }

  static double? maybeThreadParagraphLineHeightOf(BuildContext context) {
    return maybeOf(context)?.threadParagraphLineHeight;
  }

  static EdgeInsets? maybeBubbleContentPaddingOf(BuildContext context) {
    return maybeOf(context)?.bubbleContentPadding;
  }

  static double? maybeThreadFeedItemSpacingOf(BuildContext context) {
    return maybeOf(context)?.threadFeedItemSpacing;
  }

  static bool useThreadAttachmentStyleOf(BuildContext context) {
    return maybeOf(context)?.useThreadAttachmentStyle ?? false;
  }

  static bool normalizeParticipantDisplayNameOf(BuildContext context) {
    return maybeOf(context)?.normalizeParticipantDisplayName ?? false;
  }

  static bool showInlineDisclosureCueOf(BuildContext context) {
    return maybeOf(context)?.showInlineDisclosureCue ?? false;
  }

  static bool useDesktopAuthorHeaderAtNarrowWidthsOf(BuildContext context) {
    return maybeOf(context)?.useDesktopAuthorHeaderAtNarrowWidths ?? false;
  }

  static Color? maybeMineBubbleColorOf(BuildContext context) {
    return maybeOf(context)?.mineBubbleColor;
  }

  static Color? maybeMineBubbleTextColorOf(BuildContext context) {
    return maybeOf(context)?.mineBubbleTextColor;
  }

  static Color? maybeMineBubbleLinkColorOf(BuildContext context) {
    return maybeOf(context)?.mineBubbleLinkColor;
  }

  static Color? maybeOtherHumanBubbleColorOf(BuildContext context) {
    return maybeOf(context)?.otherHumanBubbleColor;
  }

  static Color? maybeOtherHumanBubbleTextColorOf(BuildContext context) {
    return maybeOf(context)?.otherHumanBubbleTextColor;
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

  static Color? maybeAttachmentSurfaceColorOf(BuildContext context) {
    return maybeOf(context)?.attachmentSurfaceColor;
  }

  static Color? maybeAttachmentBorderColorOf(BuildContext context) {
    return maybeOf(context)?.attachmentBorderColor;
  }

  static Color? maybeAttachmentIconColorOf(BuildContext context) {
    return maybeOf(context)?.attachmentIconColor;
  }

  static Color? maybeAttachmentActionColorOf(BuildContext context) {
    return maybeOf(context)?.attachmentActionColor;
  }

  static Color? maybeAttachmentHoverSurfaceColorOf(BuildContext context) {
    return maybeOf(context)?.attachmentHoverSurfaceColor;
  }

  static List<BoxShadow>? maybeAttachmentHoverShadowsOf(BuildContext context) {
    return maybeOf(context)?.attachmentHoverShadows;
  }

  static bool alignAttachmentEdgesWithBubblesOf(BuildContext context) {
    return maybeOf(context)?.alignAttachmentEdgesWithBubbles ?? false;
  }

  static ThreadAttachmentIconBuilder? maybeAttachmentIconBuilderOf(BuildContext context) {
    return maybeOf(context)?.attachmentIconBuilder;
  }

  static ThreadAttachmentActionIconBuilder? maybeAttachmentActionIconBuilderOf(BuildContext context) {
    return maybeOf(context)?.attachmentActionIconBuilder;
  }

  static Color? maybeCodeBlockSurfaceColorOf(BuildContext context) {
    return maybeOf(context)?.codeBlockSurfaceColor;
  }

  static Color? maybeCodeBlockHeaderSurfaceColorOf(BuildContext context) {
    return maybeOf(context)?.codeBlockHeaderSurfaceColor;
  }

  static Color? maybeCodeBlockBorderColorOf(BuildContext context) {
    return maybeOf(context)?.codeBlockBorderColor;
  }

  static Color? maybeCodeBlockTextColorOf(BuildContext context) {
    return maybeOf(context)?.codeBlockTextColor;
  }

  static Color? maybeCodeBlockHeaderTextColorOf(BuildContext context) {
    return maybeOf(context)?.codeBlockHeaderTextColor;
  }

  static Map<String, TextStyle>? maybeCodeBlockHighlightThemeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockHighlightTheme;
  }

  static double? maybeCodeBlockFontSizeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockFontSize;
  }

  static double? maybeCodeBlockLineHeightOf(BuildContext context) {
    return maybeOf(context)?.codeBlockLineHeight;
  }

  static bool codeBlockUseTextFontSizeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockUseTextFontSize ?? false;
  }

  static bool codeBlockWrapLinesOf(BuildContext context) {
    return maybeOf(context)?.codeBlockWrapLines ?? false;
  }

  static double? maybeCodeBlockHeaderFontSizeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockHeaderFontSize;
  }

  static double? maybeCodeBlockActionIconSizeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockActionIconSize;
  }

  static double? maybeCodeBlockActionButtonSizeOf(BuildContext context) {
    return maybeOf(context)?.codeBlockActionButtonSize;
  }

  static Color? maybeInlineCodeTextColorOf(BuildContext context) {
    return maybeOf(context)?.inlineCodeTextColor;
  }

  static Color? maybeInlineCodeBackgroundColorOf(BuildContext context) {
    return maybeOf(context)?.inlineCodeBackgroundColor;
  }

  static bool inlineCodeHorizontalPaddingOf(BuildContext context) {
    return maybeOf(context)?.inlineCodeHorizontalPadding ?? false;
  }

  static bool suppressRepeatedChatBubbleTextOf(BuildContext context) {
    return maybeOf(context)?.suppressRepeatedChatBubbleText ?? false;
  }

  static bool suppressAgentOnlyChatContextOf(BuildContext context) {
    return maybeOf(context)?.suppressAgentOnlyChatContext ?? false;
  }

  static Color? maybeThreadErrorSurfaceColorOf(BuildContext context) {
    return maybeOf(context)?.threadErrorSurfaceColor;
  }

  static Color? maybeThreadErrorTextColorOf(BuildContext context) {
    return maybeOf(context)?.threadErrorTextColor;
  }

  static String resolveThreadErrorText(BuildContext context, String errorMessage) {
    return maybeOf(context)?.threadErrorTextResolver?.call(errorMessage) ?? errorMessage;
  }

  static Color? maybeMarkdownHorizontalRuleColorOf(BuildContext context) {
    return maybeOf(context)?.markdownHorizontalRuleColor;
  }

  static Color? maybeMarkdownBlockquoteSideColorOf(BuildContext context) {
    return maybeOf(context)?.markdownBlockquoteSideColor;
  }

  static Color? maybeMarkdownBlockquoteBackgroundColorOf(BuildContext context) {
    return maybeOf(context)?.markdownBlockquoteBackgroundColor;
  }

  static bool markdownSuppressHeadingDividersOf(BuildContext context) {
    return maybeOf(context)?.markdownSuppressHeadingDividers ?? false;
  }

  static EdgeInsets? maybeMarkdownHeadingPaddingOf(BuildContext context, String tag) {
    return maybeOf(context)?.markdownHeadingPaddingResolver?.call(tag);
  }

  static TextStyle? maybeMarkdownHeadingStyleOf(BuildContext context, String tag, TextStyle defaultStyle) {
    return maybeOf(context)?.markdownHeadingStyleResolver?.call(tag, defaultStyle);
  }

  static ThreadMarkdownLinkHandler? maybeMarkdownLinkHandlerOf(BuildContext context) {
    return maybeOf(context)?.markdownLinkHandler;
  }

  @override
  bool updateShouldNotify(ThreadTypographyOverride oldWidget) {
    return textFontFamily != oldWidget.textFontFamily ||
        codeFontFamily != oldWidget.codeFontFamily ||
        threadParagraphBaseFontSize != oldWidget.threadParagraphBaseFontSize ||
        threadParagraphLineHeight != oldWidget.threadParagraphLineHeight ||
        narrowDesktopParagraphBaseFontSize != oldWidget.narrowDesktopParagraphBaseFontSize ||
        bubbleContentPadding != oldWidget.bubbleContentPadding ||
        threadFeedItemSpacing != oldWidget.threadFeedItemSpacing ||
        useThreadAttachmentStyle != oldWidget.useThreadAttachmentStyle ||
        normalizeParticipantDisplayName != oldWidget.normalizeParticipantDisplayName ||
        showInlineDisclosureCue != oldWidget.showInlineDisclosureCue ||
        useDesktopAuthorHeaderAtNarrowWidths != oldWidget.useDesktopAuthorHeaderAtNarrowWidths ||
        mineBubbleColor != oldWidget.mineBubbleColor ||
        mineBubbleTextColor != oldWidget.mineBubbleTextColor ||
        mineBubbleLinkColor != oldWidget.mineBubbleLinkColor ||
        agentBubbleColor != oldWidget.agentBubbleColor ||
        agentBubbleBorderColor != oldWidget.agentBubbleBorderColor ||
        linkColor != oldWidget.linkColor ||
        attachmentSurfaceColor != oldWidget.attachmentSurfaceColor ||
        attachmentBorderColor != oldWidget.attachmentBorderColor ||
        attachmentIconColor != oldWidget.attachmentIconColor ||
        attachmentActionColor != oldWidget.attachmentActionColor ||
        attachmentHoverSurfaceColor != oldWidget.attachmentHoverSurfaceColor ||
        attachmentHoverShadows != oldWidget.attachmentHoverShadows ||
        alignAttachmentEdgesWithBubbles != oldWidget.alignAttachmentEdgesWithBubbles ||
        attachmentIconBuilder != oldWidget.attachmentIconBuilder ||
        attachmentActionIconBuilder != oldWidget.attachmentActionIconBuilder ||
        codeBlockSurfaceColor != oldWidget.codeBlockSurfaceColor ||
        codeBlockHeaderSurfaceColor != oldWidget.codeBlockHeaderSurfaceColor ||
        codeBlockBorderColor != oldWidget.codeBlockBorderColor ||
        codeBlockTextColor != oldWidget.codeBlockTextColor ||
        codeBlockHeaderTextColor != oldWidget.codeBlockHeaderTextColor ||
        codeBlockHighlightTheme != oldWidget.codeBlockHighlightTheme ||
        codeBlockFontSize != oldWidget.codeBlockFontSize ||
        codeBlockLineHeight != oldWidget.codeBlockLineHeight ||
        codeBlockUseTextFontSize != oldWidget.codeBlockUseTextFontSize ||
        codeBlockWrapLines != oldWidget.codeBlockWrapLines ||
        codeBlockHeaderFontSize != oldWidget.codeBlockHeaderFontSize ||
        codeBlockActionIconSize != oldWidget.codeBlockActionIconSize ||
        codeBlockActionButtonSize != oldWidget.codeBlockActionButtonSize ||
        inlineCodeTextColor != oldWidget.inlineCodeTextColor ||
        inlineCodeBackgroundColor != oldWidget.inlineCodeBackgroundColor ||
        inlineCodeHorizontalPadding != oldWidget.inlineCodeHorizontalPadding ||
        suppressRepeatedChatBubbleText != oldWidget.suppressRepeatedChatBubbleText ||
        suppressAgentOnlyChatContext != oldWidget.suppressAgentOnlyChatContext ||
        threadErrorSurfaceColor != oldWidget.threadErrorSurfaceColor ||
        threadErrorTextColor != oldWidget.threadErrorTextColor ||
        threadErrorTextResolver != oldWidget.threadErrorTextResolver ||
        markdownHorizontalRuleColor != oldWidget.markdownHorizontalRuleColor ||
        markdownBlockquoteSideColor != oldWidget.markdownBlockquoteSideColor ||
        markdownBlockquoteBackgroundColor != oldWidget.markdownBlockquoteBackgroundColor ||
        markdownSuppressHeadingDividers != oldWidget.markdownSuppressHeadingDividers ||
        markdownHeadingPaddingResolver != oldWidget.markdownHeadingPaddingResolver ||
        markdownHeadingStyleResolver != oldWidget.markdownHeadingStyleResolver ||
        markdownLinkHandler != oldWidget.markdownLinkHandler;
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
