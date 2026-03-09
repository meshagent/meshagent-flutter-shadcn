import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:re_highlight/languages/plaintext.dart';

bool isCodeFile(String filename) {
  return resolveModeForFilename(filename) != null;
}

class CodePreview extends StatefulWidget {
  const CodePreview({super.key, this.room, required this.filename, this.url, this.text, this.readOnly = false});

  final RoomClient? room;
  final String filename;
  final Uri? url;
  final String? text;
  final bool readOnly;

  @override
  State createState() => _CodePreview();
}

class _CodePreview extends State<CodePreview> {
  final theme = monokaiSublimeTheme;
  String? text;
  Object? saveError;

  @override
  void initState() {
    super.initState();

    if (widget.url != null) {
      get(widget.url!).then((response) {
        if (!mounted) return;

        setState(() {
          text = utf8.decode(response.bodyBytes);
          controller = CodeLineEditingController.fromText(text);
        });
      });
    } else {
      setState(() {
        text = widget.text!;
        controller = CodeLineEditingController.fromText(text);
      });
    }
  }

  void codeChanged() {
    setState(() {
      dirty = true;
    });
  }

  @override
  void dispose() {
    super.dispose();
    focusNode.dispose();
  }

  late final focusNode = FocusNode(
    // TODO: editor replaces this handler, need to update editor to fix
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.save) {
        if (!saving && dirty) {
          unawaited(save());
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
  );
  var dirty = false;
  var saving = false;

  Future<void> save() async {
    final room = widget.room;
    final currentController = controller;
    if (room == null || currentController == null || saving) {
      return;
    }

    setState(() {
      saving = true;
      saveError = null;
    });

    final nextText = currentController.text;
    try {
      final bytes = Uint8List.fromList(utf8.encode(nextText));
      await room.storage.uploadStream(widget.filename, Stream.value(bytes), overwrite: true, size: bytes.length);
      if (!mounted) {
        return;
      }
      setState(() {
        dirty = false;
        text = nextText;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saveError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  CodeLineEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final mode = resolveModeForFilename(widget.filename) ?? langPlaintext;

    return Column(
      children: [
        if (!widget.readOnly)
          Container(
            decoration: BoxDecoration(
              color: ShadTheme.of(context).colorScheme.background,
              border: Border(bottom: BorderSide(color: ShadTheme.of(context).colorScheme.border)),
            ),
            padding: EdgeInsets.all(10),
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ShadButton.secondary(
                  enabled: !saving && dirty,
                  onPressed: () async {
                    await save();
                  },
                  leading: saving ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : Icon(LucideIcons.save),
                  child: Text("Save"),
                ),
                if (saveError != null) ...[
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Save failed: $saveError",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: text == null
              ? Center(child: CircularProgressIndicator())
              : Container(
                  padding: EdgeInsets.only(right: 10),
                  color: theme["root"]!.backgroundColor!,
                  child: Builder(
                    builder: (context) => CodeEditor(
                      onChanged: (value) {
                        if (dirty) {
                          return;
                        }
                        if (text == controller!.text) return;

                        text = controller!.text;
                        setState(() {
                          dirty = true;
                        });
                      },
                      showCursorWhenReadOnly: false,

                      readOnly: widget.readOnly,
                      padding: EdgeInsets.only(left: 20, top: 20),
                      style: CodeEditorStyle(
                        cursorColor: ShadTheme.of(context).colorScheme.selection,
                        fontSize: 16,
                        fontFamily: "SourceCodePro",
                        textColor: theme["root"]?.color,
                        codeTheme: CodeHighlightTheme(
                          languages: {'default': CodeHighlightThemeMode(mode: mode)},
                          theme: theme,
                        ),
                      ),
                      focusNode: focusNode,
                      controller: controller,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
