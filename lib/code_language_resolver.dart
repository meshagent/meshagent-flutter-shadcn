import 'package:path/path.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/re_highlight.dart';

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
};

const String plaintextLanguageId = 'plaintext';

String _ext(String path) {
  final base = basename(path);
  if (base.isEmpty) return "";
  return base.split(".").last.toLowerCase();
}

String _normalizeLanguageOrFilename(String value) {
  var normalized = basename(value).toLowerCase().trim();
  if (normalized.startsWith('language-')) {
    normalized = normalized.substring('language-'.length);
  }
  if (normalized.isEmpty) {
    return normalized;
  }

  final firstSegment = normalized.split(RegExp(r'[\s{,:;]')).first;
  return firstSegment.trim();
}

String? resolveLanguageIdForFilename(String filename) {
  final base = _normalizeLanguageOrFilename(filename);
  if (base.isEmpty) {
    return null;
  }

  final byNameId = highlightIdByKey[base] ?? base;
  if (builtinAllLanguages.containsKey(byNameId)) {
    return byNameId;
  }

  if (base.startsWith('.env.')) {
    return plaintextLanguageId;
  }
  if (base.startsWith('dockerfile.')) {
    return 'dockerfile';
  }

  final ext = _ext(base);
  if (ext.isEmpty) {
    return null;
  }

  final id = highlightIdByKey[ext] ?? ext;
  if (builtinAllLanguages.containsKey(id)) {
    return id;
  }
  return null;
}

Mode? resolveModeForFilename(String filename) {
  final id = resolveLanguageIdForFilename(filename);
  if (id == null) {
    return null;
  }
  return builtinAllLanguages[id];
}

Mode resolveModeOrPlaintext(String languageOrFilename) {
  return resolveModeForFilename(languageOrFilename) ?? langPlaintext;
}
