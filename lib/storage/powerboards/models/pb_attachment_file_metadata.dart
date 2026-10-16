import 'package:flutter/material.dart';

import '../theme/pb_colors.dart';

enum PbAttachmentCategory { generic, businessDocument, code, media, archive, transcript, thread }

enum PbAttachmentFileType {
  generic,
  folder,
  pdf,
  archive,
  type,
  widget,
  mediaGeneric,
  image,
  video,
  sound,
  music,
  businessGeneric,
  spreadsheet,
  document,
  presentation,
  codeGeneric,
  script,
  code,
  key,
  settings,
  transcript,
  thread,
}

enum PbAttachmentPreviewState { none, unavailable, unsupported }

class PbResolvedAttachmentMetadata {
  const PbResolvedAttachmentMetadata({required this.displayTitle, required this.displayType, required this.fileType});

  factory PbResolvedAttachmentMetadata.resolve({
    required String title,
    String descriptor = '',
    PbAttachmentFileType? explicitFileType,
    String? explicitFileTypeKey,
  }) {
    final resolvedFileType =
        explicitFileType ??
        PbAttachmentFileTypeRules.tryParse(explicitFileTypeKey) ??
        PbAttachmentFileTypeRules.infer(title: title, descriptor: descriptor);

    return PbResolvedAttachmentMetadata(
      displayTitle: PbAttachmentFileTypeRules.displayTitleFor(title: title, fileType: resolvedFileType, descriptor: descriptor),
      displayType: PbAttachmentFileTypeRules.displayTypeFor(title: title, descriptor: descriptor, fileType: resolvedFileType),
      fileType: resolvedFileType,
    );
  }

  final String displayTitle;
  final String displayType;
  final PbAttachmentFileType fileType;

  PbAttachmentCategory get category => fileType.category;
  String get iconAssetName => fileType.iconAssetName;
  Color get iconColor => fileType.iconColor;

  PbAttachmentListItemData toListItemData({
    String? path,
    PbAttachmentPreviewState previewState = PbAttachmentPreviewState.none,
    String sizeLabel = '',
    Object? sourceKey,
    bool isLoading = false,
    bool showAskAgentAction = true,
    bool showSaveCopyAsAction = false,
  }) {
    return PbAttachmentListItemData(
      title: displayTitle,
      subtitle: displayType,
      fileType: fileType,
      path: path,
      previewState: previewState,
      sizeLabel: sizeLabel,
      sourceKey: sourceKey,
      isLoading: isLoading,
      showAskAgentAction: showAskAgentAction,
      showSaveCopyAsAction: showSaveCopyAsAction,
    );
  }
}

extension PbAttachmentFileTypeRules on PbAttachmentFileType {
  static const Set<PbAttachmentFileType> extensionlessAppFileTypes = {PbAttachmentFileType.transcript, PbAttachmentFileType.thread};

  static PbAttachmentFileType? tryParse(String? value) {
    final normalized = _normalizeAttachmentText(value);
    if (normalized.isEmpty) {
      return null;
    }

    final candidates = {normalized, normalized.replaceFirst(RegExp(r'^file[-_\s]+', caseSensitive: false), '')};

    for (final candidate in candidates) {
      for (final fileType in PbAttachmentFileType.values) {
        if (fileType.name == candidate || fileType.name.toLowerCase() == candidate.toLowerCase()) {
          return fileType;
        }
      }

      final compact = candidate
          .replaceAllMapped(RegExp(r'[-_\s]+([a-zA-Z0-9])'), (match) {
            return match.group(1)!.toUpperCase();
          })
          .replaceFirstMapped(RegExp(r'^[A-Z]'), (match) {
            return match.group(0)!.toLowerCase();
          });

      for (final fileType in PbAttachmentFileType.values) {
        if (fileType.name == compact) {
          return fileType;
        }
      }
    }

    return null;
  }

