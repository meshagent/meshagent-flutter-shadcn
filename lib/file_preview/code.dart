import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:path/path.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:re_highlight/languages/plaintext.dart';

const highlightIdByKey = <String, String>{
  // special filenames
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'cmakelists.txt': 'cmake',
  'nginx.conf': 'nginx',
  'apache.conf': 'apache',
  'httpd.conf': 'apache',
  'rakefile': 'ruby',
  'gemfile': 'ruby',
  'gradlew': 'bash',
  '.bashrc': 'bash',
  '.zshrc': 'bash',
  '.profile': 'bash',
  'gradlew.bat': 'dos',
  'readme': 'markdown',
  'license': 'plaintext',
  'changelog': 'plaintext',
  '.env': 'plaintext',
  '.gitignore': 'plaintext',
  '.dockerignore': 'plaintext',
  '.gitattributes': 'plaintext',
  '.gitmodules': 'plaintext',
  '.npmrc': 'plaintext',
  '.editorconfig': 'plaintext',

  // common extensions that differ from ids
  'py': 'python',
  'rs': 'rust',
  'cs': 'csharp',
  'js': 'javascript',
  'jsx': 'javascript',
  'tsx': 'typescript',
  'ts': 'typescript',
  'yml': 'yaml',
  'html': 'xml',
  'sh': 'bash',
  'zsh': 'bash',
  'ksh': 'bash',
  'ps1': 'powershell',
  'bat': 'dos',
  'cmd': 'dos',
  'rb': 'ruby',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'erl': 'erlang',
  'ex': 'elixir',
  'exs': 'elixir',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'hh': 'cpp',
  'h': 'cpp',
  'jsonl': 'json',
  'ndjson': 'json',
  'md': 'markdown',
  'txt': 'plaintext',
  'log': 'plaintext',
  'env': 'plaintext',
  'conf': 'plaintext',

  // extensions that are ids already can be omitted
  // e.g. 'json', 'xml', 'dart', 'css', 'go', ...
};

bool isCodeFile(String filename) {
  return resolveModeForFilename(filename) != null;
}

Mode? resolveModeForFilename(String filename) {
  final base = basename(filename).toLowerCase();

  final byNameId = highlightIdByKey[base] ?? base;
  final byNameMode = builtinAllLanguages[byNameId];
  if (byNameMode != null) return byNameMode;

  if (base.startsWith('.env.')) return langPlaintext;
  if (base.startsWith('dockerfile.')) return builtinAllLanguages['dockerfile'];

  final ext = extension(base).replaceFirst('.', '');
  if (ext.isEmpty) return null;

  final id = highlightIdByKey[ext] ?? ext;
  return builtinAllLanguages[id];
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
        if (!saving) {
          save();
        }
      }
      return KeyEventResult.ignored;
    },
  );
  var dirty = false;
  var saving = false;

  void save() async {
    setState(() {
      saving = true;
    });
    try {
      final handle = await widget.room!.storage.open(widget.filename, overwrite: true);
      final bytes = utf8.encode(controller!.text);
      await widget.room!.storage.write(handle, bytes);
      await widget.room!.storage.close(handle);
    } finally {
      setState(() {
        saving = false;
        dirty = false;
      });
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
                    save();
                  },
                  leading: saving ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : Icon(LucideIcons.save),
                  child: Text("Save"),
                ),
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
