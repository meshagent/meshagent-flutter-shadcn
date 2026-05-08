import 'dart:convert';

import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:path/path.dart' as p;

const Set<String> _connectors = {'&&', '||', '|', ';'};
const Set<String> _shellNames = {'bash', 'zsh', 'sh'};
const Set<String> _powerShellNames = {'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe'};
const Set<String> _shellTools = {'shell', 'local_shell', 'code_interpreter'};
const Set<String> _containerCommandTools = {'container_shell', 'process_shell', 'run_in_container'};
const Set<String> _commandTools = {..._shellTools, ..._containerCommandTools};
const int _toolLogRenderLimit = 4;

class ParsedCommand {
  const ParsedCommand({required this.kind, required this.cmd, this.name, this.path, this.query});

  final String kind;
  final String cmd;
  final String? name;
  final String? path;
  final String? query;

  @override
  bool operator ==(Object other) {
    return other is ParsedCommand &&
        other.kind == kind &&
        other.cmd == cmd &&
        other.name == name &&
        other.path == path &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(kind, cmd, name, path, query);
}

class ToolCallHeadline {
  const ToolCallHeadline({required this.action, this.rest = '', this.detailLanguageOrFilename});

  final String action;
  final String rest;
  final String? detailLanguageOrFilename;

  String get text => rest.trim().isEmpty ? action : '$action $rest';
}

class ToolCallEntryDisplay {
  const ToolCallEntryDisplay({required this.headline, required this.detailLines, this.detailsTruncated = false});

  final ToolCallHeadline headline;
  final List<String> detailLines;
  final bool detailsTruncated;

