import 'package:flutter/material.dart';
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
  final languageId = resolveLanguageIdForFilename(language) ?? plaintextLanguageId;
  final lines = code.split(RegExp(r"\r?\n"));
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  final normalizedCode = lines.join("\n");

  if (languageId == "diff") {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: const BorderRadius.all(Radius.circular(8.0))),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
      ),
    );
  }

  final span = highlightCodeSpanWithReHighlight(context: context, code: normalizedCode, languageOrFilename: language, textStyle: textStyle);

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8.0),
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(color: backgroundColor, borderRadius: const BorderRadius.all(Radius.circular(8.0))),
    width: double.infinity,
    child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SelectableText.rich(span)),
  );
}

MarkdownConfig buildChatBubbleMarkdownConfig(
  BuildContext context, {
  Color? color,
  double? baseFontSize,
  Color? horizontalRuleColor,
  double horizontalRuleHeight = 1,
}) {
  final theme = ShadTheme.of(context);
  final mdColor = color ?? chatBubbleMarkdownColor(context);
  final resolvedBaseFontSize = baseFontSize ?? chatBubbleMarkdownBaseFontSize(context);
  final codeTextStyle = GoogleFonts.sourceCodePro(fontSize: resolvedBaseFontSize * 1.0, color: mdColor);

  return MarkdownConfig(
    configs: [
      HrConfig(color: horizontalRuleColor ?? mdColor.withAlpha(100), height: horizontalRuleHeight),
      _NoDividerH1Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold),
      ),
      _NoDividerH2Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 1.8, color: mdColor, inherit: false),
      ),
      H3Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 1.6, color: mdColor, inherit: false),
      ),
      H4Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 1.4, color: mdColor, inherit: false),
      ),
      H5Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 1.2, color: mdColor, inherit: false),
      ),
      H6Config(
        style: TextStyle(fontSize: resolvedBaseFontSize * 1.0, color: mdColor, inherit: false),
      ),
      PreConfig(
        decoration: BoxDecoration(color: theme.cardTheme.backgroundColor),
        textStyle: TextStyle(fontSize: resolvedBaseFontSize * 1.0, color: mdColor, inherit: false, fontFamily: 'SourceCodePro'),
        builder: (code, language) => _buildHighlightedCodeBlock(
          context: context,
          code: code,
          language: language,
          textStyle: codeTextStyle,
          backgroundColor: theme.cardTheme.backgroundColor,
        ),
      ),
      PConfig(
        textStyle: TextStyle(fontSize: resolvedBaseFontSize * 1.0, color: mdColor, inherit: false),
      ),
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
