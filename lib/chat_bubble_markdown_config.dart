import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github.dart';
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

double chatBubbleMarkdownBaseFontSize(BuildContext context) {
  final defaultFontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
  return MediaQuery.of(context).textScaler.scale(defaultFontSize);
}

Map<String, TextStyle> _codeTheme(BuildContext context) {
  final background = ShadTheme.of(context).colorScheme.background;
  return background.computeLuminance() < 0.5 ? monokaiSublimeTheme : githubTheme;
}

Color? diffLineBackgroundColor(String line) {
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
  final resolvedBackgroundColor = backgroundColor ?? theme.cardTheme.backgroundColor;
  final headerTextStyle = GoogleFonts.sourceCodePro(fontSize: 11, color: theme.colorScheme.mutedForeground);
  final body = languageId == "diff"
      ? SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines.indexed)
                Padding(
                  padding: EdgeInsets.only(bottom: line.$1 < lines.length - 1 ? 2 : 0),
                  child: Container(
                    decoration: BoxDecoration(color: diffLineBackgroundColor(line.$2), borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: SelectableText.rich(
                      highlightCodeSpanWithReHighlight(
                        context: context,
                        code: line.$2,
                        languageOrFilename: "diff",
                        textStyle: textStyle.copyWith(color: const Color(0xFFE5E7EB)),
                        theme: monokaiSublimeTheme,
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
          child: SelectableText.rich(
            highlightCodeSpanWithReHighlight(context: context, code: normalizedCode, languageOrFilename: language, textStyle: textStyle),
          ),
        );

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8.0),
    decoration: BoxDecoration(color: resolvedBackgroundColor, borderRadius: const BorderRadius.all(Radius.circular(8.0))),
    clipBehavior: Clip.antiAlias,
    width: double.infinity,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
          decoration: BoxDecoration(color: theme.colorScheme.background.withAlpha(150)),
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
                width: 24,
                height: 24,
                iconSize: 14,
                icon: const Icon(LucideIcons.copy, size: 14),
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
  final resolvedBaseFontSize = baseFontSize ?? chatBubbleMarkdownBaseFontSize(context);
  final codeTextStyle = GoogleFonts.sourceCodePro(
    fontSize: threadTypography ? (resolvedBaseFontSize * 0.95).clamp(12.0, 16.0).toDouble() : resolvedBaseFontSize,
    color: mdColor,
  );
  final paragraphStyle = TextStyle(fontSize: resolvedBaseFontSize, color: mdColor, inherit: false, height: threadTypography ? 1.45 : null);

  final headingBase = TextStyle(
    color: mdColor,
    inherit: false,
    height: threadTypography ? 1.25 : null,
    fontWeight: threadTypography ? FontWeight.w600 : null,
  );
  final h1Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.55).clamp(20.0, 30.0).toDouble(), height: 1.2, fontWeight: FontWeight.w700)
      : TextStyle(fontSize: resolvedBaseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold);
  final h2Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.35).clamp(18.0, 26.0).toDouble())
      : TextStyle(fontSize: resolvedBaseFontSize * 1.8, color: mdColor, inherit: false);
  final h3Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.2).clamp(16.0, 22.0).toDouble())
      : TextStyle(fontSize: resolvedBaseFontSize * 1.6, color: mdColor, inherit: false);
  final h4Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 1.1).clamp(15.0, 20.0).toDouble())
      : TextStyle(fontSize: resolvedBaseFontSize * 1.4, color: mdColor, inherit: false);
  final h5Style = threadTypography
      ? headingBase.copyWith(fontSize: resolvedBaseFontSize.clamp(14.0, 18.0).toDouble())
      : TextStyle(fontSize: resolvedBaseFontSize * 1.2, color: mdColor, inherit: false);
  final h6Style = threadTypography
      ? headingBase.copyWith(fontSize: (resolvedBaseFontSize * 0.95).clamp(13.0, 16.0).toDouble(), fontWeight: FontWeight.w500)
      : TextStyle(fontSize: resolvedBaseFontSize * 1.0, color: mdColor, inherit: false);
  final preStyle = TextStyle(
    fontSize: codeTextStyle.fontSize,
    color: mdColor,
    inherit: false,
    fontFamily: 'SourceCodePro',
    height: threadTypography ? 1.45 : null,
  );

  return MarkdownConfig(
    configs: [
      HrConfig(color: horizontalRuleColor ?? mdColor.withAlpha(100), height: horizontalRuleHeight),
      _NoDividerH1Config(style: h1Style),
      _NoDividerH2Config(style: h2Style),
      H3Config(style: h3Style),
      H4Config(style: h4Style),
      H5Config(style: h5Style),
      H6Config(style: h6Style),
      PreConfig(
        decoration: BoxDecoration(color: theme.cardTheme.backgroundColor),
        textStyle: preStyle,
        builder: (code, language) => _buildHighlightedCodeBlock(
          context: context,
          code: code,
          language: language,
          textStyle: codeTextStyle,
          backgroundColor: theme.cardTheme.backgroundColor,
        ),
      ),
      PConfig(textStyle: paragraphStyle),
      CodeConfig(style: codeTextStyle),
      BlockquoteConfig(textColor: mdColor),
      LinkConfig(
        style: TextStyle(color: theme.linkButtonTheme.foregroundColor, decoration: TextDecoration.underline),
      ),
      ListConfig(
        marker: (isOrdered, depth, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text("${index + 1}.", textAlign: TextAlign.right),
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