  String get text => [headline.text, ...detailLines].join('\n');
}

List<ParsedCommand> parseToolCommand(Object command) {
  final tokens = _coerceCommandTokens(command);
  final parsed = _parseCommandImpl(tokens);
  final deduped = <ParsedCommand>[];
  for (final item in parsed) {
    if (deduped.isNotEmpty && deduped.last == item) {
      continue;
    }
    deduped.add(item);
  }
  if (deduped.any((item) => item.kind == 'unknown')) {
    return [_singleUnknownForCommand(tokens)];
  }
  return deduped;
}

String formatToolCallSummary({
  required String toolkit,
  required String tool,
  required Map<String, Object?>? arguments,
  bool failed = false,
  bool completed = true,
}) {
  return toolCallHeadline(toolkit: toolkit, tool: tool, arguments: arguments, failed: failed, completed: completed).text;
}

ToolCallHeadline toolCallHeadline({
  required String toolkit,
  required String tool,
  required Map<String, Object?>? arguments,
  bool failed = false,
  bool completed = true,
}) {
  final label = toolCallLabel(toolkit: toolkit, tool: tool, arguments: arguments);
  final friendly = _friendlyBuiltinHeadline(toolkit: toolkit, tool: tool, arguments: arguments, failed: failed, completed: completed);
  if (friendly != null) return friendly;

  final normalizedTool = tool.trim().toLowerCase();
  final normalizedToolkit = toolkit.trim().toLowerCase();
  if (!completed && !failed && normalizedToolkit == 'openai' && _shellTools.contains(normalizedTool) && arguments == null) {
    return const ToolCallHeadline(action: 'Running', rest: 'commands');
  }
  if (failed || !_commandTools.contains(normalizedTool) || arguments == null) {
    return ToolCallHeadline(action: failed ? 'Failed' : (completed ? 'Ran' : 'Running'), rest: label);
  }

  final commands = _commandArguments(tool: normalizedTool, arguments: arguments);
  if (commands.isEmpty) {
    return ToolCallHeadline(action: failed ? 'Failed' : (completed ? 'Ran' : 'Running'), rest: label);
  }

  final parsed = <ParsedCommand>[];
  for (final command in commands) {
    parsed.addAll(parseToolCommand(command));
  }
  if (parsed.isEmpty || parsed.any((item) => item.kind == 'unknown')) {
    return ToolCallHeadline(action: completed ? 'Ran' : 'Running', rest: label);
  }

  final lines = ['Explored'];
  for (final line in _exploringDetailLines(parsed)) {
    lines.add('  $line');
  }
  return ToolCallHeadline(action: lines.join('\n'));
}

String formatToolCallEntryText({
  required String toolkit,
  required String tool,
  required Map<String, Object?>? arguments,
  required List<String> logs,
  required String? errorMessage,
  bool completed = true,
  int? detailLineLimit = _toolLogRenderLimit,
}) {
  return formatToolCallEntry(
    toolkit: toolkit,
    tool: tool,
    arguments: arguments,
    logs: logs,
    errorMessage: errorMessage,
    completed: completed,
    detailLineLimit: detailLineLimit,
  ).text;
}

ToolCallEntryDisplay formatToolCallEntry({
  required String toolkit,
  required String tool,
  required Map<String, Object?>? arguments,
  required List<String> logs,
  required String? errorMessage,
  bool completed = true,
  int? detailLineLimit = _toolLogRenderLimit,
}) {
  final failed = errorMessage != null;
  var headline = toolCallHeadline(toolkit: toolkit, tool: tool, arguments: arguments, failed: failed, completed: completed);
  final rawHeadline = '${failed ? "Failed" : "Ran"} ${toolCallRawLabel(toolkit: toolkit, tool: tool)}';
  final logLines = _toolLogLines(logs).toList(growable: true);
  if (failed && _logLinesLookLikeTraceback(logLines)) {
    logLines.clear();
  }
  if (headline.text == rawHeadline && logLines.isNotEmpty) {
    headline = _logHeadline(logLines.removeAt(0));
  }

  final detailsTruncated = detailLineLimit != null && logLines.length > detailLineLimit;
  final displayedLogLines = detailLineLimit == null ? logLines : _trailingLogLines(logLines, detailLineLimit);
  final detailLines = <String>[...displayedLogLines];
  final errorLine = _toolErrorLine(errorMessage);
  if (errorLine != null) {
    detailLines.add(errorLine);
  }
  return ToolCallEntryDisplay(headline: headline, detailLines: detailLines, detailsTruncated: detailsTruncated);
}

String toolCallRawLabel({required String toolkit, required String tool}) {
  final normalizedTool = tool.trim().isEmpty ? 'tool' : tool.trim();
  final normalizedToolkit = toolkit.trim();
  if (normalizedToolkit.isNotEmpty && normalizedToolkit != normalizedTool) {
    return '$normalizedToolkit: $normalizedTool';
  }
  return normalizedTool;
}

String toolCallLabel({required String toolkit, required String tool, required Map<String, Object?>? arguments}) {
  final normalizedTool = tool.trim();
  final normalizedToolkit = toolkit.trim();
  if (_commandTools.contains(normalizedTool.toLowerCase()) && arguments != null) {
    final commands = _commandArguments(tool: normalizedTool.toLowerCase(), arguments: arguments);
    if (commands.isNotEmpty) {
      return commands.map(_commandLabel).join(' && ');
    }
  }
  if (normalizedToolkit.isNotEmpty && normalizedToolkit != normalizedTool) {
    return '$normalizedToolkit: ${normalizedTool.isEmpty ? "tool" : normalizedTool}';
  }
  return normalizedTool.isEmpty ? 'tool' : normalizedTool;
}

ToolCallHeadline? _friendlyBuiltinHeadline({
  required String toolkit,
  required String tool,
  required Map<String, Object?>? arguments,
  required bool failed,
  required bool completed,
}) {
  final normalizedToolkit = toolkit.trim().toLowerCase();
  final normalizedTool = tool.trim().toLowerCase();
  final args = arguments ?? const <String, Object?>{};
  ToolCallHeadline? headline;
  if (normalizedToolkit == 'storage') {
    headline = _storageHeadline(tool: normalizedTool, arguments: args, completed: completed);
  } else if (normalizedToolkit == 'dataset') {
    headline = _headlineFromText(_datasetSummary(tool: normalizedTool, arguments: args, completed: completed));
  } else if (normalizedToolkit == 'datetime' || normalizedToolkit == 'time') {
    headline = _headlineFromText(_datetimeSummary(tool: normalizedTool, arguments: args, completed: completed));
  } else if (normalizedToolkit == 'web_fetch') {
    headline = _headlineFromText(_webFetchSummary(tool: normalizedTool, arguments: args, completed: completed));
  } else if (normalizedToolkit == 'container') {
    headline = _headlineFromText(_containerSummary(tool: normalizedTool, completed: completed));
  } else if (normalizedToolkit == 'chat') {
    headline = _headlineFromText(_chatSummary(tool: normalizedTool, arguments: args, completed: completed));
  } else if (normalizedToolkit == 'mail' || normalizedToolkit == 'email' || normalizedToolkit == 'emails') {
    headline = _headlineFromText(_mailSummary(tool: normalizedTool, arguments: args, completed: completed));
  }
  if (headline == null) return null;
  return failed
      ? ToolCallHeadline(action: 'Failed:', rest: headline.text, detailLanguageOrFilename: headline.detailLanguageOrFilename)
      : headline;
}

ToolCallHeadline? _storageHeadline({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  final path = _stringArgument(arguments, ['path']);
  if (tool == 'read_file') {
    return ToolCallHeadline(
      action: path == null ? (completed ? 'Read file' : 'Reading file') : (completed ? 'Read file:' : 'Reading file:'),
      rest: path ?? '',
      detailLanguageOrFilename: path,
    );
  }
  if (tool == 'grep_file') {
    final pattern = _stringArgument(arguments, ['pattern']);
    if (pattern != null && path != null) {
      return ToolCallHeadline(action: completed ? 'Searched' : 'Searching', rest: '$path for $pattern');
    }
    return ToolCallHeadline(
      action: path == null ? (completed ? 'Searched file' : 'Searching file') : (completed ? 'Searched file:' : 'Searching file:'),
      rest: path ?? '',
    );
  }
  if (tool == 'write_file') {
    return ToolCallHeadline(
      action: path == null ? (completed ? 'Wrote file' : 'Writing file') : (completed ? 'Wrote file:' : 'Writing file:'),
      rest: path ?? '',
      detailLanguageOrFilename: path,
    );
  }
  if (tool == 'get_file_download_url') {
    return ToolCallHeadline(
      action: path == null
          ? (completed ? 'Prepared download' : 'Preparing download')
          : (completed ? 'Prepared download:' : 'Preparing download:'),
      rest: path ?? '',
    );
  }
  if (tool == 'list_files_in_room') {
    return ToolCallHeadline(
      action: path == null ? (completed ? 'Listed files' : 'Listing files') : (completed ? 'Listed files:' : 'Listing files:'),
      rest: path ?? '',
    );
  }
  if (tool == 'save_file_from_url') {
    final url = _stringArgument(arguments, ['url']);
    if (path != null) {
      return ToolCallHeadline(action: completed ? 'Saved file to' : 'Saving file to', rest: path, detailLanguageOrFilename: path);
    }
    return ToolCallHeadline(action: completed ? 'Saved file from URL:' : 'Saving file from URL:', rest: url ?? '');
  }
  return null;
}

ToolCallHeadline? _headlineFromText(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex >= 0 && colonIndex + 1 < 30) {
    return ToolCallHeadline(action: trimmed.substring(0, colonIndex + 1), rest: trimmed.substring(colonIndex + 1).trim());
  }
  final firstWordMatch = RegExp(r'^\S+').firstMatch(trimmed);
  if (firstWordMatch == null) return ToolCallHeadline(action: trimmed);
  return ToolCallHeadline(action: trimmed.substring(0, firstWordMatch.end), rest: trimmed.substring(firstWordMatch.end).trim());
}

String? _datasetSummary({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  if (tool == 'list_tables') return completed ? 'Listed dataset tables' : 'Listing dataset tables';
  if (tool == 'execute_sql') {
    final query = _stringArgument(arguments, ['query']);
    final prefix = completed ? 'Ran SQL' : 'Running SQL';
    return query == null ? prefix : '$prefix: ${_singleLine(query)}';
  }
  final table = _datasetTableFromTool(tool: tool);
  if (tool.startsWith('insert_') && tool.endsWith('_rows')) {
    return _withOptionalSuffix(completed ? 'Inserted dataset rows' : 'Inserting dataset rows', table);
  }
  if (tool.startsWith('update_') && tool.endsWith('_rows')) {
    return _withOptionalSuffix(completed ? 'Updated dataset rows' : 'Updating dataset rows', table);
  }
  if (tool.startsWith('delete_') && tool.endsWith('_rows')) {
    return _withOptionalSuffix(completed ? 'Deleted dataset rows' : 'Deleting dataset rows', table);
  }
  if (tool.startsWith('advanced_delete_')) return _withOptionalSuffix(completed ? 'Deleted dataset rows' : 'Deleting dataset rows', table);
  if (tool.startsWith('search_') || tool.startsWith('advanced_search_')) {
    return _withOptionalSuffix(completed ? 'Searched dataset' : 'Searching dataset', table);
  }
  if (tool.startsWith('count_')) return _withOptionalSuffix(completed ? 'Counted dataset rows' : 'Counting dataset rows', table);
  if (tool.startsWith('spawn_task_for_each_') && tool.endsWith('_row')) {
    return _withOptionalSuffix(completed ? 'Queued tasks for dataset rows' : 'Queueing tasks for dataset rows', table);
  }
  return null;
}

String? _datetimeSummary({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  final tz = _stringArgument(arguments, ['tz', 'assume_tz']);
  if (tool == 'now') return _withOptionalSuffix(completed ? 'Checked current time' : 'Checking current time', tz);
  if (tool == 'today_range') return _withOptionalSuffix(completed ? 'Checked today' : 'Checking today', tz);
  if (tool == 'week_range') return _withOptionalSuffix(completed ? 'Checked week range' : 'Checking week range', tz);
  if (tool == 'month_range') return _withOptionalSuffix(completed ? 'Checked month range' : 'Checking month range', tz);
  if (tool == 'add_duration') return completed ? 'Added duration' : 'Adding duration';
  if (tool == 'diff') return completed ? 'Compared datetimes' : 'Comparing datetimes';
  if (tool == 'parse_iso') return completed ? 'Parsed datetime' : 'Parsing datetime';
  if (tool == 'format_dt') return completed ? 'Formatted datetime' : 'Formatting datetime';
  if (tool == 'to_utc_z') return completed ? 'Converted datetime to UTC' : 'Converting datetime to UTC';
  return null;
}

String? _webFetchSummary({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  final url = _stringArgument(arguments, ['url']);
  if (tool == 'web_fetch') return _withOptionalSuffix(completed ? 'Fetched URL' : 'Fetching URL', url);
  if (tool == 'web_grep') {
    final pattern = _stringArgument(arguments, ['pattern']);
    if (pattern != null && url != null) return '${completed ? "Searched" : "Searching"} $url for $pattern';
    return _withOptionalSuffix(completed ? 'Searched URL' : 'Searching URL', url);
  }
  return null;
}

String? _containerSummary({required String tool, required bool completed}) {
  if (tool == 'list_managed_containers') return completed ? 'Listed containers' : 'Listing containers';
  if (tool == 'start_container') return completed ? 'Started container' : 'Starting container';
  if (tool == 'stop_managed_container') return completed ? 'Stopped container' : 'Stopping container';
  return null;
}

String? _chatSummary({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  if (tool == 'new_thread') return completed ? 'Started chat thread' : 'Starting chat thread';
  if (tool == 'attach_file') {
    return _withOptionalSuffix(completed ? 'Attached file' : 'Attaching file', _stringArgument(arguments, ['path']));
  }
  if (tool == 'list_threads') return completed ? 'Listed chat threads' : 'Listing chat threads';
  if (tool == 'grep_thread_list') {
    return _withOptionalSuffix(completed ? 'Searched chat threads' : 'Searching chat threads', _stringArgument(arguments, ['pattern']));
  }
  if (tool.startsWith('run_') && tool.endsWith('_task')) {
    return _withOptionalSuffix(completed ? 'Sent task' : 'Sending task', _stringArgument(arguments, ['prompt']));
  }
  return null;
}

String? _mailSummary({required String tool, required Map<String, Object?> arguments, required bool completed}) {
  if (tool == 'new_email_thread') {
    final subject = _stringArgument(arguments, ['subject']);
    final prefix = completed ? 'Started email thread' : 'Starting email thread';
    return subject == null ? prefix : '$prefix: $subject';
  }
  if (tool == 'attach_file' || tool == 'attach file') {
    return _withOptionalSuffix(completed ? 'Attached file' : 'Attaching file', _stringArgument(arguments, ['path']));
  }
  return null;
}

List<String> _exploringDetailLines(List<ParsedCommand> commands) {
  final lines = <String>[];
  var readNames = <String>[];
  for (final command in commands) {
    if (command.kind == 'read') {
      final name = command.name;
      if (name != null && !readNames.contains(name)) {
        readNames.add(name);
      }
      continue;
    }
    if (readNames.isNotEmpty) {
      lines.add('Read ${readNames.join(", ")}');
      readNames = <String>[];
    }
    if (command.kind == 'list_files') {
      lines.add(command.path == null ? 'List files' : 'List ${command.path}');
    } else if (command.kind == 'search') {
      if (command.query != null && command.path != null) {
        lines.add('Search ${command.query} in ${command.path}');
      } else if (command.query != null) {
        lines.add('Search ${command.query}');
      } else if (command.path != null) {
        lines.add('Search in ${command.path}');
      } else {
        lines.add('Search');
      }
    }
  }
  if (readNames.isNotEmpty) {
    lines.add('Read ${readNames.join(", ")}');
  }
  return [for (final item in lines.indexed) item.$1 == 0 ? '└ ${item.$2}' : '  ${item.$2}'];
}

Object? _shellCommandArgument(Map<String, Object?> arguments) {
  for (final key in ['command', 'cmd', 'code']) {
    final value = arguments[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.every((item) => item is String)) return value.cast<String>().toList();
  }
  final action = arguments['action'];
  if (action is Map) {
    final command = action['command'];
    if (command is String && command.trim().isNotEmpty) return command.trim();
    if (command is List && command.every((item) => item is String)) return command.cast<String>().toList();
  }
  return null;
}

List<Object> _commandArguments({required String tool, required Map<String, Object?> arguments}) {
  if (_shellTools.contains(tool)) {
    final command = _shellCommandArgument(arguments);
    return command == null ? const [] : [command];
  }
  if (_containerCommandTools.contains(tool)) {
    final commands = arguments['commands'];
    if (commands is List && commands.every((item) => item is String)) {
      return commands.cast<String>().map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    }
    final command = _shellCommandArgument(arguments);
    return command == null ? const [] : [command];
  }
  return const [];
}

String _commandLabel(Object command) {
  if (command is String) return command;
  if (command is List) return _shlexJoin(command.map((item) => item.toString()).toList());
  return command.toString();
}

String? _stringArgument(Map<String, Object?> arguments, List<String> names) {
  for (final name in names) {
    final value = arguments[name];
    if (value is String && value.trim().isNotEmpty) return _singleLine(value.trim());
  }
  return null;
}

String _withOptionalSuffix(String prefix, String? suffix) {
  return suffix == null ? prefix : '$prefix: $suffix';
}

String _singleLine(String value) {
  return value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join(' ');
}

String? _datasetTableFromTool({required String tool}) {
  for (final pattern in [
    RegExp(r'^insert_(.+)_rows$'),
    RegExp(r'^update_(.+)_rows$'),
    RegExp(r'^delete_(.+)_rows$'),
    RegExp(r'^advanced_delete_(.+)$'),
    RegExp(r'^advanced_search_(.+)$'),
    RegExp(r'^search_(.+)$'),
    RegExp(r'^count_(.+)$'),
    RegExp(r'^spawn_task_for_each_(.+)_row$'),
  ]) {
    final match = pattern.firstMatch(tool);
    if (match != null) return match.group(1);
  }
  return null;
}

List<String> _coerceCommandTokens(Object command) {
  if (command is String) return _shlexSplit(command);
  if (command is List) return command.map((item) => item.toString()).toList();
  return [command.toString()];
}

List<String> _shlexSplit(String script) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaped = false;
  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  for (var index = 0; index < script.length; index += 1) {
    final char = script[index];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      flush();
      continue;
    }
    final two = index + 1 < script.length ? script.substring(index, index + 2) : '';
    if (two == '&&' || two == '||') {
      flush();
      tokens.add(two);
      index += 1;
      continue;
    }
    if (char == '|' || char == ';') {
      flush();
      tokens.add(char);
      continue;
    }
    buffer.write(char);
  }
  if (escaped) buffer.write('\\');
  flush();
  return tokens;
}

String _shlexJoin(List<String> tokens) {
  return tokens
      .map((token) {
        if (token.isEmpty) return "''";
        if (!RegExp(r'''[\s'"\\|&;]''').hasMatch(token)) return token;
        return "'${token.replaceAll("'", "'\"'\"'")}'";
      })
      .join(' ');
}

List<ParsedCommand> _parseCommandImpl(List<String> command) {
  final shellCommand = _extractShellCommand(command);
  if (shellCommand != null) return _parseShellScript(shellCommand);
  final powershellCommand = _extractPowerShellCommand(command);
  if (powershellCommand != null) return [ParsedCommand(kind: 'unknown', cmd: powershellCommand)];
  final normalized = _normalizeTokens(command);
  final parts = _containsConnectors(normalized) ? _splitOnConnectors(normalized) : [normalized];
  final commands = <ParsedCommand>[];
  String? cwd;
  for (final tokens in parts) {
    if (tokens.isEmpty) continue;
    if (tokens.first == 'cd') {
      final target = _cdTarget(tokens.skip(1).toList());
      if (target != null) cwd = _joinPaths(cwd, target);
      continue;
    }
    commands.add(_withCwd(_summarizeMainTokens(tokens), cwd));
  }
  return _simplify(commands);
}

List<ParsedCommand> _parseShellScript(String script) {
  final tokens = _shlexSplit(script);
  if (tokens.isEmpty) return [ParsedCommand(kind: 'unknown', cmd: script)];
  final parts = _containsConnectors(tokens) ? _splitOnConnectors(tokens) : [tokens];
  final hadConnectors = parts.length > 1;
  final filtered = _dropSmallFormattingCommands(parts);
  if (filtered.isEmpty) return [ParsedCommand(kind: 'unknown', cmd: script)];
  final commands = <ParsedCommand>[];
  String? cwd;
  for (final part in filtered) {
    if (part.isEmpty) continue;
    if (part.first == 'cd') {
      final target = _cdTarget(part.skip(1).toList());
      if (target != null) cwd = _joinPaths(cwd, target);
      continue;
    }
    commands.add(_withCwd(_summarizeMainTokens(part), cwd));
  }
  final simplified = _simplify(commands);
  if (simplified.length == 1) {
    final command = simplified.first;
    if (command.kind == 'read') {
      if (hadConnectors && tokens.contains('|') && _scriptContainsSedN(tokens)) {
        return [ParsedCommand(kind: 'read', cmd: script, name: command.name, path: command.path)];
      }
      if (!hadConnectors) {
        return [ParsedCommand(kind: 'read', cmd: _shlexJoin(tokens), name: command.name, path: command.path)];
      }
    }
    if ((command.kind == 'list_files' || command.kind == 'search') && !hadConnectors) {
      return [ParsedCommand(kind: command.kind, cmd: _shlexJoin(tokens), name: command.name, path: command.path, query: command.query)];
    }
  }
  return simplified;
}

ParsedCommand _singleUnknownForCommand(List<String> command) {
  final shellCommand = _extractShellCommand(command);
  if (shellCommand != null) return ParsedCommand(kind: 'unknown', cmd: shellCommand);
  final powershellCommand = _extractPowerShellCommand(command);
  if (powershellCommand != null) return ParsedCommand(kind: 'unknown', cmd: powershellCommand);
  return ParsedCommand(kind: 'unknown', cmd: _shlexJoin(command));
}

String? _extractShellCommand(List<String> command) {
  if (command.length < 3) return null;
  final shellName = p.basename(command.first).toLowerCase();
  if (!_shellNames.contains(shellName)) return null;
  for (var index = 1; index < command.length - 1; index += 1) {
    final flag = command[index];
    if (flag == '-c' || flag == '-lc') return command[index + 1];
    if (flag.startsWith('-') && flag.contains('c')) return command[index + 1];
  }
  return null;
}

String? _extractPowerShellCommand(List<String> command) {
  if (command.length < 2) return null;
  final shellName = p.basename(command.first).toLowerCase();
  if (!_powerShellNames.contains(shellName)) return null;
  for (var index = 1; index < command.length - 1; index += 1) {
    final flag = command[index].toLowerCase();
    if (flag == '-command' || flag == '-c') return command[index + 1];
  }
  return null;
}

List<String> _normalizeTokens(List<String> command) {
  if (command.length >= 3 && {'yes', 'y', 'no', 'n'}.contains(command[0]) && command[1] == '|') {
    return command.sublist(2);
  }
  final shellCommand = _extractShellCommand(command);
  return shellCommand == null ? [...command] : _shlexSplit(shellCommand);
}

bool _containsConnectors(List<String> tokens) => tokens.any(_connectors.contains);

List<List<String>> _splitOnConnectors(List<String> tokens) {
  final parts = <List<String>>[];
  var current = <String>[];
  for (final token in tokens) {
    if (_connectors.contains(token)) {
      if (current.isNotEmpty) {
        parts.add(current);
        current = <String>[];
      }
    } else {
      current.add(token);
    }
  }
  if (current.isNotEmpty) parts.add(current);
  return parts;
}

List<String> _trimAtConnector(List<String> tokens) {
  final index = tokens.indexWhere(_connectors.contains);
  return index == -1 ? [...tokens] : tokens.sublist(0, index);
}

String _shortDisplayPath(String path) {
  final normalized = path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
  final parts = normalized.split('/').reversed.where((part) => part.isNotEmpty && !{'build', 'dist', 'node_modules', 'src'}.contains(part));
  return parts.isNotEmpty ? parts.first : normalized;
}

List<String> _skipFlagValues(List<String> args, Set<String> flagsWithValues) {
  final output = <String>[];
  var skipNext = false;
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (skipNext) {
      skipNext = false;
      continue;
    }
    if (arg == '--') {
      output.addAll(args.sublist(index + 1));
      break;
    }
    if (arg.startsWith('--') && arg.contains('=')) continue;
    if (flagsWithValues.contains(arg)) {
      skipNext = index + 1 < args.length;
      continue;
    }
    output.add(arg);
  }
  return output;
}

