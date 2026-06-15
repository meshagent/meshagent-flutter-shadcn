import 'package:flutter/widgets.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';

class MarkdownViewer extends StatelessWidget {
  const MarkdownViewer({
    super.key,
    required this.markdown,
    this.padding = const EdgeInsets.all(20),
    this.selectable = true,
    this.shrinkWrap = true,
    this.threadTypography = false,
    this.color,
    this.baseFontSize,
    this.horizontalRuleColor,
    this.horizontalRuleHeight = 1,
    this.physics,
  });

  final String markdown;
  final EdgeInsetsGeometry? padding;
  final bool selectable;
  final bool shrinkWrap;
  final bool threadTypography;
  final Color? color;
  final double? baseFontSize;
  final Color? horizontalRuleColor;
  final double horizontalRuleHeight;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: MarkdownWidget(
        padding: padding,
        config: buildChatBubbleMarkdownConfig(
          context,
          color: color,
          baseFontSize: baseFontSize,
          threadTypography: threadTypography,
          horizontalRuleColor: horizontalRuleColor,
          horizontalRuleHeight: horizontalRuleHeight,
        ),
        markdownGenerator: _buildMarkdownGenerator(context),
        shrinkWrap: shrinkWrap,
        selectable: selectable,
        physics: physics,
        data: markdown,
      ),
    );
  }
}

MarkdownGenerator _buildMarkdownGenerator(BuildContext context) {
  final inlineCodeHasHorizontalPadding = ThreadTypographyOverride.inlineCodeHorizontalPaddingOf(context);
  final blockquoteBackgroundColor = ThreadTypographyOverride.maybeMarkdownBlockquoteBackgroundColorOf(context);
  final headingTagsWithPadding = [
    MarkdownTag.h1.name,
    MarkdownTag.h2.name,
    MarkdownTag.h3.name,
  ].where((tag) => ThreadTypographyOverride.maybeMarkdownHeadingPaddingOf(context, tag) != null);
  return MarkdownGenerator(
    generators: [
      for (final tag in headingTagsWithPadding)
        SpanNodeGeneratorWithTag(
          tag: tag,
          generator: (element, config, visitor) {
            final padding = ThreadTypographyOverride.maybeMarkdownHeadingPaddingOf(context, tag);
            return _PaddedHeadingNode(
              headingConfig: _headingConfigForTag(config, tag),
              visitor: visitor,
              padding: padding ?? EdgeInsets.zero,
            );
          },
        ),
      if (blockquoteBackgroundColor != null)
        SpanNodeGeneratorWithTag(
          tag: MarkdownTag.blockquote.name,
          generator: (element, config, visitor) =>
              _DecoratedBlockquoteNode(config.blockquote, visitor: visitor, backgroundColor: blockquoteBackgroundColor),
        ),
      SpanNodeGeneratorWithTag(tag: MarkdownTag.table.name, generator: (element, config, visitor) => _MarkdownTableNode()),
      if (inlineCodeHasHorizontalPadding)
        SpanNodeGeneratorWithTag(
          tag: MarkdownTag.code.name,
          generator: (element, config, visitor) => _PaddedInlineCodeNode(element.textContent, config.code),
        ),
    ],
  );
}

HeadingConfig _headingConfigForTag(MarkdownConfig config, String tag) {
  if (tag == MarkdownTag.h1.name) {
    return config.h1;
  }
  if (tag == MarkdownTag.h2.name) {
    return config.h2;
  }
  if (tag == MarkdownTag.h3.name) {
    return config.h3;
  }
  if (tag == MarkdownTag.h4.name) {
    return config.h4;
  }
  if (tag == MarkdownTag.h5.name) {
    return config.h5;
  }
  return config.h6;
}

class _PaddedHeadingNode extends ElementNode {
  _PaddedHeadingNode({required this.headingConfig, required this.visitor, required this.padding});

  final HeadingConfig headingConfig;
  final WidgetVisitor visitor;
  final EdgeInsets padding;

  @override
  InlineSpan build() {
    return WidgetSpan(
      child: Padding(
        padding: padding,
        child: ProxyRichText(childrenSpan, richTextBuilder: visitor.richTextBuilder),
      ),
    );
  }

  @override
  TextStyle get style => headingConfig.style.merge(parentStyle);
}

class _DecoratedBlockquoteNode extends ElementNode {
  _DecoratedBlockquoteNode(this.blockquoteConfig, {required this.visitor, required this.backgroundColor});

  final BlockquoteConfig blockquoteConfig;
  final WidgetVisitor visitor;
  final Color backgroundColor;

  @override
  InlineSpan build() {
    return WidgetSpan(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            left: BorderSide(color: blockquoteConfig.sideColor, width: blockquoteConfig.sideWith),
          ),
          borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
        ),
        margin: blockquoteConfig.margin,
        padding: const EdgeInsets.only(left: 16, right: 14, top: 10, bottom: 10),
        child: ProxyRichText(childrenSpan, richTextBuilder: visitor.richTextBuilder),
      ),
    );
  }

  @override
  TextStyle get style => TextStyle(color: blockquoteConfig.textColor).merge(parentStyle);
}

class _PaddedInlineCodeNode extends ElementNode {
  _PaddedInlineCodeNode(this.text, this.codeConfig);

  static const String _inlinePadding = '\u2009';

  final String text;
  final CodeConfig codeConfig;

  @override
  InlineSpan build() => TextSpan(style: style, text: '$_inlinePadding$text$_inlinePadding');

  @override
  TextStyle get style => codeConfig.style.merge(parentStyle);
}

class _MarkdownTableNode extends ElementNode {
  @override
  InlineSpan build() {
    final columns = <String>[];
    final rows = <List<String>>[];

    for (final child in children) {
      if (child is THeadNode) {
        final headerRows = _extractRows(child);
        if (headerRows.isEmpty) {
          continue;
        }

        if (columns.isEmpty) {
          columns.addAll(headerRows.first);
        }
        if (headerRows.length > 1) {
          rows.addAll(headerRows.skip(1));
        }
      } else if (child is TBodyNode) {
        rows.addAll(_extractRows(child));
      }
    }

    if (columns.isEmpty && rows.isNotEmpty) {
      columns.addAll(rows.removeAt(0));
    }

    if (columns.isEmpty) {
      return const TextSpan(text: '');
    }

    return WidgetSpan(
      child: SelectionContainer.disabled(
        child: CoordinatedSecondaryTapBarrier(
          child: InMemoryTable(
            columns: columns,
            rows: rows,
            autoSizeColumns: true,
            autoSizeRows: true,
            autoSizeVertically: true,
            showLeadingOuterBorders: true,
            showRowHeaders: false,
          ),
        ),
      ),
    );
  }

  List<List<String>> _extractRows(ElementNode section) {
    return [
      for (final row in section.children)
        if (row is TrNode) [for (final cell in row.children) _plainTextFromNode(cell)],
    ];
  }

  String _plainTextFromNode(SpanNode node) {
    if (node is TextNode) {
      return node.text;
    }
    if (node is ElementNode) {
      final buffer = StringBuffer();
      for (final child in node.children) {
        buffer.write(_plainTextFromNode(child));
      }
      return buffer.toString();
    }
    return node.build().toPlainText();
  }
}
