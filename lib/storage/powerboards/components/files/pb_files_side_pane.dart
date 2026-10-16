import 'package:flutter/material.dart';

import '../../models/pb_attachment_file_metadata.dart';
import '../../theme/pb_colors.dart';
import '../layouts/pb_room_panel.dart';
import 'pb_archive_extract.dart';
import 'pb_files_data.dart';
import 'pb_sidepane_file_list.dart';

class PbFilesSidePane extends StatelessWidget {
  const PbFilesSidePane({
    super.key,
    required this.files,
    required this.previewFile,
    required this.fullscreen,
    required this.resizing,
    required this.borderOnTop,
    required this.responsiveOverlay,
    required this.responsiveOverlayMobile,
    required this.onPreviewFile,
    this.previewBuilder,
    this.previewSourceBuilder,
    this.onAskAgent,
    this.onShare,
    this.extractingArchiveIds = const <String>{},
    this.onExtractArchive,
    this.onDownload,
    this.onSaveRequested,
    this.previewDraftText,
    this.previewDraftDirty,
    this.onPreviewDraftChanged,
    this.onPreviewDraftSaved,
    required this.onToggleFullscreen,
    required this.onClosePreview,
  });

  static const _emptyRecentFiles = PbSidepaneFileEmptyStateData(
    title: 'No file history yet',
    subtitle: 'Files you open will appear here.',
    fileType: PbAttachmentFileType.generic,
  );

  final List<PbFilesItemData> files;
  final PbFilesItemData? previewFile;
  final bool fullscreen;
  final bool resizing;
  final bool borderOnTop;
  final bool responsiveOverlay;
  final bool responsiveOverlayMobile;
  final ValueChanged<PbFilesItemData> onPreviewFile;
  final Widget? Function(PbFilesItemData file)? previewBuilder;
  final PbFilePreviewSource? Function(PbFilesItemData file)? previewSourceBuilder;
  final ValueChanged<PbFilesItemData>? onAskAgent;
  final ValueChanged<PbFilesItemData>? onShare;
  final Set<String> extractingArchiveIds;
  final ValueChanged<PbFilesItemData>? onExtractArchive;
  final ValueChanged<PbFilesItemData>? onDownload;
  final Future<void> Function(PbFilesItemData file)? onSaveRequested;
  final String? previewDraftText;
  final bool? previewDraftDirty;
  final ValueChanged<String>? onPreviewDraftChanged;
  final VoidCallback? onPreviewDraftSaved;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClosePreview;

  @override
  Widget build(BuildContext context) {
    final preview = previewFile;
    if (preview != null) {
      final previewExtractable = onExtractArchive != null && pbCanExtractArchive(preview.toAttachmentData());
      final previewExtracting = previewExtractable && extractingArchiveIds.contains(preview.id);
      final previewSource = preview.previewState == PbAttachmentPreviewState.none ? previewSourceBuilder?.call(preview) : null;
      final previewContentChild = previewSource?.buildChild(fullscreen);
      return PbFilePreviewPane(
        file: preview.toAttachmentData(),
        fullscreen: fullscreen,
        resizing: resizing,
        borderOnTop: borderOnTop,
        showInlineBorder: !responsiveOverlay,
        hideFullscreenToggle: responsiveOverlayMobile,
        onAskAgent: onAskAgent == null ? null : () => onAskAgent!(preview),
        onShare: onShare == null ? null : () => onShare!(preview),
        showExtractArchive: previewExtractable,
        extractArchiveDisabled: previewExtracting,
        onExtractArchive: !previewExtractable || previewExtracting ? null : () => onExtractArchive!(preview),
        onDownload: onDownload == null ? null : () => onDownload!(preview),
        onToggleFullscreen: onToggleFullscreen,
        onClose: onClosePreview,
        onSaveRequested: onSaveRequested == null ? null : () => onSaveRequested!(preview),
        previewContentChild: previewContentChild,
        loadText: previewSource?.loadText,
        onSaveTextRequested: previewSource?.saveText,
        sourceKey: previewSource?.sourceKey,
        draftText: previewDraftText,
        draftDirty: previewDraftDirty,
        onDraftTextChanged: onPreviewDraftChanged,
        onDraftSaved: onPreviewDraftSaved,
        child: preview.previewState == PbAttachmentPreviewState.none ? previewBuilder?.call(preview) : null,
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.fromLTRB(22, responsiveOverlay ? 26 : 29, 22, 0),
      decoration: BoxDecoration(
        color: responsiveOverlay ? Colors.transparent : PbColors.surfacePanelWash,
        border: responsiveOverlay
            ? null
            : borderOnTop
            ? const Border(top: BorderSide(color: PbColors.borderSoft))
            : const Border(left: BorderSide(color: PbColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PbStaticRoomTabs(label: 'Recently opened'),
          const SizedBox(height: 16),
          const PbRoomPanelDescription('Your file session history appears here.'),
          const SizedBox(height: 20),
          PbSidepaneFileList(
            files: [
              for (final file in files)
                PbSidepaneFileListItem(
                  data: file.toAttachmentData(),
                  onPressed: () => onPreviewFile(file),
                  onAskAgent: onAskAgent == null ? null : () => onAskAgent!(file),
                  onShare: onShare == null ? null : () => onShare!(file),
                  onExtract:
                      onExtractArchive == null || !pbCanExtractArchive(file.toAttachmentData()) || extractingArchiveIds.contains(file.id)
                      ? null
                      : () => onExtractArchive!(file),
                  onDownload: onDownload == null ? null : () => onDownload!(file),
                ),
            ],
            emptyState: _emptyRecentFiles,
          ),
        ],
      ),
    );
  }
}

extension PbFilesSidePaneOverlay on PbFilesSidePane {
  Widget asOverlayFrame({required bool mobile, required VoidCallback onClose}) {
    return PbResponsiveRoomPanelOverlayFrame(
      mobile: mobile,
      onClose: onClose,
      preview: previewFile == null ? null : this,
      child: previewFile == null ? this : const SizedBox.shrink(),
    );
  }
}