List<String> _positionalOperands(List<String> args, Set<String> flagsWithValues) {
  final output = <String>[];
  var afterDoubleDash = false;
  var skipNext = false;
  for (final arg in args) {
    if (skipNext) {
      skipNext = false;
      continue;
    }
    if (afterDoubleDash) {
      output.add(arg);
      continue;
    }
    if (arg == '--') {
      afterDoubleDash = true;
      continue;
    }
    if (arg.startsWith('--') && arg.contains('=')) continue;
    if (flagsWithValues.contains(arg)) {
      skipNext = true;
      continue;
    }
    if (arg.startsWith('-')) continue;
    output.add(arg);
  }
  return output;
}

String? _firstNonFlagOperand(List<String> args, Set<String> flagsWithValues) {
  final operands = _positionalOperands(args, flagsWithValues);
  return operands.isEmpty ? null : operands.first;
}

String? _firstNonFlag(Iterable<String> args) {
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      return arg;
    }
  }
  return null;
}

String? _singleNonFlagOperand(List<String> args, Set<String> flagsWithValues) {
  final operands = _positionalOperands(args, flagsWithValues);
  return operands.length == 1 ? operands.first : null;
}

ParsedCommand _parseGrepLike(List<String> mainCmd, List<String> args) {
  final argsNoConnector = _trimAtConnector(args);
  final operands = <String>[];
  String? pattern;
  var afterDoubleDash = false;
  var index = 0;
  while (index < argsNoConnector.length) {
    final arg = argsNoConnector[index];
    if (afterDoubleDash) {
      operands.add(arg);
      index += 1;
      continue;
    }
    if (arg == '--') {
      afterDoubleDash = true;
      index += 1;
      continue;
    }
    if (arg == '-e' || arg == '--regexp' || arg == '-f' || arg == '--file') {
      if (index + 1 < argsNoConnector.length && pattern == null) pattern = argsNoConnector[index + 1];
      index += 2;
      continue;
    }
    if ({'-m', '--max-count', '-C', '--context', '-A', '--after-context', '-B', '--before-context'}.contains(arg)) {
      index += 2;
      continue;
    }
    if (arg.startsWith('-')) {
      index += 1;
      continue;
    }
    operands.add(arg);
    index += 1;
  }
  final hasPattern = pattern != null;
  final query = pattern ?? (operands.isNotEmpty ? operands.first : null);
  final pathIndex = hasPattern ? 0 : 1;
  final path = operands.length > pathIndex ? _shortDisplayPath(operands[pathIndex]) : null;
  return ParsedCommand(kind: 'search', cmd: _shlexJoin(mainCmd), query: query, path: path);
}

