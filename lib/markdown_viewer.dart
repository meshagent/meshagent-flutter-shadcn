import 'package:flutter/widgets.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';

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
        markdownGenerator: _buildMarkdownGenerator(),
        shrinkWrap: shrinkWrap,
        selectable: selectable,
        physics: physics,
        data: markdown,
      ),
    );
  }
}

MarkdownGenerator _buildMarkdownGenerator() {
  return MarkdownGenerator(
    generators: [SpanNodeGeneratorWithTag(tag: MarkdownTag.table.name, generator: (element, config, visitor) => _MarkdownTableNode())],
  );
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
      child: InMemoryTable(
        columns: columns,
        rows: rows,
        autoSizeColumns: true,
        autoSizeRows: true,
        autoSizeVertically: true,
        showLeadingOuterBorders: true,
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