  static PbAttachmentFileType infer({required String title, String descriptor = ''}) {
    final extension = _fileExtension(title);
    final normalizedDescriptor = _normalizeAttachmentText(descriptor).toLowerCase();

    if (extension == 'thread' || normalizedDescriptor == 'thread') {
      return PbAttachmentFileType.thread;
    }

    if (extension == 'transcript') {
      return PbAttachmentFileType.transcript;
    }

    if (extension == 'widget' || normalizedDescriptor == 'widget') {
      return PbAttachmentFileType.widget;
    }

    if (extension == 'document') {
      return PbAttachmentFileType.document;
    }

    if (extension == 'presentation') {
      return PbAttachmentFileType.presentation;
    }

    if (extension == 'gallery') {
      return PbAttachmentFileType.image;
    }

    if (extension == 'form') {
      return PbAttachmentFileType.document;
    }

    if (['zip', 'rar', '7z', 'tar', 'gz', 'tgz'].contains(extension)) {
      return PbAttachmentFileType.archive;
    }

    if (['png', 'jpg', 'jpeg', 'jfif', 'gif', 'webp', 'svg', 'svgz', 'heic', 'heif', 'tif', 'tiff', 'bmp'].contains(extension)) {
      return PbAttachmentFileType.image;
    }

    if (['mov', 'mp4', 'm4v', 'webm', 'avi', 'mkv'].contains(extension)) {
      return PbAttachmentFileType.video;
    }

    if (['m4a', 'wav', 'aac', 'ogg'].contains(extension)) {
      return PbAttachmentFileType.sound;
    }

    if (['mp3', 'flac'].contains(extension)) {
      return PbAttachmentFileType.music;
    }

    if (['csv', 'xls', 'xlsx', 'numbers', 'gsheet'].contains(extension)) {
      return PbAttachmentFileType.spreadsheet;
    }

    if (normalizedDescriptor.contains('spreadsheet') || normalizedDescriptor.contains('sheet')) {
      return PbAttachmentFileType.spreadsheet;
    }

    if (['ppt', 'pptx', 'gslides'].contains(extension)) {
      return PbAttachmentFileType.presentation;
    }

    if (normalizedDescriptor.contains('presentation') || normalizedDescriptor.contains('slide')) {
      return PbAttachmentFileType.presentation;
    }

    if (extension == 'pdf' || normalizedDescriptor == 'pdf') {
      return PbAttachmentFileType.pdf;
    }

    if ([
      'json',
      'yaml',
      'yml',
      'js',
      'mjs',
      'cjs',
      'ts',
      'tsx',
      'jsx',
      'dart',
      'html',
      'css',
      'scss',
      'sass',
      'less',
      'sh',
      'bash',
      'zsh',
      'py',
      'rb',
      'java',
      'go',
      'rs',
      'c',
      'cc',
      'cpp',
      'h',
      'hpp',
      'cs',
      'php',
      'swift',
      'kt',
      'kts',
      'sql',
      'xml',
      'toml',
      'ini',
    ].contains(extension)) {
      return extension == 'sh' ? PbAttachmentFileType.script : PbAttachmentFileType.code;
    }

    if (['env', 'pem', 'key', 'crt'].contains(extension)) {
      return PbAttachmentFileType.key;
    }

    if (['srt', 'vtt'].contains(extension) || normalizedDescriptor.contains('caption') || normalizedDescriptor.contains('transcript')) {
      return PbAttachmentFileType.transcript;
    }

    if (['doc', 'docx', 'pages', 'rtf', 'txt', 'md', 'gdoc'].contains(extension) ||
        ['document', 'markdown', 'text', 'rich text', 'meeting note', 'google doc', 'google docs'].contains(normalizedDescriptor)) {
      return PbAttachmentFileType.document;
    }

    if (normalizedDescriptor.contains('audio')) {
      return PbAttachmentFileType.sound;
    }

    if (normalizedDescriptor.contains('video')) {
      return PbAttachmentFileType.video;
    }

    if (normalizedDescriptor.contains('image')) {
      return PbAttachmentFileType.image;
    }

    if (normalizedDescriptor.contains('archive')) {
      return PbAttachmentFileType.archive;
    }

    if (normalizedDescriptor.contains('folder') || normalizedDescriptor.contains('directory')) {
      return PbAttachmentFileType.folder;
    }

    if (normalizedDescriptor.contains('json') || normalizedDescriptor.contains('yaml')) {
      return PbAttachmentFileType.code;
    }

    return PbAttachmentFileType.generic;
  }

  static String displayTitleFor({required String title, required PbAttachmentFileType fileType, String descriptor = ''}) {
    final normalizedTitle = _normalizeAttachmentText(title);
    if (normalizedTitle.isEmpty) {
      return '';
    }

    final descriptorFileType = PbAttachmentFileTypeRules.tryParse(descriptor);
    final descriptorKey = descriptorFileType ?? _descriptorAppFileType(descriptor);
    final shouldStripExtension =
        extensionlessAppFileTypes.contains(fileType) || (descriptorKey != null && extensionlessAppFileTypes.contains(descriptorKey));

    return shouldStripExtension ? normalizedTitle.replaceFirst(RegExp(r'\.[a-z0-9]{1,12}$', caseSensitive: false), '') : normalizedTitle;
  }