String? _awkDataFileOperand(List<String> args) {
  if (args.isEmpty) return null;
  final argsNoConnector = _trimAtConnector(args);
  final hasScriptFile = argsNoConnector.any((arg) => arg == '-f' || arg == '--file');
  final candidates = _skipFlagValues(argsNoConnector, {'-F', '-v', '-f', '--field-separator', '--assign', '--file'});
  final nonFlags = candidates.where((arg) => !arg.startsWith('-')).toList();
  if (hasScriptFile) return nonFlags.isEmpty ? null : nonFlags.first;
  if (nonFlags.length >= 2) return nonFlags[1];
  return null;
}

bool _pythonWalksFiles(List<String> args) {
  final argsNoConnector = _trimAtConnector(args);
  for (var index = 0; index < argsNoConnector.length - 1; index += 1) {
    if (argsNoConnector[index] == '-c') {
      final script = argsNoConnector[index + 1];
      return ['os.walk', 'os.listdir', 'os.scandir', 'glob.glob', 'glob.iglob', 'pathlib.Path', '.rglob('].any(script.contains);
    }
  }
  return false;
}

bool _isPythonCommand(String command) =>
    command == 'python' || command == 'python2' || command == 'python3' || command.startsWith('python2.') || command.startsWith('python3.');

String? _cdTarget(List<String> args) {
  String? target;
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--') return index + 1 < args.length ? args[index + 1] : null;
    if (arg == '-L' || arg == '-P' || arg.startsWith('-')) continue;
    target = arg;
  }
  return target;
}

