import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';

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
