import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:url_launcher/url_launcher.dart';

const int codePreviewLargeFileThresholdBytes = 1024 * 1024;

bool isCodeFile(String filename) {
  return resolveLanguageIdForFilename(filename) != null;
}

bool _usesSystemAdaptiveTextSelectionToolbar() {
  if (kIsWeb) {
    return false;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    TargetPlatform.fuchsia || TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
  };
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
  _LargeCodeFile? largeFile;
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
      largeFile = null;
      loadError = null;
      saveError = null;
      dirty = false;
      saving = false;
      controller = null;
    });
    widget.controller?._sync(this);

    try {
      final result = await _readPreviewData();
      if (!mounted || generation != _loadGeneration) {
        return;
      }

      setState(() {
        text = result.text;
        largeFile = result.largeFile;
        controller = result.text == null ? null : CodeLineEditingController.fromText(result.text!);
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

  Future<_CodePreviewLoadResult> _readPreviewData() async {
    final inlineText = widget.text;
    if (inlineText != null) {
      return _CodePreviewLoadResult.text(inlineText);
    }

    final room = widget.room;
    if (room != null) {
      final entry = await room.storage.stat(widget.filename);
      final size = entry?.size;
      if (size != null && size > codePreviewLargeFileThresholdBytes) {
        final downloadUrl = await room.storage.downloadUrl(widget.filename);
        return _CodePreviewLoadResult.largeFile(_LargeCodeFile(size: size, downloadUrl: Uri.parse(downloadUrl)));
      }

      final content = await room.storage.download(widget.filename);
      return _CodePreviewLoadResult.text(utf8.decode(content.data, allowMalformed: true));
    }

    final url = widget.url;
    if (url == null) {
      throw StateError("CodePreview requires room, text, or url.");
    }

    final response = await get(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClientException("Failed to load file (${response.statusCode})", url);
    }

    return _CodePreviewLoadResult.text(utf8.decode(response.bodyBytes, allowMalformed: true));
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

  SelectionToolbarController? _selectionToolbarController() {
    if (!_usesSystemAdaptiveTextSelectionToolbar()) {
      return null;
    }

    return MobileSelectionToolbarController(
      builder: ({required context, required anchors, required controller, required onDismiss, required onRefresh}) {
        return _CodePreviewMobileSelectionToolbar(
          anchors: anchors,
          controller: controller,
          readOnly: widget.readOnly,
          onDismiss: onDismiss,
          onRefresh: onRefresh,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = resolveModeForFilename(widget.filename) ?? langPlaintext;
    final showEditorToolbar = !widget.readOnly && widget.showToolbar && largeFile == null;

    return Column(
      children: [
        if (showEditorToolbar)
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
          child: largeFile != null
              ? _LargeCodeFilePreview(filename: widget.filename, file: largeFile!)
              : text == null
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
                      toolbarController: _selectionToolbarController(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CodePreviewLoadResult {
  const _CodePreviewLoadResult._({this.text, this.largeFile});

  factory _CodePreviewLoadResult.text(String text) {
    return _CodePreviewLoadResult._(text: text);
  }

  factory _CodePreviewLoadResult.largeFile(_LargeCodeFile largeFile) {
    return _CodePreviewLoadResult._(largeFile: largeFile);
  }

  final String? text;
  final _LargeCodeFile? largeFile;
}

class _LargeCodeFile {
  const _LargeCodeFile({required this.size, required this.downloadUrl});

  final int size;
  final Uri downloadUrl;
}

class _LargeCodeFilePreview extends StatelessWidget {
  const _LargeCodeFilePreview({required this.filename, required this.file});

  final String filename;
  final _LargeCodeFile file;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ColoredBox(
      color: theme.colorScheme.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.fileCode, size: 40, color: theme.colorScheme.mutedForeground),
                const SizedBox(height: 16),
                Text(
                  filename.split("/").last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.h4,
                ),
                const SizedBox(height: 8),
                Text(
                  "This file is ${_formatBytes(file.size)}, which is too large to preview.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.muted,
                ),
                const SizedBox(height: 18),
                ShadButton.secondary(
                  leading: const Icon(LucideIcons.download),
                  onPressed: () async {
                    await launchUrl(file.downloadUrl);
                  },
                  child: const Text("Download"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  if (unitIndex == 0) {
    return "$bytes ${units[unitIndex]}";
  }

  return "${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}";
}

class _CodePreviewMobileSelectionToolbar extends StatefulWidget {
  const _CodePreviewMobileSelectionToolbar({
    required this.anchors,
    required this.controller,
    required this.readOnly,
    required this.onDismiss,
    required this.onRefresh,
  });

  final TextSelectionToolbarAnchors anchors;
  final CodeLineEditingController controller;
  final bool readOnly;
  final VoidCallback onDismiss;
  final VoidCallback onRefresh;

  @override
  State<_CodePreviewMobileSelectionToolbar> createState() => _CodePreviewMobileSelectionToolbarState();
}

class _CodePreviewMobileSelectionToolbarState extends State<_CodePreviewMobileSelectionToolbar> {
  bool _clipboardChecked = false;
  bool _hasClipboardText = false;

  @override
  void initState() {
    super.initState();
    _refreshClipboard();
  }

  @override
  void didUpdateWidget(covariant _CodePreviewMobileSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller || oldWidget.readOnly != widget.readOnly) {
      _refreshClipboard();
    }
  }

  Future<void> _refreshClipboard() async {
    if (widget.readOnly) {
      if (!mounted) {
        return;
      }

      setState(() {
        _clipboardChecked = true;
        _hasClipboardText = false;
      });
      return;
    }

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }

    setState(() {
      _clipboardChecked = true;
      _hasClipboardText = (clipboardData?.text?.trim().isNotEmpty ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.controller.selection;
    final hasSelection = !selection.isCollapsed;
    final hasContent = widget.controller.text.isNotEmpty;

    if (!_clipboardChecked) {
      return const SizedBox.shrink();
    }

    final buttonItems = <ContextMenuButtonItem>[
      if (!widget.readOnly && hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            widget.controller.cut();
            widget.onDismiss();
          },
        ),
      if (hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            unawaited(widget.controller.copy());
            widget.onDismiss();
          },
        ),
      if (!widget.readOnly && _hasClipboardText)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            widget.controller.paste();
            widget.onDismiss();
          },
        ),
      if (hasContent)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () {
            widget.controller.selectAll();
            widget.onRefresh();
          },
        ),
    ];

    if (buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(anchors: widget.anchors, buttonItems: buttonItems);
  }
}