  static String displayTypeFor({required String title, required String descriptor, required PbAttachmentFileType fileType}) {
    final normalizedDescriptor = _normalizeAttachmentText(descriptor);
    if (normalizedDescriptor.isNotEmpty) {
      return normalizedDescriptor;
    }

    return _displayTypeFromExtension(_fileExtension(title)) ?? fileType.defaultDisplayLabel;
  }

  PbAttachmentCategory get category {
    return switch (this) {
      PbAttachmentFileType.generic => PbAttachmentCategory.generic,
      PbAttachmentFileType.folder ||
      PbAttachmentFileType.pdf ||
      PbAttachmentFileType.businessGeneric ||
      PbAttachmentFileType.spreadsheet ||
      PbAttachmentFileType.document ||
      PbAttachmentFileType.presentation => PbAttachmentCategory.businessDocument,
      PbAttachmentFileType.archive || PbAttachmentFileType.type => PbAttachmentCategory.archive,
      PbAttachmentFileType.transcript || PbAttachmentFileType.widget => PbAttachmentCategory.transcript,
      PbAttachmentFileType.thread => PbAttachmentCategory.thread,
      PbAttachmentFileType.mediaGeneric ||
      PbAttachmentFileType.image ||
      PbAttachmentFileType.video ||
      PbAttachmentFileType.sound ||
      PbAttachmentFileType.music => PbAttachmentCategory.media,
      PbAttachmentFileType.codeGeneric ||
      PbAttachmentFileType.script ||
      PbAttachmentFileType.code ||
      PbAttachmentFileType.key ||
      PbAttachmentFileType.settings => PbAttachmentCategory.code,
    };
  }

  String get iconAssetName {
    return switch (this) {
      PbAttachmentFileType.generic => 'file',
      PbAttachmentFileType.folder => 'folder',
      PbAttachmentFileType.pdf => 'file',
      PbAttachmentFileType.archive => 'file-archive',
      PbAttachmentFileType.type => 'file-type-corner',
      PbAttachmentFileType.widget => 'file-cog',
      PbAttachmentFileType.mediaGeneric => 'file',
      PbAttachmentFileType.image => 'file-image',
      PbAttachmentFileType.video => 'file-video-camera',
      PbAttachmentFileType.sound => 'file-volume',
      PbAttachmentFileType.music => 'file-music',
      PbAttachmentFileType.businessGeneric => 'file',
      PbAttachmentFileType.spreadsheet => 'file-spreadsheet',
      PbAttachmentFileType.document => 'file-text',
      PbAttachmentFileType.presentation => 'file-chart-pie',
      PbAttachmentFileType.codeGeneric => 'file',
      PbAttachmentFileType.script => 'file-braces-corner',
      PbAttachmentFileType.code => 'file-code-corner',
      PbAttachmentFileType.key => 'file-key',
      PbAttachmentFileType.settings => 'file-cog',
      PbAttachmentFileType.transcript => 'file-play',
      PbAttachmentFileType.thread => 'file-thread',
    };
  }

  Color get iconColor {
    if (this == PbAttachmentFileType.folder) {
      return PbColors.surfaceRailActive;
    }

    return switch (category) {
      PbAttachmentCategory.generic => PbColors.customGray,
      PbAttachmentCategory.businessDocument => PbColors.customBlue,
      PbAttachmentCategory.code => PbColors.customViolet,
      PbAttachmentCategory.media => PbColors.customTeal,
      PbAttachmentCategory.archive => PbColors.customAmber,
      PbAttachmentCategory.transcript => PbColors.customRose,
      PbAttachmentCategory.thread => PbColors.customRose,
    };
  }

  String get defaultDisplayLabel {
    return switch (this) {
      PbAttachmentFileType.generic => 'File',
      PbAttachmentFileType.folder => 'Folder',
      PbAttachmentFileType.pdf => 'PDF',
      PbAttachmentFileType.archive => 'Archive',
      PbAttachmentFileType.type => 'Type',
      PbAttachmentFileType.widget => 'Widget',
      PbAttachmentFileType.mediaGeneric => 'Media',
      PbAttachmentFileType.image => 'Image',
      PbAttachmentFileType.video => 'Video',
      PbAttachmentFileType.sound => 'Audio',
      PbAttachmentFileType.music => 'Music',
      PbAttachmentFileType.businessGeneric => 'File',
      PbAttachmentFileType.spreadsheet => 'Spreadsheet',
      PbAttachmentFileType.document => 'Document',
      PbAttachmentFileType.presentation => 'Presentation',
      PbAttachmentFileType.codeGeneric => 'Code',
      PbAttachmentFileType.script => 'Script',
      PbAttachmentFileType.code => 'Code',
      PbAttachmentFileType.key => 'Key',
      PbAttachmentFileType.settings => 'Settings',
      PbAttachmentFileType.transcript => 'Transcript',
      PbAttachmentFileType.thread => 'Thread',
    };
  }
}

