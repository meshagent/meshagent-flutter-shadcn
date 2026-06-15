import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final Highlight _markdownHighlighter = () {
  final highlight = Highlight();
  highlight.registerLanguages(builtinAllLanguages);
  return highlight;
}();

Color chatBubbleMarkdownColor(BuildContext context) {
  final theme = ShadTheme.of(context);
  return theme.textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? theme.colorScheme.foreground;
}

const double chatBubbleMarkdownMobileBaseFontSize = 16;
const double chatBubbleMarkdownThreadLineHeight = 1.45;
const double chatBubbleMarkdownMobileCodeLineHeight = 1.4;

bool chatBubbleMarkdownUsesMobileTypography(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < 600 || (size.width > size.height && size.shortestSide < 600);
}

double chatBubbleMarkdownBaseFontSize(BuildContext context, {bool threadTypography = false}) {
  if (threadTypography && chatBubbleMarkdownUsesMobileTypography(context)) {
    return chatBubbleMarkdownMobileBaseFontSize;
  }

  final defaultFontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
  return MediaQuery.of(context).textScaler.scale(defaultFontSize);
}

Map<String, TextStyle> _codeTheme(BuildContext context) {
  return ThreadTypographyOverride.maybeCodeBlockHighlightThemeOf(context) ?? monokaiSublimeTheme;
}

Map<String, TextStyle> chatBubbleCodeHighlightTheme(BuildContext context) {
  return _codeTheme(context);
}

Color? diffLineBackgroundColor(BuildContext context, String line) {
  if (line.startsWith("+") && !line.startsWith("+++")) {
    return const Color(0x801B5E20);
  }
  if (line.startsWith("-") && !line.startsWith("---")) {
    return const Color(0x807F1D1D);
  }
  return null;
}

String _codeBlockLanguageLabel({required String language, required String languageId}) {
  final trimmedLanguage = language.trim();
  if (trimmedLanguage.isEmpty) {
    return languageId == plaintextLanguageId ? "text" : languageId;
  }
  final resolved = resolveLanguageIdForFilename(trimmedLanguage);
  return (resolved ?? trimmedLanguage).toLowerCase();
}

TextSpan highlightCodeSpanWithReHighlight({
  required BuildContext context,
  required String code,
  required String languageOrFilename,
  required TextStyle textStyle,
  Map<String, TextStyle>? theme,
  String fallbackLanguageId = plaintextLanguageId,
}) {
  final languageId = resolveLanguageIdForFilename(languageOrFilename) ?? fallbackLanguageId;
  final codeTheme = theme ?? _codeTheme(context);
  try {
    final result = _markdownHighlighter.highlight(code: code, language: languageId);
    final renderer = TextSpanRenderer(textStyle, codeTheme);
    result.render(renderer);
    return renderer.span ?? TextSpan(text: code, style: textStyle);
  } catch (_) {
    return TextSpan(text: code, style: textStyle);
  }
}