bool _isPathish(String value) =>
    value == '.' || value == '..' || value.startsWith('./') || value.startsWith('../') || value.contains('/') || value.contains('\\');

(String?, String?) _parseFdQueryAndPath(List<String> tail) {
  final argsNoConnector = _trimAtConnector(tail);
  final candidates = _skipFlagValues(argsNoConnector, {'-t', '--type', '-e', '--extension', '-E', '--exclude', '--search-path'});
  final nonFlags = candidates.where((arg) => !arg.startsWith('-')).toList();
  if (nonFlags.length == 1) {
    final one = nonFlags.first;
    if (_isPathish(one)) return (null, _shortDisplayPath(one));
    return (one, null);
  }
  if (nonFlags.length >= 2) return (nonFlags.first, _shortDisplayPath(nonFlags[1]));
  return (null, null);
}

(String?, String?) _parseFindQueryAndPath(List<String> tail) {
  final argsNoConnector = _trimAtConnector(tail);
  String? path;
  for (final arg in argsNoConnector) {
    if (!arg.startsWith('-') && !{'!', '(', ')'}.contains(arg)) {
      path = _shortDisplayPath(arg);
      break;
    }
  }
  String? query;
  for (var index = 0; index < argsNoConnector.length - 1; index += 1) {
    if ({'-name', '-iname', '-path', '-regex'}.contains(argsNoConnector[index])) {
      query = argsNoConnector[index + 1];
      break;
    }
  }
  return (query, path);
}

