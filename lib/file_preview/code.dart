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

class CodePreviewController extends ChangeNotifier {
  _CodePreview? _state;
  bool _dirty = false;
  bool _saving = false;
  Object? _saveError;
  bool _notifyScheduled = false;
  bool _disposed = false;
  int _notifyGeneration = 0;

  bool get dirty => _dirty;
  bool get saving => _saving;
  Object? get saveError => _saveError;
  bool get canSave => !_saving && _dirty;

  Future<void> save() async {
    await _state?._save();
  }

  void _attach(_CodePreview state) {
    _state = state;
    _sync(state);
  }

  void _detach(_CodePreview state) {
    if (_state != state) {
      return;
    }
    _state = null;
    _dirty = false;
    _saving = false;
    _saveError = null;
    _invalidatePendingNotifications();
    _notifyListenersSafely();
  }

  void _sync(_CodePreview state) {
    if (_state != state) {
      return;
    }

    final changed = _dirty != state.dirty || _saving != state.saving || _saveError != state.saveError;
    _dirty = state.dirty;
    _saving = state.saving;
    _saveError = state.saveError;
    if (changed) {
      _notifyListenersSafely();
    }
  }

  void _notifyListenersSafely() {
    if (_disposed) {
      return;
    }

    if (_notifyScheduled) {
      return;
    }

    _notifyScheduled = true;
    final generation = _notifyGeneration;
    Future<void>.delayed(Duration.zero, () {
      if (_disposed || !_notifyScheduled || generation != _notifyGeneration) {
        return;
      }
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void _invalidatePendingNotifications() {
    _notifyScheduled = false;
    _notifyGeneration++;
  }

  @override
  void dispose() {
    _disposed = true;
    _state = null;
    _invalidatePendingNotifications();
    super.dispose();
  }
}

class CodePreview extends StatefulWidget {
  const CodePreview({
    super.key,
    this.room,
    required this.filename,
    this.url,
    this.text,
    this.readOnly = false,
    this.showToolbar = true,
    this.controller,
  });

  final RoomClient? room;
  final String filename;
  final Uri? url;
  final String? text;
  final bool readOnly;
  final bool showToolbar;
  final CodePreviewController? controller;

  @override
  State createState() => _CodePreview();
}

class _CodePreview extends State<CodePreview> {
  final theme = monokaiSublimeTheme;
  String? text;
  Object? loadError;
  Object? saveError;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _load();
  }

  void codeChanged() {
    setState(() {
      dirty = true;
    });
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
    focusNode.dispose();
  }

  @override
  void didUpdateWidget(covariant CodePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldReload =
        oldWidget.filename != widget.filename ||
        oldWidget.url != widget.url ||
        oldWidget.text != widget.text ||
        oldWidget.room != widget.room;

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }

    if (shouldReload) {
      _load();
    } else {
      widget.controller?._sync(this);
    }
  }

  late final focusNode = FocusNode(
    // TODO: editor replaces this handler, need to update editor to fix
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.save) {
        if (!saving && dirty) {
          unawaited(_save());
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
  );
  var dirty = false;
  var saving = false;
  int _loadGeneration = 0;

  Future<void> _load() async {
    final generation = ++_loadGeneration;

    setState(() {
      text = null;
      loadError = null;
      saveError = null;
      dirty = false;
      saving = false;
      controller = null;
    });
    widget.controller?._sync(this);

    try {
      final nextText = await _readText();
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        text = nextText;
        controller = CodeLineEditingController.fromText(nextText);
      });
      widget.controller?._sync(this);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        loadError = error;
      });
      widget.controller?._sync(this);
    }
  }

  Future<String> _readText() async {
    final inlineText = widget.text;
    if (inlineText != null) {
      return inlineText;
    }

    final room = widget.room;
    if (room != null) {
      final content = await room.storage.download(widget.filename);
      return utf8.decode(content.data, allowMalformed: true);
    }

    final url = widget.url;
    if (url == null) {
      throw StateError("CodePreview requires room, text, or url.");
    }

    final response = await get(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClientException("Failed to load file (${response.statusCode})", url);
    }

    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<void> _save() async {
    final room = widget.room;
    final currentController = controller;
    if (room == null || currentController == null || saving) {
      return;
    }

    setState(() {
      saving = true;
      saveError = null;
    });
    widget.controller?._sync(this);

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
      widget.controller?._sync(this);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saveError = error;
      });
      widget.controller?._sync(this);

      ShadToaster.of(context).show(ShadToast.destructive(title: const Text("Save failed"), description: Text('$error')));
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
        widget.controller?._sync(this);
      }
    }
  }

  CodeLineEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final mode = resolveModeForFilename(widget.filename) ?? langPlaintext;

    return Column(
      children: [
        if (!widget.readOnly && widget.showToolbar)
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
                (dirty || saving ? ShadButton.destructive : ShadButton.secondary)(
                  enabled: !saving && dirty,
                  onPressed: () async {
                    await _save();
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
              ? loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            "Unable to load file: $loadError",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive),
                          ),
                        ),
                      )
                    : Center(child: CircularProgressIndicator())
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
                        widget.controller?._sync(this);
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
