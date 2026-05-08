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
  });

  test('formatToolCallEntryText caps logs and extracts errors', () {
    final text = formatToolCallEntryText(
      toolkit: 'openai',
      tool: 'web_search',
      arguments: null,
      logs: ['line 1\nline 2\nline 3\nline 4\nline 5'],
      errorMessage: null,
    );

    expect(text, 'line 1\nline 2\nline 3\nline 4');
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
}
