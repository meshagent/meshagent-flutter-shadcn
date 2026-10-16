import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pb_attachment_file_metadata.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../dialogs/pb_dialog.dart';
import '../primitives/pb_spinning_icon.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_dialog_file_list.dart';

const String pbArchiveExtractTriggerLabel = 'Extract files into folder';
const String pbArchiveExtractMenuLabel = 'Extract';
const String pbArchiveExtractFallbackSubtitle = 'To preview';

class PbArchiveExtractLimits {
  const PbArchiveExtractLimits._();

  static const int archiveMaxBytes = 100 * 1024 * 1024;
  static const int expandedMaxBytes = 250 * 1024 * 1024;
  static const int fileCountMax = 100;
  static const int folderCountMax = 50;
  static const int folderDepthMax = 6;
  static const int autoPreviewImageMaxBytes = 12 * 1024 * 1024;
  static const int singleFileMaxBytes = 25 * 1024 * 1024;
}

const List<String> pbSupportedArchiveExtractExtensions = ['.tar.gz', '.tgz', '.zip', '.tar'];

bool pbCanExtractArchive(PbAttachmentListItemData file) {
  return file.previewState == PbAttachmentPreviewState.unsupported &&
      pbSupportedArchiveExtractExtensions.any((extension) => file.title.trim().toLowerCase().endsWith(extension));
}

String pbArchiveExtractFolderName(String title) {
  final normalizedTitle = title.trim();
  final lowerTitle = normalizedTitle.toLowerCase();

  for (final extension in pbSupportedArchiveExtractExtensions) {
    if (lowerTitle.endsWith(extension)) {
      return normalizedTitle.substring(0, normalizedTitle.length - extension.length).trim();
    }
  }

  return normalizedTitle.replaceFirst(RegExp(r'\.[a-z0-9]{1,12}$', caseSensitive: false), '');
}

enum PbArchiveInspectionVariant { browsable, overLimit }

class PbArchiveInspectionResult {
  const PbArchiveInspectionResult({
    required this.variant,
    required this.targetFolderName,
    required this.archiveSizeBytes,
    required this.expandedSizeBytes,
    required this.fileCount,
    required this.folderCount,
    required this.maxDepth,
    required this.entries,
    this.firstPreviewPath,
    this.overLimitReason,
  });

  factory PbArchiveInspectionResult.forFile(PbAttachmentListItemData file) {
    final targetFolderName = pbArchiveExtractFolderName(file.title);
    final lowerTitle = file.title.toLowerCase();

    if (lowerTitle.contains('large') || lowerTitle.contains('complex')) {
      return PbArchiveInspectionResult(
        variant: PbArchiveInspectionVariant.overLimit,
        targetFolderName: targetFolderName,
        archiveSizeBytes: 118 * 1024 * 1024,
        expandedSizeBytes: 312 * 1024 * 1024,
        fileCount: 128,
        folderCount: 62,
        maxDepth: 9,
        entries: const [],
        overLimitReason: 'This archive exceeds the preview limits for size and complexity.',
      );
    }

    return PbArchiveInspectionResult(
      variant: PbArchiveInspectionVariant.browsable,
      targetFolderName: targetFolderName,
      archiveSizeBytes: 18 * 1024 * 1024,
      expandedSizeBytes: 68 * 1024 * 1024,
      fileCount: 8,
      folderCount: 2,
      maxDepth: 3,
      firstPreviewPath: 'cover.jpg',
      entries: const [
        PbArchiveExtractEntry.folder('images'),
        PbArchiveExtractEntry.file('cover.jpg', 3984589, PbAttachmentFileType.image),
        PbArchiveExtractEntry.file('brief.pdf', 1468006, PbAttachmentFileType.pdf),
        PbArchiveExtractEntry.file('notes.md', 24576, PbAttachmentFileType.document),
        PbArchiveExtractEntry.file('images/lobby.jpg', 4823449, PbAttachmentFileType.image),
        PbArchiveExtractEntry.file('images/room.jpg', 5347738, PbAttachmentFileType.image),
        PbArchiveExtractEntry.folder('images/reference'),
        PbArchiveExtractEntry.file('images/reference/colors.json', 18432, PbAttachmentFileType.code),
      ],
    );
  }

  final PbArchiveInspectionVariant variant;
  final String targetFolderName;
  final int archiveSizeBytes;
  final int expandedSizeBytes;
  final int fileCount;
  final int folderCount;
  final int maxDepth;
  final List<PbArchiveExtractEntry> entries;
  final String? firstPreviewPath;
  final String? overLimitReason;

  bool get browsable => variant == PbArchiveInspectionVariant.browsable;

  String get summaryLabel {
    return '$fileCount files, $folderCount folders, ${pbFormatBytes(expandedSizeBytes)} expanded';
  }

  String get limitSummaryLabel {
    return '${pbFormatBytes(archiveSizeBytes)} archive, ${pbFormatBytes(expandedSizeBytes)} expanded, '
        '$fileCount files, $folderCount folders, depth $maxDepth.';
  }
}