bool _isValidSedNArg(String? value) {
  if (value == null || !value.endsWith('p')) return false;
  final parts = value.substring(0, value.length - 1).split(',');
  if (parts.length == 1) return int.tryParse(parts[0]) != null;
  if (parts.length == 2) return int.tryParse(parts[0]) != null && int.tryParse(parts[1]) != null;
  return false;
}

String? _sedReadPath(List<String> args) {
  final argsNoConnector = _trimAtConnector(args);
  if (!argsNoConnector.contains('-n')) return null;
  var hasRangeScript = false;
  var index = 0;
  while (index < argsNoConnector.length) {
    final arg = argsNoConnector[index];
    if (arg == '-e' || arg == '--expression') {
      if (index + 1 < argsNoConnector.length && _isValidSedNArg(argsNoConnector[index + 1])) hasRangeScript = true;
      index += 2;
      continue;
    }
    if (arg == '-f' || arg == '--file') {
      index += 2;
      continue;
    }
    index += 1;
  }
  hasRangeScript = hasRangeScript || argsNoConnector.any((arg) => !arg.startsWith('-') && _isValidSedNArg(arg));
  if (!hasRangeScript) return null;
  final candidates = _skipFlagValues(argsNoConnector, {'-e', '-f', '--expression', '--file'});
  final nonFlags = candidates.where((arg) => !arg.startsWith('-')).toList();
  if (nonFlags.isEmpty) return null;
  if (_isValidSedNArg(nonFlags.first)) return nonFlags.length > 1 ? nonFlags[1] : null;
  return nonFlags.first;
}

bool _isSmallFormattingCommand(List<String> tokens) {
  if (tokens.isEmpty) return false;
  final command = tokens.first;
  if ({'wc', 'tr', 'cut', 'sort', 'uniq', 'tee', 'column', 'yes', 'printf'}.contains(command)) return true;
  if (command == 'xargs') return !_isMutatingXargsCommand(tokens);
  if (command == 'awk') return _awkDataFileOperand(tokens.skip(1).toList()) == null;
  if (command == 'head') {
    if (tokens.length == 1) return true;
    if (tokens.length == 2) return tokens[1].startsWith('-');
    if (tokens.length == 3 && (tokens[1] == '-n' || tokens[1] == '-c') && int.tryParse(tokens[2]) != null) return true;
    return false;
  }
  if (command == 'tail') {
    if (tokens.length == 1) return true;
    if (tokens.length == 2) return tokens[1].startsWith('-');
    if (tokens.length == 3 && (tokens[1] == '-n' || tokens[1] == '-c')) {
      final value = tokens[2].startsWith('+') ? tokens[2].substring(1) : tokens[2];
      return int.tryParse(value) != null;
    }
    return false;
  }
  if (command == 'sed') return _sedReadPath(tokens.skip(1).toList()) == null;
  return false;
}

bool _isMutatingXargsCommand(List<String> tokens) {
  final subcommand = _xargsSubcommand(tokens);
  return subcommand != null && _xargsIsMutatingSubcommand(subcommand);
}

List<String>? _xargsSubcommand(List<String> tokens) {
  if (tokens.isEmpty || tokens.first != 'xargs') return null;
  var index = 1;
  while (index < tokens.length) {
    final token = tokens[index];
    if (token == '--') return index + 1 < tokens.length ? tokens.sublist(index + 1) : null;
    if (!token.startsWith('-')) return tokens.sublist(index);
    final takesValue = {'-E', '-e', '-I', '-L', '-n', '-P', '-s'}.contains(token);
    index += takesValue && token.length == 2 ? 2 : 1;
  }
  return null;
}

bool _xargsIsMutatingSubcommand(List<String> tokens) {
  if (tokens.isEmpty) return false;
  final command = tokens.first;
  final tail = tokens.skip(1).toList();
  if (command == 'perl' || command == 'ruby') return _xargsHasInPlaceFlag(tail);
  if (command == 'sed') return _xargsHasInPlaceFlag(tail) || tail.contains('--in-place');
  if (command == 'rg') return tail.contains('--replace');
  return false;
}

bool _xargsHasInPlaceFlag(List<String> tokens) {
  return tokens.any((token) => token == '-i' || token.startsWith('-i') || token == '-pi' || token.startsWith('-pi'));
}