Widget _buildHighlightedCodeBlock({
  required BuildContext context,
  required String code,
  required String language,
  required TextStyle textStyle,
  required Color? backgroundColor,
}) {
  final theme = ShadTheme.of(context);
  final languageId = resolveLanguageIdForFilename(language) ?? plaintextLanguageId;
  final lines = code.split(RegExp(r"\r?\n"));
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  final normalizedCode = lines.join("\n");
  final usesMobileTypography = chatBubbleMarkdownUsesMobileTypography(context);
  final codeBlockSurfaceColor = ThreadTypographyOverride.maybeCodeBlockSurfaceColorOf(context);
  final codeBlockHeaderSurfaceColor = ThreadTypographyOverride.maybeCodeBlockHeaderSurfaceColorOf(context);
  final codeBlockBorderColor = ThreadTypographyOverride.maybeCodeBlockBorderColorOf(context);
  final codeBlockTextColor = ThreadTypographyOverride.maybeCodeBlockTextColorOf(context);
  final codeBlockHeaderTextColor = ThreadTypographyOverride.maybeCodeBlockHeaderTextColorOf(context);
  final codeBlockTheme = _codeTheme(context);
  final codeBlockWrapLines = ThreadTypographyOverride.codeBlockWrapLinesOf(context);
  final codeBlockHeaderFontSize = ThreadTypographyOverride.maybeCodeBlockHeaderFontSizeOf(context);
  final codeBlockActionIconSize = ThreadTypographyOverride.maybeCodeBlockActionIconSizeOf(context) ?? 14;
  final codeBlockActionButtonSize = ThreadTypographyOverride.maybeCodeBlockActionButtonSizeOf(context) ?? 24;
  final resolvedBackgroundColor = codeBlockSurfaceColor ?? backgroundColor ?? theme.cardTheme.backgroundColor;
  final resolvedTextStyle = codeBlockTextColor == null ? textStyle : textStyle.copyWith(color: codeBlockTextColor);
  final headerTextStyle = threadTypographyCodeTextStyle(
    context,
    fontSize: codeBlockHeaderFontSize ?? (usesMobileTypography ? 13 : 11),
    color: codeBlockHeaderTextColor ?? theme.colorScheme.mutedForeground,
  );
  final body = languageId == "diff"
      ? codeBlockWrapLines
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in lines.indexed)
                      Padding(
                        padding: EdgeInsets.only(bottom: line.$1 < lines.length - 1 ? 2 : 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: diffLineBackgroundColor(context, line.$2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: SelectableText.rich(
                            highlightCodeSpanWithReHighlight(
                              context: context,
                              code: line.$2,
                              languageOrFilename: "diff",
                              textStyle: resolvedTextStyle,
                              theme: codeBlockTheme,
                              fallbackLanguageId: "diff",
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines.indexed)
                      Padding(
                        padding: EdgeInsets.only(bottom: line.$1 < lines.length - 1 ? 2 : 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: diffLineBackgroundColor(context, line.$2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: SelectableText.rich(
                            highlightCodeSpanWithReHighlight(
                              context: context,
                              code: line.$2,
                              languageOrFilename: "diff",
                              textStyle: resolvedTextStyle,
                              theme: codeBlockTheme,
                              fallbackLanguageId: "diff",
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
      : codeBlockWrapLines
      ? Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          child: SelectableText.rich(
            highlightCodeSpanWithReHighlight(
              context: context,
              code: normalizedCode,
              languageOrFilename: language,
              textStyle: resolvedTextStyle,
              theme: codeBlockTheme,
            ),
          ),
        )
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16.0),
          child: SelectableText.rich(
            highlightCodeSpanWithReHighlight(
              context: context,
              code: normalizedCode,
              languageOrFilename: language,
              textStyle: resolvedTextStyle,
              theme: codeBlockTheme,
            ),
          ),
        );

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8.0),
    decoration: BoxDecoration(
      color: resolvedBackgroundColor,
      borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      border: Border.all(color: codeBlockBorderColor ?? theme.colorScheme.border, width: 1),
    ),
    clipBehavior: Clip.antiAlias,
    width: double.infinity,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
          decoration: BoxDecoration(color: codeBlockHeaderSurfaceColor ?? theme.colorScheme.background.withAlpha(150)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _codeBlockLanguageLabel(language: language, languageId: languageId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headerTextStyle,
                ),
              ),
              ShadIconButton.ghost(
                width: codeBlockActionButtonSize,
                height: codeBlockActionButtonSize,
                iconSize: codeBlockActionIconSize,
                icon: Icon(LucideIcons.copy, size: codeBlockActionIconSize, color: codeBlockHeaderTextColor),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: normalizedCode));
                },
              ),
            ],
          ),
        ),
        body,
      ],
    ),
  );
}

