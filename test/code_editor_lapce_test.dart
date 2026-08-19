import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lapce_editor_flutter/lapce_editor_flutter.dart' as lapce;
import 'package:meshagent_flutter_shadcn/code_editor.dart';
import 'package:re_highlight/languages/json.dart';

void main() {
  setUpAll(initializeCodeEditorForTesting);

  testWidgets('shared code editor is backed by Lapce', (tester) async {
    final controller = CodeLineEditingController.fromText('{"ready": false}');
    addTearDown(controller.dispose);
    String? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: CodeEditor(
              controller: controller,
              onChanged: (value) => changed = value,
              style: CodeEditorStyle(
                codeTheme: CodeHighlightTheme(
                  languages: {'default': CodeHighlightThemeMode(mode: langJson)},
                  theme: const {
                    'root': TextStyle(color: Colors.black),
                    'string': TextStyle(color: Colors.green),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(lapce.LapceEditor), findsOneWidget);

    controller.text = '{"ready": true}';
    await tester.pump();

    expect(changed, '{"ready": true}');
    expect(controller.text, '{"ready": true}');
  });

  test('selection adapter preserves direction and clamps offsets', () {
    final controller = CodeLineEditingController.fromText('abcdef');
    addTearDown(controller.dispose);

    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 2);
    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 2);

    controller.selection = const TextSelection(baseOffset: -1, extentOffset: 20);
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 6);
  });
}