List<List<String>> _dropSmallFormattingCommands(List<List<String>> commands) =>
    commands.where((tokens) => !_isSmallFormattingCommand(tokens)).toList();

ParsedCommand _summarizeMainTokens(List<String> mainCmd) {
  if (mainCmd.isEmpty) return const ParsedCommand(kind: 'unknown', cmd: '');
  final command = mainCmd.first;
  final tail = mainCmd.skip(1).toList();
  if (command == 'ls' || command == 'eza' || command == 'exa') {
    final flags = command == 'ls'
        ? {'-I', '-w', '--block-size', '--format', '--time-style', '--color', '--quoting-style'}
        : {'-I', '--ignore-glob', '--color', '--sort', '--time-style', '--time'};
    final path = _firstNonFlagOperand(tail, flags);
    return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: path == null ? null : _shortDisplayPath(path));
  }
  if (command == 'tree') {
    final path = _firstNonFlagOperand(tail, {'-L', '-P', '-I', '--charset', '--filelimit', '--sort'});
    return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: path == null ? null : _shortDisplayPath(path));
  }
  if (command == 'du') {
    final path = _firstNonFlagOperand(tail, {'-d', '--max-depth', '-B', '--block-size', '--exclude', '--time-style'});
    return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: path == null ? null : _shortDisplayPath(path));
  }
  if (command == 'rg' || command == 'rga' || command == 'ripgrep-all') {
    final argsNoConnector = _trimAtConnector(tail);
    final hasFilesFlag = argsNoConnector.contains('--files');
    final candidates = _skipFlagValues(argsNoConnector, {
      '-g',
      '--glob',
      '--iglob',
      '-t',
      '--type',
      '--type-add',
      '--type-not',
      '-m',
      '--max-count',
      '-A',
      '-B',
      '-C',
      '--context',
      '--max-depth',
    });
    final nonFlags = candidates.where((arg) => !arg.startsWith('-')).toList();
    if (hasFilesFlag) {
      final path = nonFlags.isNotEmpty ? nonFlags.first : null;
      return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: path == null ? null : _shortDisplayPath(path));
    }
    final query = nonFlags.isNotEmpty ? nonFlags.first : null;
    final path = nonFlags.length > 1 ? nonFlags[1] : null;
    return ParsedCommand(kind: 'search', cmd: _shlexJoin(mainCmd), query: query, path: path == null ? null : _shortDisplayPath(path));
  }
  if (command == 'git') {
    if (tail.isNotEmpty && tail.first == 'grep') return _parseGrepLike(mainCmd, tail.skip(1).toList());
    if (tail.isNotEmpty && tail.first == 'ls-files') {
      final path = _firstNonFlagOperand(tail.skip(1).toList(), {'--exclude', '--exclude-from', '--pathspec-from-file'});
      return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: path == null ? null : _shortDisplayPath(path));
    }
    return ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd));
  }
  if (command == 'fd') {
    final parsed = _parseFdQueryAndPath(tail);
    if (parsed.$1 != null) return ParsedCommand(kind: 'search', cmd: _shlexJoin(mainCmd), query: parsed.$1, path: parsed.$2);
    return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: parsed.$2);
  }
  if (command == 'find') {
    final parsed = _parseFindQueryAndPath(tail);
    if (parsed.$1 != null) return ParsedCommand(kind: 'search', cmd: _shlexJoin(mainCmd), query: parsed.$1, path: parsed.$2);
    return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd), path: parsed.$2);
  }
  if (command == 'grep' || command == 'egrep' || command == 'fgrep') return _parseGrepLike(mainCmd, tail);
  if (command == 'ag' || command == 'ack' || command == 'pt') {
    final candidates = _skipFlagValues(_trimAtConnector(tail), {
      '-G',
      '-g',
      '--file-search-regex',
      '--ignore-dir',
      '--ignore-file',
      '--path-to-ignore',
    });
    final nonFlags = candidates.where((arg) => !arg.startsWith('-')).toList();
    final query = nonFlags.isNotEmpty ? nonFlags.first : null;
    final path = nonFlags.length > 1 ? nonFlags[1] : null;
    return ParsedCommand(kind: 'search', cmd: _shlexJoin(mainCmd), query: query, path: path == null ? null : _shortDisplayPath(path));
  }
  if (command == 'cat') return _readFromSingleOperand(mainCmd, tail, {});
  if (command == 'bat' || command == 'batcat') {
    return _readFromSingleOperand(mainCmd, tail, {
      '--theme',
      '--language',
      '--style',
      '--terminal-width',
      '--tabs',
      '--line-range',
      '--map-syntax',
    });
  }
  if (command == 'less') {
    return _readFromSingleOperand(mainCmd, tail, {
      '-p',
      '-P',
      '-x',
      '-y',
      '-z',
      '-j',
      '--pattern',
      '--prompt',
      '--tabs',
      '--shift',
      '--jump-target',
    });
  }
  if (command == 'more') return _readFromSingleOperand(mainCmd, tail, {});
  if (command == 'head') {
    final path = _headTailPath(tail, allowPlus: false);
    return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
  }
  if (command == 'tail') {
    final path = _headTailPath(tail, allowPlus: true);
    return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
  }
  if (command == 'awk') {
    final path = _awkDataFileOperand(tail);
    return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
  }
  if (command == 'nl') {
    final candidates = _skipFlagValues(tail, {'-s', '-w', '-v', '-i', '-b'});
    final path = _firstNonFlag(candidates);
    return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
  }
  if (command == 'sed') {
    final path = _sedReadPath(tail);
    return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
  }
  if (_isPythonCommand(command)) {
    if (_pythonWalksFiles(tail)) return ParsedCommand(kind: 'list_files', cmd: _shlexJoin(mainCmd));
    return ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd));
  }
  return ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd));
}

ParsedCommand _readFromSingleOperand(List<String> mainCmd, List<String> tail, Set<String> flagsWithValues) {
  final path = _singleNonFlagOperand(tail, flagsWithValues);
  return path == null ? ParsedCommand(kind: 'unknown', cmd: _shlexJoin(mainCmd)) : _readCommand(mainCmd, path);
}

ParsedCommand _readCommand(List<String> mainCmd, String path) {
  return ParsedCommand(kind: 'read', cmd: _shlexJoin(mainCmd), name: _shortDisplayPath(path), path: path);
}