class PbArchiveExtractEntry {
  const PbArchiveExtractEntry._({required this.path, required this.sizeBytes, required this.fileType, required this.folder});

  const PbArchiveExtractEntry.file(String path, int sizeBytes, PbAttachmentFileType fileType)
    : this._(path: path, sizeBytes: sizeBytes, fileType: fileType, folder: false);

  const PbArchiveExtractEntry.folder(String path) : this._(path: path, sizeBytes: 0, fileType: PbAttachmentFileType.folder, folder: true);

  factory PbArchiveExtractEntry.fromPath({required String path, required int sizeBytes, required bool folder}) {
    if (folder) {
      return PbArchiveExtractEntry.folder(path);
    }
    final metadata = PbResolvedAttachmentMetadata.resolve(title: path);
    return PbArchiveExtractEntry.file(path, sizeBytes, metadata.fileType);
  }

  final String path;
  final int sizeBytes;
  final PbAttachmentFileType fileType;
  final bool folder;

  String get title => path.split('/').last;
  bool get previewable => !folder;
  String get iconAssetName => folder ? 'folder' : fileType.iconAssetName;
  Color get iconColor => folder ? PbColors.surfaceRailActive : fileType.iconColor;

  PbDialogFileListItemData toDialogListItem({int? depthOverride}) {
    return PbDialogFileListItemData(
      id: path,
      title: title,
      iconAssetName: iconAssetName,
      iconColor: iconColor,
      depth: depthOverride ?? path.split('/').where((part) => part.isNotEmpty).length,
      enabled: folder,
    );
  }
}

String pbFormatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  if (bytes >= 1024) {
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }

  return '$bytes B';
}

class PbArchiveExtractPreviewDialog extends StatefulWidget {
  const PbArchiveExtractPreviewDialog({
    super.key,
    required this.file,
    required this.onClose,
    this.onInspect,
    this.onConfirm,
    this.onDownload,
  });

  final PbAttachmentListItemData file;
  final VoidCallback onClose;
  final Future<PbArchiveInspectionResult> Function(PbAttachmentListItemData file)? onInspect;
  final ValueChanged<PbArchiveInspectionResult>? onConfirm;
  final VoidCallback? onDownload;

  @override
  State<PbArchiveExtractPreviewDialog> createState() => _PbArchiveExtractPreviewDialogState();
}

class _PbArchiveExtractPreviewDialogState extends State<PbArchiveExtractPreviewDialog> {
  PbArchiveInspectionResult? _inspection;
  Object? _inspectionError;

  @override
  void initState() {
    super.initState();
    unawaited(_startInspection());
  }

  @override
  void didUpdateWidget(covariant PbArchiveExtractPreviewDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.title != widget.file.title) {
      unawaited(_startInspection());
    }
  }

  Future<void> _startInspection() async {
    setState(() {
      _inspection = null;
      _inspectionError = null;
    });

    try {
      final inspect = widget.onInspect;
      final result = inspect == null
          ? await Future<PbArchiveInspectionResult>.delayed(
              const Duration(milliseconds: 420),
              () => PbArchiveInspectionResult.forFile(widget.file),
            )
          : await inspect(widget.file);
      if (!mounted) {
        return;
      }
      setState(() => _inspection = result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _inspectionError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    final error = _inspectionError;
    final isBrowsable = inspection?.browsable ?? false;

    return PbDialogShell(
      title: widget.file.title,
      subtitle: 'Extract files into folder',
      bodyExpanded: isBrowsable,
      maxWidth: 425,
      maxHeight: 700,
      onClose: widget.onClose,
      body: error != null
          ? _ArchiveExtractError(error: error)
          : inspection == null
          ? const _ArchiveExtractLoading()
          : isBrowsable
          ? _ArchiveExtractBrowsable(inspection: inspection)
          : _ArchiveExtractOverLimit(inspection: inspection),
      actions: inspection == null && error == null
          ? null
          : error != null
          ? _ArchiveExtractDownloadActions(onClose: widget.onClose, onDownload: widget.onDownload)
          : isBrowsable
          ? PbDialogActions(
              secondaryLabel: 'Cancel',
              primaryLabel: 'Extract to folder',
              onSecondaryPressed: widget.onClose,
              onPrimaryPressed: widget.onConfirm == null ? null : () => widget.onConfirm!(inspection!),
            )
          : _ArchiveExtractDownloadActions(onClose: widget.onClose, onDownload: widget.onDownload),
    );
  }
}

class _ArchiveExtractDownloadActions extends StatelessWidget {
  const _ArchiveExtractDownloadActions({required this.onClose, required this.onDownload});

  final VoidCallback onClose;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return PbDialogActions(
      secondaryLabel: 'Cancel',
      primaryLabel: 'Download',
      primaryIconAssetName: 'arrow-down-to-line',
      onSecondaryPressed: onClose,
      onPrimaryPressed: onDownload ?? onClose,
    );
  }
}