MarkdownConfig buildChatBubbleMarkdownConfig(
  BuildContext context, {
  Color? color,
  double? baseFontSize,
  bool threadTypography = false,
  Color? horizontalRuleColor,
  double horizontalRuleHeight = 1,
}) {
  final theme = ShadTheme.of(context);
  final mdColor = color ?? chatBubbleMarkdownColor(context);
  final usesMobileThreadTypography = threadTypography && chatBubbleMarkdownUsesMobileTypography(context);
  final resolvedBaseFontSize = baseFontSize ?? chatBubbleMarkdownBaseFontSize(context, threadTypography: threadTypography);
  final codeTextStyle = threadTypographyCodeTextStyle(
    context,
    fontSize: usesMobileThreadTypography
        ? resolvedBaseFontSize
        : threadTypography
        ? (resolvedBaseFontSize * 0.95).clamp(12.0, 16.0).toDouble()
        : resolvedBaseFontSize,
    color: mdColor,
    height: usesMobileThreadTypography ? chatBubbleMarkdownMobileCodeLineHeight : null,
  );
  final inlineCodeTextStyle = threadTypographyCodeTextStyle(
    context,
    fontSize: codeTextStyle.fontSize,
    color: ThreadTypographyOverride.maybeInlineCodeTextColorOf(context) ?? mdColor,
    backgroundColor: ThreadTypographyOverride.maybeInlineCodeBackgroundColorOf(context),
    height: codeTextStyle.height,
  );
  final paragraphStyle = threadTypographyTextStyle(
    context,
    TextStyle(
      fontSize: resolvedBaseFontSize,
      color: mdColor,
      inherit: false,
      height: threadTypography ? chatBubbleMarkdownThreadLineHeight : null,
    ),
  );
  final linkColor = ThreadTypographyOverride.maybeLinkColorOf(context) ?? theme.linkButtonTheme.foregroundColor;

  final headingBase = threadTypographyTextStyle(
    context,
    TextStyle(
      color: mdColor,
      inherit: false,
      height: threadTypography ? 1.25 : null,
      fontWeight: threadTypography ? FontWeight.w600 : null,
    ),
  );
  final h1Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.55).clamp(20.0, 30.0).toDouble(), height: 1.2, fontWeight: FontWeight.w700)
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold));
  final h2Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.35).clamp(18.0, 26.0).toDouble())
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 1.8, color: mdColor, inherit: false));
  final h3Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.2).clamp(16.0, 22.0).toDouble())
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 1.6, color: mdColor, inherit: false));
  final h4Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.1).clamp(15.0, 20.0).toDouble())
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 1.4, color: mdColor, inherit: false));
  final h5Style = threadTypography
      ? headingBase.copyWith(fontSize: resolvedBaseFontSize.clamp(14.0, 18.0).toDouble())
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 1.2, color: mdColor, inherit: false));
  final h6Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 0.95).clamp(13.0, 16.0).toDouble(), fontWeight: FontWeight.w500)
      : threadTypographyTextStyle(context, TextStyle(fontSize: resolvedBaseFontSize * 1.0, color: mdColor, inherit: false));
  final resolvedH1Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h1.name, h1Style) ?? h1Style;
  final resolvedH2Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h2.name, h2Style) ?? h2Style;
  final resolvedH3Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h3.name, h3Style) ?? h3Style;
  final resolvedH4Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h4.name, h4Style) ?? h4Style;
  final resolvedH5Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h5.name, h5Style) ?? h5Style;
  final resolvedH6Style = ThreadTypographyOverride.maybeMarkdownHeadingStyleOf(context, MarkdownTag.h6.name, h6Style) ?? h6Style;
  final preStyle = threadTypographyCodeTextStyle(
    context,
    fontSize:
        ThreadTypographyOverride.maybeCodeBlockFontSizeOf(context) ??
        (ThreadTypographyOverride.codeBlockUseTextFontSizeOf(context) ? resolvedBaseFontSize : codeTextStyle.fontSize),
    color: ThreadTypographyOverride.maybeCodeBlockTextColorOf(context) ?? mdColor,
    inherit: false,
    height:
        ThreadTypographyOverride.maybeCodeBlockLineHeightOf(context) ??
        (usesMobileThreadTypography
            ? chatBubbleMarkdownMobileCodeLineHeight
            : threadTypography
            ? chatBubbleMarkdownThreadLineHeight
            : null),
  );
  final codeBlockSurfaceColor = ThreadTypographyOverride.maybeCodeBlockSurfaceColorOf(context);
  final codeBlockBorderColor = ThreadTypographyOverride.maybeCodeBlockBorderColorOf(context);
  final resolvedCodeBlockSurfaceColor = codeBlockSurfaceColor ?? theme.cardTheme.backgroundColor;
  final resolvedHorizontalRuleColor =
      horizontalRuleColor ?? ThreadTypographyOverride.maybeMarkdownHorizontalRuleColorOf(context) ?? mdColor.withAlpha(100);
  final suppressHeadingDividers = ThreadTypographyOverride.markdownSuppressHeadingDividersOf(context);
  final blockquoteSideColor = ThreadTypographyOverride.maybeMarkdownBlockquoteSideColorOf(context);

  return MarkdownConfig(
    configs: [
      HrConfig(color: resolvedHorizontalRuleColor, height: horizontalRuleHeight),
      _NoDividerH1Config(style: resolvedH1Style),
      _NoDividerH2Config(style: resolvedH2Style),
      suppressHeadingDividers ? _NoDividerH3Config(style: resolvedH3Style) : H3Config(style: resolvedH3Style),
      H4Config(style: resolvedH4Style),
      H5Config(style: resolvedH5Style),
      H6Config(style: resolvedH6Style),
      PreConfig(
        decoration: BoxDecoration(
          color: resolvedCodeBlockSurfaceColor,
          border: Border.all(color: codeBlockBorderColor ?? theme.colorScheme.border, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        ),
        textStyle: preStyle,
        builder: (code, language) => _buildHighlightedCodeBlock(
          context: context,
          code: code,
          language: language,
          textStyle: preStyle,
          backgroundColor: resolvedCodeBlockSurfaceColor,
        ),
      ),
      PConfig(textStyle: paragraphStyle),
      CodeConfig(style: inlineCodeTextStyle),
      BlockquoteConfig(sideColor: blockquoteSideColor ?? const Color(0xffd0d7de), textColor: mdColor),
      LinkConfig(
        style: paragraphStyle.copyWith(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor),
      ),
      ListConfig(
        marker: (isOrdered, depth, index) {
          if (!isOrdered) {
            return null;
          }

          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: SelectionContainer.disabled(
                child: Text("${index + 1}.", style: paragraphStyle, textAlign: TextAlign.right),
              ),
            ),
          );
        },
      ),
    ],
  );
}

class _NoDividerH1Config extends HeadingConfig {
  const _NoDividerH1Config({required this.style});

  @override
  final TextStyle style;

  @override
  String get tag => MarkdownTag.h1.name;
}

class _NoDividerH2Config extends HeadingConfig {
  const _NoDividerH2Config({required this.style});

  @override
  final TextStyle style;

  @override
  String get tag => MarkdownTag.h2.name;
}

class _NoDividerH3Config extends HeadingConfig {
  const _NoDividerH3Config({required this.style});

  @override
  final TextStyle style;

  @override
  String get tag => MarkdownTag.h3.name;
}
