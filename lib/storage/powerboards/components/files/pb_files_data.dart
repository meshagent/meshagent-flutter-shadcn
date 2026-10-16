import 'package:flutter/material.dart' show Color;

import '../../models/pb_attachment_file_metadata.dart';
import '../../theme/pb_colors.dart';

typedef PbFilesLinkedThreadHandler = void Function(PbFilesItemData file, String thread);

enum PbFilesSortKey {
  updated('updated', 'Last updated'),
  name('name', 'Name'),
  type('type', 'Type'),
  size('size', 'Size'),
  thread('thread', 'Linked thread'),
  creator('creator', 'Created by');

  const PbFilesSortKey(this.id, this.label);

  final String id;
  final String label;
}

enum PbFilesItemKind { file, folder, processing, processingError }

class PbFilesItemData {
  const PbFilesItemData({
    required this.id,
    required this.title,
    required this.type,
    this.sizeLabel = '',
    this.sizeSort = 0,
    required this.thread,
    this.linkedThreads = const [],
    required this.creator,
    required this.creatorInitials,
    required this.updatedLabel,
    required this.updatedSort,
    required this.parentPath,
    this.path,
    this.folderPath = '',
    required this.fileType,
    this.kind = PbFilesItemKind.file,
    this.previewState = PbAttachmentPreviewState.none,
    this.iconAssetNameOverride,
    this.iconColorOverride,
    this.renameActionLabelOverride,
  });

  factory PbFilesItemData.fromFileName({
    required String id,
    required String title,
    String type = '',
    String sizeLabel = '',
    int sizeSort = 0,
    required String thread,
    List<String> linkedThreads = const [],
    required String creator,
    required String creatorInitials,
    required String updatedLabel,
    required int updatedSort,
    required String parentPath,
    String? path,
    String folderPath = '',
    PbAttachmentFileType? fileType,
    String? fileTypeKey,
    PbFilesItemKind kind = PbFilesItemKind.file,
    PbAttachmentPreviewState previewState = PbAttachmentPreviewState.none,
  }) {
    final resolved = PbResolvedAttachmentMetadata.resolve(
      title: title,
      descriptor: type,
      explicitFileType: kind == PbFilesItemKind.folder ? PbAttachmentFileType.folder : fileType,
      explicitFileTypeKey: fileTypeKey,
    );

    return PbFilesItemData(
      id: id,
      title: resolved.displayTitle,
      type: resolved.displayType,
      sizeLabel: sizeLabel,
      sizeSort: sizeSort,
      thread: thread,
      linkedThreads: linkedThreads,
      creator: creator,
      creatorInitials: creatorInitials,
      updatedLabel: updatedLabel,
      updatedSort: updatedSort,
      parentPath: parentPath,
      path: path,
      folderPath: folderPath,
      fileType: resolved.fileType,
      kind: kind,
      previewState: previewState,
    );
  }

  final String id;
  final String title;
  final String type;
  final String sizeLabel;
  final int sizeSort;
  final String thread;
  final List<String> linkedThreads;
  final String creator;
  final String creatorInitials;
  final String updatedLabel;
  final int updatedSort;
  final String parentPath;
  final String? path;
  final String folderPath;
  final PbAttachmentFileType fileType;
  final PbFilesItemKind kind;
  final PbAttachmentPreviewState previewState;
  final String? iconAssetNameOverride;
  final Color? iconColorOverride;
  final String? renameActionLabelOverride;

  PbFilesItemData copyWith({
    String? id,
    String? title,
    String? type,
    String? sizeLabel,
    int? sizeSort,
    String? thread,
    List<String>? linkedThreads,
    String? creator,
    String? creatorInitials,
    String? updatedLabel,
    int? updatedSort,
    String? parentPath,
    String? path,
    String? folderPath,
    PbAttachmentFileType? fileType,
    PbFilesItemKind? kind,
    PbAttachmentPreviewState? previewState,
    String? iconAssetNameOverride,
    Color? iconColorOverride,
    String? renameActionLabelOverride,
  }) {
    return PbFilesItemData(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      sizeSort: sizeSort ?? this.sizeSort,
      thread: thread ?? this.thread,
      linkedThreads: linkedThreads ?? this.linkedThreads,
      creator: creator ?? this.creator,
      creatorInitials: creatorInitials ?? this.creatorInitials,
      updatedLabel: updatedLabel ?? this.updatedLabel,
      updatedSort: updatedSort ?? this.updatedSort,
      parentPath: parentPath ?? this.parentPath,
      path: path ?? this.path,
      folderPath: folderPath ?? this.folderPath,
      fileType: fileType ?? this.fileType,
      kind: kind ?? this.kind,
      previewState: previewState ?? this.previewState,
      iconAssetNameOverride: iconAssetNameOverride ?? this.iconAssetNameOverride,
      iconColorOverride: iconColorOverride ?? this.iconColorOverride,
      renameActionLabelOverride: renameActionLabelOverride ?? this.renameActionLabelOverride,
    );
  }

  bool get canPreview => kind == PbFilesItemKind.file;

  List<String> get linkedThreadTargets {
    final rawThreads = linkedThreads.isNotEmpty ? linkedThreads : [thread];
    final seen = <String>{};
    final normalized = <String>[];

    for (final rawThread in rawThreads) {
      final value = rawThread.trim();
      final key = value.toLowerCase();
      if (value.isEmpty || seen.contains(key)) {
        continue;
      }

      seen.add(key);
      normalized.add(value);
    }

    return normalized;
  }

  String get threadLabel {
    final threads = linkedThreadTargets;
    if (threads.length > 1) {
      return 'Multiple';
    }

    return threads.isEmpty ? '-' : threads.first;
  }

  String get iconAssetName {
    if (iconAssetNameOverride != null) {
      return iconAssetNameOverride!;
    }

    if (kind == PbFilesItemKind.folder) {
      return 'folder';
    }

    return fileType.iconAssetName;
  }

  Color get iconColor {
    if (iconColorOverride != null) {
      return iconColorOverride!;
    }

    if (kind == PbFilesItemKind.folder) {
      return PbColors.surfaceRailActive;
    }

    return fileType.iconColor;
  }

  String get filterText {
    return [title, type, sizeLabel, ...linkedThreadTargets, creator, updatedLabel].join(' ').toLowerCase();
  }

  String compactMeta({required bool showThread, required bool showCreator}) {
    final parts = <String>[type];
    if (sizeLabel.isNotEmpty && sizeLabel != '-') {
      parts.add(sizeLabel);
    }
    if (showThread && threadLabel != '-') {
      parts.add(threadLabel);
    }
    if (showCreator) {
      parts.add(creator);
    }
    return parts.join(' / ');
  }

  PbAttachmentListItemData toAttachmentData() {
    return PbAttachmentListItemData(
      title: title,
      subtitle: type.isEmpty ? 'File' : type,
      fileType: fileType,
      path: path,
      previewState: previewState,
      sizeLabel: sizeLabel,
    );
  }
}
