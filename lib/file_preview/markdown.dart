import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';

class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({super.key, required this.filename, required this.room});

  final RoomClient room;

  final String filename;

  @override
  State createState() => _MarkdownPreview();
}

class _MarkdownPreview extends State<MarkdownPreview> {
  @override
  void initState() {
    super.initState();

    load();
  }

  String? markdown;

  void load() async {
    final content = await widget.room.storage.download(widget.filename);
    if (!mounted) {
      return;
    }

    setState(() {
      markdown = utf8.decode(content.data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownViewer(markdown: markdown ?? "");
  }
}

class MarkdownViewer extends StatelessWidget {
  const MarkdownViewer({required this.markdown, super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: MarkdownWidget(
        padding: const EdgeInsets.all(20),
        config: buildChatBubbleMarkdownConfig(context),
        shrinkWrap: true,
        selectable: true,
        data: markdown,
      ),
    );
  }
}
