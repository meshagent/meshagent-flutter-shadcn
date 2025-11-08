import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

  void load() async {
    final content = await widget.room.storage.download(widget.filename);
    if (!mounted) {
      return;
    }

    setState(() {
      markdown = utf8.decode(content.data);
    });
  }

  String? markdown;

  @override
  Widget build(BuildContext context) {
    final mdColor =
        ShadTheme.of(context).textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: MarkdownWidget(
        padding: const EdgeInsets.all(20),
        config: MarkdownConfig(
          configs: [
            HrConfig(color: mdColor),
            H1Config(style: TextStyle(fontSize: baseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold)),
            H2Config(style: TextStyle(fontSize: baseFontSize * 1.8, color: mdColor, inherit: false)),
            H3Config(style: TextStyle(fontSize: baseFontSize * 1.6, color: mdColor, inherit: false)),
            H4Config(style: TextStyle(fontSize: baseFontSize * 1.4, color: mdColor, inherit: false)),
            H5Config(style: TextStyle(fontSize: baseFontSize * 1.2, color: mdColor, inherit: false)),
            H6Config(style: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false)),
            PreConfig(
              decoration: BoxDecoration(color: ShadTheme.of(context).cardTheme.backgroundColor),
              textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
            ),
            PConfig(textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false)),
            CodeConfig(style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor)),
            BlockquoteConfig(textColor: mdColor),
            LinkConfig(
              style: TextStyle(color: ShadTheme.of(context).linkButtonTheme.foregroundColor, decoration: TextDecoration.underline),
            ),
            ListConfig(
              marker: (isOrdered, depth, index) {
                return Padding(padding: EdgeInsets.only(right: 5), child: Text("${index + 1}.", textAlign: TextAlign.right));
              },
            ),
          ],
        ),
        shrinkWrap: true,
        selectable: true,
        data: markdown ?? "",
      ),
    );
  }
}