class _ArchiveExtractLoading extends StatelessWidget {
  const _ArchiveExtractLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        const PbSpinningIcon(assetName: 'loader-circle', size: 32, color: PbColors.customAmber),
        const SizedBox(height: 18),
        Text(
          'Inspecting archive contents without extracting files.',
          textAlign: TextAlign.center,
          style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted),
        ),
      ],
    );
  }
}

class _ArchiveExtractBrowsable extends StatefulWidget {
  const _ArchiveExtractBrowsable({required this.inspection});

  final PbArchiveInspectionResult inspection;

  @override
  State<_ArchiveExtractBrowsable> createState() => _ArchiveExtractBrowsableState();
}

class _ArchiveExtractBrowsableState extends State<_ArchiveExtractBrowsable> {
  String _currentPath = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArchiveStatsBox(summaryLabel: widget.inspection.summaryLabel),
        const SizedBox(height: 16),
        _ArchiveBreadcrumb(currentPath: _currentPath, onPathPressed: (path) => setState(() => _currentPath = path)),
        const SizedBox(height: 10),
        Expanded(
          child: PbDialogFileList.unframed(
            items: _visibleEntries().map((entry) => entry.toDialogListItem(depthOverride: 1)).toList(growable: false),
            onItemPressed: _selectEntry,
          ),
        ),
      ],
    );
  }

  List<PbArchiveExtractEntry> _visibleEntries() {
    return widget.inspection.entries.where((entry) => _entryParentPath(entry.path) == _currentPath).toList(growable: false);
  }

  void _selectEntry(PbDialogFileListItemData item) {
    final entry = widget.inspection.entries.firstWhere((candidate) => candidate.path == item.id);
    if (entry.folder) {
      setState(() => _currentPath = entry.path);
    }
  }

  String _entryParentPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) {
      return '';
    }
    return parts.take(parts.length - 1).join('/');
  }
}

class _ArchiveExtractOverLimit extends StatelessWidget {
  const _ArchiveExtractOverLimit({required this.inspection});

  final PbArchiveInspectionResult inspection;

  @override
  Widget build(BuildContext context) {
    final notice =
        '${inspection.overLimitReason ?? 'This archive is too large or complex to preview in Powerboards.'} Please download to continue.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [_ArchiveNotice(text: notice)],
    );
  }
}

class _ArchiveExtractError extends StatelessWidget {
  const _ArchiveExtractError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return _ArchiveNotice(text: 'The archive could not be inspected. Please download to continue.');
  }
}

class _ArchiveStatsBox extends StatelessWidget {
  const _ArchiveStatsBox({required this.summaryLabel});

  final String summaryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PbColors.dynamicBorderStateSelected),
        color: PbColors.dynamicSurfaceStateSelected,
      ),
      child: Row(
        children: [
          PbSvgIcon(assetName: 'info', size: 18, color: PbColors.dynamicCustomBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Text(summaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: PowerboardsTypography.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _ArchiveBreadcrumb extends StatelessWidget {
  const _ArchiveBreadcrumb({required this.currentPath, required this.onPathPressed});

  final String currentPath;
  final ValueChanged<String> onPathPressed;

  @override
  Widget build(BuildContext context) {
    final segments = currentPath.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    final visibleSegments = segments.length <= 2 ? segments : ['...', segments.last];

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          _ArchiveBreadcrumbText(
            label: 'Browse',
            active: currentPath.isEmpty,
            onPressed: currentPath.isEmpty ? null : () => onPathPressed(''),
          ),
          for (var index = 0; index < visibleSegments.length; index++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: PbSvgIcon(assetName: 'chevron-right', size: 16, color: PbColors.textSubtle),
            ),
            Flexible(
              flex: index == visibleSegments.length - 1 ? 2 : 1,
              child: _ArchiveBreadcrumbText(
                label: visibleSegments[index],
                active: index == visibleSegments.length - 1,
                onPressed: visibleSegments[index] == '...' || index == visibleSegments.length - 1
                    ? null
                    : () => onPathPressed(segments.take(index + 1).join('/')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchiveBreadcrumbText extends StatefulWidget {
  const _ArchiveBreadcrumbText({required this.label, required this.active, this.onPressed});

  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  State<_ArchiveBreadcrumbText> createState() => _ArchiveBreadcrumbTextState();
}

class _ArchiveBreadcrumbTextState extends State<_ArchiveBreadcrumbText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onPressed != null;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: clickable ? (_) => setState(() => _hovered = true) : null,
      onExit: clickable ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (widget.active ? PowerboardsTypography.labelSmall : PowerboardsTypography.meta).copyWith(
              color: widget.active || _hovered ? PbColors.textPrimary : PbColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveNotice extends StatelessWidget {
  const _ArchiveNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PbColors.dynamicBorderStateSelected),
        color: PbColors.dynamicSurfaceStateSelected,
      ),
      child: Text(text, style: PowerboardsTypography.labelSmall.copyWith(height: 1.45)),
    );
  }
}