String? _headTailPath(List<String> tail, {required bool allowPlus}) {
  if (tail.length == 1 && !tail.first.startsWith('-')) return tail.first;
  if (tail.length >= 2) {
    final first = tail.first;
    if (first == '-n') {
      final value = tail[1];
      final numeric = allowPlus && value.startsWith('+') ? value.substring(1) : value;
      if (int.tryParse(numeric) != null) return _firstNonFlag(tail.skip(2));
    }
    if (first.startsWith('-n')) {
      final value = first.substring(2);
      final numeric = allowPlus && value.startsWith('+') ? value.substring(1) : value;
      if (int.tryParse(numeric) != null) return _firstNonFlag(tail.skip(1));
    }
  }
  return null;
}

List<ParsedCommand> _simplify(List<ParsedCommand> commands) {
  var current = [...commands];
  while (true) {
    final next = _simplifyOnce(current);
    if (next == null) return current;
    current = next;
  }
}

List<ParsedCommand>? _simplifyOnce(List<ParsedCommand> commands) {
  if (commands.length <= 1) return null;
  final first = commands.first;
  if (first.kind == 'unknown') {
    final tokens = _shlexSplit(first.cmd);
    if (tokens.isNotEmpty && tokens.first == 'echo') return commands.sublist(1);
  }
  for (final item in commands.indexed) {
    final command = item.$2;
    if (command.kind != 'unknown') continue;
    final tokens = _shlexSplit(command.cmd);
    if (tokens.isNotEmpty && tokens.first == 'cd' && commands.length > item.$1 + 1) {
      return [...commands.take(item.$1), ...commands.skip(item.$1 + 1)];
    }
  }
  for (final item in commands.indexed) {
    final command = item.$2;
    if (command.kind == 'unknown' && command.cmd == 'true') return [...commands.take(item.$1), ...commands.skip(item.$1 + 1)];
  }
  for (final item in commands.indexed) {
    final command = item.$2;
    if (command.kind != 'unknown') continue;
    final tokens = _shlexSplit(command.cmd);
    if (tokens.isNotEmpty && tokens.first == 'nl' && tokens.skip(1).every((token) => token.startsWith('-'))) {
      return [...commands.take(item.$1), ...commands.skip(item.$1 + 1)];
    }
  }
  return null;
}

ParsedCommand _withCwd(ParsedCommand command, String? cwd) {
  if (cwd == null || command.kind != 'read' || command.path == null) return command;
  return ParsedCommand(
    kind: command.kind,
    cmd: command.cmd,
    name: command.name,
    path: _joinPaths(cwd, command.path!),
    query: command.query,
  );
}

String _joinPaths(String? base, String rel) {
  if (_isAbsLike(rel)) return rel;
  if (base == null || base.isEmpty) return rel;
  return p.posix.join(base, rel);
}

bool _isAbsLike(String path) {
  return p.isAbsolute(path) || RegExp(r'^[A-Za-z]:\\').hasMatch(path) || path.startsWith(r'\\');
}

bool _scriptContainsSedN(List<String> tokens) {
  for (var index = 0; index < tokens.length - 1; index += 1) {
    if (tokens[index] == 'sed' && tokens[index + 1] == '-n') return true;
  }
  return false;
}

List<String> _toolLogLines(List<String> logs) {
  final lines = <String>[];
  for (final log in logs) {
    for (final line in const LineSplitter().convert(log)) {
      final stripped = line.trim();
      if (stripped.isNotEmpty) lines.add(stripped);
    }
  }
  return lines;
}

List<String> _trailingLogLines(List<String> lines, int limit) {
  if (limit <= 0) return <String>[];
  if (lines.length <= limit) return lines.toList();
  return lines.sublist(lines.length - limit);
}

ToolCallHeadline _logHeadline(String line) {
  final normalized = line.trim();
  if (_looksLikePathOnlyLogLine(normalized)) {
    return ToolCallHeadline(action: 'Output:', rest: normalized, detailLanguageOrFilename: normalized);
  }
  final trailingFilename = _trailingResolvedFilename(normalized);
  if (trailingFilename != null) {
    final action = normalized.substring(0, normalized.length - trailingFilename.length).trimRight();
    if (action.isNotEmpty) {
      return ToolCallHeadline(action: action, rest: trailingFilename, detailLanguageOrFilename: trailingFilename);
    }
  }
  return ToolCallHeadline(action: normalized);
}

String? _trailingResolvedFilename(String line) {
  final match = RegExp(r'(\S+)$').firstMatch(line);
  if (match == null) return null;
  final value = match.group(1);
  if (value == null || value.trim().isEmpty) return null;
  final filename = value.replaceFirst(RegExp(r'[,.;:]+$'), '');
  if (filename.isEmpty || resolveLanguageIdForFilename(filename) == null) return null;
  return filename;
}

bool _looksLikePathOnlyLogLine(String line) {
  if (line.isEmpty || line.contains(' ')) {
    return false;
  }
  return line.startsWith('/') || line.startsWith('./') || line.startsWith('../') || line.startsWith('~/');
}

bool _logLinesLookLikeTraceback(List<String> lines) {
  if (lines.any((line) => line.startsWith('Traceback (most recent call last):'))) return true;
  final hasFrame = lines.any((line) => line.startsWith('File "') || line.startsWith('File '));
  final hasException = lines.any(
    (line) => line.contains('Exception:') || line.endsWith('Exception') || line.endsWith('Error') || line.contains('Error:'),
  );
  return hasFrame && hasException;
}

String? _toolErrorLine(String? errorMessage) {
  if (errorMessage == null) return null;
  final lines = const LineSplitter().convert(errorMessage).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  if (lines.isEmpty) return null;
  final lastLine = lines.last;
  final separator = lastLine.indexOf(': ');
  if (separator != -1) {
    final prefix = lastLine.substring(0, separator);
    final message = lastLine.substring(separator + 2);
    if (prefix.contains('.') || prefix.endsWith('Error') || prefix.endsWith('Exception')) {
      return message.trim().isEmpty ? lastLine : message.trim();
    }
  }
  return lastLine;
}
