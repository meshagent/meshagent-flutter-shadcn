import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/tool_call_summary.dart';

void main() {
  test('parseToolCommand supports cd then cat', () {
    expect(parseToolCommand('cd foo && cat foo.txt'), [
      const ParsedCommand(kind: 'read', cmd: 'cat foo.txt', name: 'foo.txt', path: 'foo/foo.txt'),
    ]);
  });

  test('formatToolCallSummary renders explored lines', () {
    final summary = formatToolCallSummary(toolkit: '', tool: 'shell', arguments: {'command': 'cat a.py && cat b.py && rg TODO src'});

    expect(summary, 'Explored\n  └ Read a.py, b.py\n    Search TODO in src');
  });

  test('formatToolCallSummary supports openai shell action command', () {
    final summary = formatToolCallSummary(
      toolkit: 'openai',
      tool: 'shell',
      arguments: {
        'action': {
          'command': ['cat', 'a.py'],
        },
      },
    );

    expect(summary, 'Explored\n  └ Read a.py');
  });

  test('formatToolCallSummary keeps unknown as ran', () {
    final summary = formatToolCallSummary(toolkit: '', tool: 'shell', arguments: {'command': 'pytest tests'});

    expect(summary, 'Ran pytest tests');
  });

  test('formatToolCallSummary uses built-in friendly items', () {
    expect(
      formatToolCallSummary(toolkit: 'storage', tool: 'read_file', arguments: {'path': '/src/report.html'}),
      'Read file: /src/report.html',
    );
    expect(
      formatToolCallSummary(toolkit: 'dataset', tool: 'execute_sql', arguments: {'query': 'SELECT *\nFROM food'}),
      'Ran SQL: SELECT * FROM food',
    );
    expect(
      formatToolCallSummary(toolkit: 'datetime', tool: 'now', arguments: {'tz': 'America/Los_Angeles'}),
      'Checked current time: America/Los_Angeles',
    );
    expect(
      formatToolCallSummary(toolkit: 'web_fetch', tool: 'web_fetch', arguments: {'url': 'https://example.com'}),
      'Fetched URL: https://example.com',
    );
    expect(formatToolCallSummary(toolkit: 'container', tool: 'start_container', arguments: {'image': 'python:3.13'}), 'Started container');
    expect(
      formatToolCallSummary(toolkit: 'chat', tool: 'attach_file', arguments: {'path': '/src/report.html'}),
      'Attached file: /src/report.html',
    );
    expect(
      formatToolCallSummary(toolkit: 'mail', tool: 'new_email_thread', arguments: {'subject': 'Food report'}),
      'Started email thread: Food report',
    );
  });

  test('formatToolCallSummary uses in-progress wording before completion', () {
    expect(formatToolCallSummary(toolkit: 'storage', tool: 'write_file', arguments: null, completed: false), 'Writing file');
    expect(
      formatToolCallSummary(toolkit: 'storage', tool: 'write_file', arguments: {'path': '/src/report.html'}, completed: false),
      'Writing file: /src/report.html',
    );
    expect(formatToolCallSummary(toolkit: '', tool: 'shell', arguments: null, completed: false), 'Running shell');
    expect(formatToolCallSummary(toolkit: 'openai', tool: 'shell', arguments: null, completed: false), 'Running commands');
    expect(formatToolCallSummary(toolkit: '', tool: 'shell', arguments: null, completed: false, pending: true), 'Preparing shell');
    expect(formatToolCallSummary(toolkit: 'openai', tool: 'shell', arguments: null, completed: false, pending: true), 'Preparing commands');
    expect(
      formatToolCallSummary(
        toolkit: 'storage',
        tool: 'write_file',
        arguments: {'path': '/src/report.html'},
        completed: false,
        pending: true,
      ),
      'Preparing to write file: /src/report.html',
    );
  });

  test('formatToolCallSummary shows streamed argument size after threshold', () {
    expect(
      formatToolCallSummary(
        toolkit: 'storage',
        tool: 'write_file',
        arguments: {'path': '/src/report.html'},
        completed: false,
        argumentDeltaBytes: 100,
      ),
      'Writing file: /src/report.html',
    );
    expect(
      formatToolCallSummary(
        toolkit: 'storage',
        tool: 'write_file',
        arguments: {'path': '/src/report.html'},
        completed: false,
        argumentDeltaBytes: 120,
      ),
      'Writing file: /src/report.html (120 B)',
    );
  });

  test('formatToolCallSummary renders apply patch edits with line counts', () {
    const patch = '''
*** Begin Patch
*** Update File: report.py
@@
-old
+new
+extra
*** End Patch
''';

    expect(formatToolCallSummary(toolkit: 'openai', tool: 'apply_patch', arguments: {'patch': patch}), 'Edited report.py (+2 -1)');
    expect(
      formatToolCallSummary(toolkit: 'openai', tool: 'apply_patch', arguments: {'patch': patch}, completed: false),
      'Editing report.py (+2 -1)',
    );
  });

  test('formatToolCallSummary renders multi-file apply patch edits', () {
    const patch = '''
*** Begin Patch
*** Update File: app.ts
@@
-old
+new
*** Update File: test.ts
@@
+test
*** End Patch
''';

    expect(formatToolCallSummary(toolkit: 'openai', tool: 'apply_patch', arguments: {'patch': patch}), 'Edited 2 files (+2 -1)');
  });

  test('formatToolCallSummary renders OpenAI apply patch operation diffs', () {
    const diff = '''
@@
 context
+added one
+added two
-removed
''';

    expect(
      formatToolCallSummary(
        toolkit: 'openai',
        tool: 'apply_patch',
        arguments: {
          'operation': {'type': 'update_file', 'path': 'report.py', 'diff': diff},
        },
      ),
      'Edited report.py (+2 -1)',
    );
  });

  test('formatToolCallSummary renders Codex diff tool calls with line counts', () {
    const diff = '''
diff --git a/lib/report.py b/lib/report.py
--- a/lib/report.py
+++ b/lib/report.py
@@
-old
+new
+extra
''';

    expect(formatToolCallSummary(toolkit: 'codex', tool: 'diff_updated', arguments: {'diff': diff}), 'Edited lib/report.py (+2 -1)');
    expect(
      formatToolCallSummary(toolkit: 'codex', tool: 'diff_updated', arguments: {'diff': diff}, completed: false),
      'Editing lib/report.py (+2 -1)',
    );
  });

  test('formatToolCallEntryText keeps header and shows trailing details', () {
    final text = formatToolCallEntryText(
      toolkit: 'openai',
      tool: 'web_search',
      arguments: null,
      logs: ['line 1\nline 2\nline 3\nline 4\nline 5'],
      errorMessage: null,
    );

    expect(text, 'line 1\nline 2\nline 3\nline 4\nline 5');
  });

  test('formatToolCallEntryText keeps summary and shows trailing details', () {
    final text = formatToolCallEntryText(
      toolkit: 'storage',
      tool: 'read_file',
      arguments: {'path': '/tmp/report.txt'},
      logs: ['line 1\nline 2\nline 3\nline 4\nline 5'],
      errorMessage: null,
    );

    expect(text, 'Read file: /tmp/report.txt\nline 2\nline 3\nline 4\nline 5');
  });

  test('formatToolCallEntry returns headline and filename metadata', () {
    final display = formatToolCallEntry(
      toolkit: 'storage',
      tool: 'write_file',
      arguments: {'path': '/tmp/report.dart'},
      logs: ['void main() {}\nprint("done");'],
      errorMessage: null,
    );

    expect(display.headline.action, 'Wrote file:');
    expect(display.headline.rest, '/tmp/report.dart');
    expect(display.headline.detailLanguageOrFilename, '/tmp/report.dart');
    expect(display.detailLines, ['void main() {}', 'print("done");']);
    expect(display.detailsTruncated, isFalse);
  });

  test('formatToolCallEntry marks tail details as truncated', () {
    final display = formatToolCallEntry(
      toolkit: 'storage',
      tool: 'read_file',
      arguments: {'path': '/tmp/report.txt'},
      logs: ['line 1\nline 2\nline 3\nline 4\nline 5'],
      errorMessage: null,
    );

    expect(display.detailLines, ['line 2', 'line 3', 'line 4', 'line 5']);
    expect(display.detailsTruncated, isTrue);
  });

  test('formatToolCallEntryText can include all details', () {
    final text = formatToolCallEntryText(
      toolkit: 'storage',
      tool: 'read_file',
      arguments: {'path': '/tmp/report.txt'},
      logs: ['line 1\nline 2\nline 3\nline 4\nline 5'],
      errorMessage: null,
      detailLineLimit: null,
    );

    expect(text, 'Read file: /tmp/report.txt\nline 1\nline 2\nline 3\nline 4\nline 5');
  });

  test('formatToolCallEntryText prefixes path-only log headlines', () {
    final text = formatToolCallEntryText(
      toolkit: 'openai',
      tool: 'shell',
      arguments: null,
      logs: ['/tmp/pie_chart.svg\n/data/pie_chart.svg'],
      errorMessage: null,
    );

    expect(text.split('\n').first, 'Output: /tmp/pie_chart.svg');
  });

  test('formatToolCallEntry extracts filename metadata from log headlines', () {
    final display = formatToolCallEntry(
      toolkit: 'openai',
      tool: 'shell',
      arguments: null,
      logs: ['Saved pie chart to /tmp/pie_chart_matplotlib.svg\n<svg>\n</svg>'],
      errorMessage: null,
    );

    expect(display.headline.action, 'Saved pie chart to');
    expect(display.headline.rest, '/tmp/pie_chart_matplotlib.svg');
    expect(display.headline.detailLanguageOrFilename, '/tmp/pie_chart_matplotlib.svg');
  });
}