class PbAttachmentListItemData {
  const PbAttachmentListItemData({
    required this.title,
    required this.subtitle,
    required this.fileType,
    this.path,
    this.previewState = PbAttachmentPreviewState.none,
    this.sizeLabel = '',
    this.sourceKey,
    this.isLoading = false,
    this.showAskAgentAction = true,
    this.showSaveCopyAsAction = false,
  });

  factory PbAttachmentListItemData.fromFileName({
    required String title,
    String subtitle = '',
    String? path,
    PbAttachmentFileType? fileType,
    String? fileTypeKey,
    PbAttachmentPreviewState previewState = PbAttachmentPreviewState.none,
    String sizeLabel = '',
    Object? sourceKey,
    bool isLoading = false,
    bool showAskAgentAction = true,
    bool showSaveCopyAsAction = false,
  }) {
    return PbResolvedAttachmentMetadata.resolve(
      title: title,
      descriptor: subtitle,
      explicitFileType: fileType,
      explicitFileTypeKey: fileTypeKey,
    ).toListItemData(
      path: path,
      previewState: previewState,
      sizeLabel: sizeLabel,
      sourceKey: sourceKey,
      isLoading: isLoading,
      showAskAgentAction: showAskAgentAction,
      showSaveCopyAsAction: showSaveCopyAsAction,
    );
  }

  final String title;
  final String subtitle;
  final PbAttachmentFileType fileType;
  final String? path;
  final PbAttachmentPreviewState previewState;
  final String sizeLabel;
  final Object? sourceKey;
  final bool isLoading;
  final bool showAskAgentAction;
  final bool showSaveCopyAsAction;

  PbAttachmentCategory get category => fileType.category;

  String get iconAssetName => fileType.iconAssetName;

  Color get iconColor => fileType.iconColor;
}

String _normalizeAttachmentText(String? value) {
  return (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _fileExtension(String title) {
  final match = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(title.trim().toLowerCase());
  return match?.group(1) ?? '';
}

PbAttachmentFileType? _descriptorAppFileType(String descriptor) {
  final normalizedDescriptor = _normalizeAttachmentText(descriptor).toLowerCase();
  return switch (normalizedDescriptor) {
    'transcript' => PbAttachmentFileType.transcript,
    'thread' => PbAttachmentFileType.thread,
    'widget' => PbAttachmentFileType.widget,
    _ => null,
  };
}

String? _displayTypeFromExtension(String extension) {
  return switch (extension) {
    'gdoc' => 'Google Doc',
    'gsheet' => 'Google Sheet',
    'gslides' => 'Google Slides',
    'md' => 'Markdown',
    'txt' => 'Text',
    'rtf' => 'Rich text',
    'csv' || 'xls' || 'xlsx' || 'numbers' => 'Spreadsheet',
    'pdf' => 'PDF',
    'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'tgz' => 'Archive',
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' || 'heic' => 'Image',
    'mov' || 'mp4' || 'webm' || 'avi' || 'mkv' => 'Video',
    'm4a' || 'wav' || 'aac' || 'ogg' => 'Audio',
    'mp3' || 'flac' => 'Music',
    'ppt' || 'pptx' => 'Presentation',
    'json' => 'JSON',
    'yaml' || 'yml' => 'YAML',
    'js' => 'JavaScript',
    'ts' => 'TypeScript',
    'tsx' => 'TSX',
    'jsx' => 'JSX',
    'dart' => 'Dart',
    'html' => 'HTML',
    'css' => 'CSS',
    'sh' => 'Script',
    'env' || 'pem' || 'key' => 'Key',
    'crt' => 'Certificate',
    'srt' || 'vtt' || 'transcript' => 'Transcript',
    'thread' => 'Thread',
    'widget' => 'Widget',
    'document' => 'Document',
    'presentation' => 'Presentation',
    'gallery' => 'Gallery',
    'form' => 'Form',
    _ => null,
  };
}
