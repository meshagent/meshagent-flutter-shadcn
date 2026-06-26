import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/base16/material-darker.dart';
import 'package:re_highlight/styles/base16/material-lighter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../src/code_editor/code_editor.dart';
import '../src/code_editor/code_editor_types.dart';

class JsonMetadataEditingController extends CodeLineEditingController {
  JsonMetadataEditingController({Map<String, dynamic> value = const <String, dynamic>{}})
    : super(codeLines: CodeLines.fromText(prettyJson(value)));

  Map<String, dynamic> parse({String label = 'Metadata'}) {
    return parseJsonObject(text, label: label);
  }
}

class JsonMetadataEditor extends StatelessWidget {
  const JsonMetadataEditor({super.key, required this.controller, this.minHeight = 120, this.maxHeight = 220});

  final JsonMetadataEditingController controller;
  final double minHeight;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final editorColors = _editorColors(context);
    final editorTheme = _sourceCodeEditorTheme(context, editorColors);
    final height = maxHeight < minHeight ? minHeight : maxHeight;
    return SizedBox(
      height: height,
      child: ShadDecorator(
        decoration: theme.inputTheme.decoration ?? const ShadDecoration(),
        child: ClipRRect(
          borderRadius: theme.radius,
          child: CodeEditor(
            controller: controller,
            wordWrap: true,
            padding: const EdgeInsets.all(8),
            style: CodeEditorStyle(
              backgroundColor: editorColors.background,
              cursorColor: theme.colorScheme.selection,
              fontSize: 14,
              fontFamily: 'SourceCodePro',
              textColor: editorColors.foreground,
              codeTheme: CodeHighlightTheme(
                languages: {'default': CodeHighlightThemeMode(mode: langJson)},
                theme: editorTheme,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnnotationsField extends StatelessWidget {
  const AnnotationsField({super.key, this.label = 'Annotations', required this.value, required this.onChanged});

  final String label;
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(label, style: ShadTheme.of(context).textTheme.small),
        AnnotationsEditor(value: value, onChanged: onChanged),
      ],
    );
  }
}

class AnnotationsEditor extends StatefulWidget {
  const AnnotationsEditor({super.key, required this.value, required this.onChanged});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  State<AnnotationsEditor> createState() => _AnnotationsEditorState();
}

class _AnnotationsEditorState extends State<AnnotationsEditor> {
  final List<_AnnotationRowController> _rows = [];

  @override
  void initState() {
    super.initState();
    _setRows(widget.value);
  }

  @override
  void didUpdateWidget(covariant AnnotationsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(_rowsValue(), _stringAnnotations(widget.value)) && !mapEquals(oldWidget.value, widget.value)) {
      _setRows(widget.value);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _setRows(Map<String, dynamic> value) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        value.entries
            .map((entry) => _AnnotationRowController(keyText: entry.key, valueText: _annotationValueToString(entry.value)))
            .toList(growable: false),
      );
    if (_rows.isEmpty) {
      _rows.add(_AnnotationRowController());
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(_AnnotationRowController());
    });
    _emit();
  }

  void _removeRow(int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }
    setState(() {
      final row = _rows.removeAt(index);
      row.dispose();
      if (_rows.isEmpty) {
        _rows.add(_AnnotationRowController());
      }
    });
    _emit();
  }

  void _emit() {
    final next = _rowsValue();
    widget.onChanged(next);
  }

  Map<String, String> _rowsValue() {
    final next = <String, String>{};
    for (final row in _rows) {
      final key = row.keyController.text.trim();
      if (key.isEmpty) {
        continue;
      }
      next[key] = row.valueController.text;
    }
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Key', style: theme.textTheme.muted)),
            const SizedBox(width: 8),
            Expanded(child: Text('Value', style: theme.textTheme.muted)),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < _rows.length; index++) ...[
          _AnnotationRow(index: index, row: _rows[index], onChanged: _emit, onRemove: _rows.length == 1 ? null : () => _removeRow(index)),
          if (index != _rows.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            key: const Key('add-annotation-row'),
            size: ShadButtonSize.sm,
            onPressed: _addRow,
            leading: const Icon(LucideIcons.plus),
            child: const Text('Add annotation'),
          ),
        ),
      ],
    );
  }
}

class _AnnotationRow extends StatelessWidget {
  const _AnnotationRow({required this.index, required this.row, required this.onChanged, required this.onRemove});

  final int index;
  final _AnnotationRowController row;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ShadInput(
            key: Key('annotation-key-$index'),
            controller: row.keyController,
            placeholder: const Text('meshagent.io/secret.provider'),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShadInput(
            key: Key('annotation-value-$index'),
            controller: row.valueController,
            placeholder: const Text('value'),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        ShadButton.ghost(
          key: Key('remove-annotation-row-$index'),
          size: ShadButtonSize.sm,
          onPressed: onRemove,
          child: const Icon(LucideIcons.trash2),
        ),
      ],
    );
  }
}

class _AnnotationRowController {
  _AnnotationRowController({String keyText = '', String valueText = ''})
    : keyController = TextEditingController(text: keyText),
      valueController = TextEditingController(text: valueText);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

Map<String, String> _stringAnnotations(Map<String, dynamic> value) {
  return {for (final entry in value.entries) entry.key: _annotationValueToString(entry.value)};
}

String prettyJson(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return '{}';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

Map<String, TextStyle> _sourceCodeEditorTheme(BuildContext context, ({Color background, Color foreground}) colors) {
  final baseTheme = _isDarkEditorTheme(context) ? materialDarkerTheme : materialLighterTheme;
  return {
    ...baseTheme,
    'root': (baseTheme['root'] ?? const TextStyle()).copyWith(color: colors.foreground, backgroundColor: colors.background),
  };
}

bool _isDarkEditorTheme(BuildContext context) {
  final shadTheme = ShadTheme.of(context);
  return shadTheme.colorScheme.background.computeLuminance() < 0.5 ||
      shadTheme.brightness == Brightness.dark ||
      Theme.of(context).brightness == Brightness.dark;
}

({Color background, Color foreground}) _editorColors(BuildContext context) {
  final colorScheme = ShadTheme.of(context).colorScheme;
  final isDark = _isDarkEditorTheme(context);
  return (background: isDark ? colorScheme.background : colorScheme.popover, foreground: colorScheme.foreground);
}

Map<String, dynamic> parseJsonObject(String value, {String label = 'Metadata'}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(trimmed);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  throw FormatException('$label must be a JSON object.');
}

String _annotationValueToString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return jsonEncode(value);
}
