import 'package:flutter/material.dart';

import '../menus/pb_menu_divider.dart';
import '../menus/pb_menu_list.dart';
import '../menus/pb_menu_option.dart';
import 'pb_archive_extract.dart';
import 'pb_files_data.dart';

class PbFileItemMenu extends StatelessWidget {
  const PbFileItemMenu({
    super.key,
    this.onOpen,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onSaveCopyAs,
    this.onDismiss,
  });

  final VoidCallback? onOpen;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onSaveCopyAs;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return PbMenuList(
      children: [
        if (onOpen != null)
          PbMenuOption(
            title: 'Open',
            leadingIconAssetName: 'arrow-up-right',
            singleLine: true,
            onPressed: () => _runMenuAction(onOpen, onDismiss),
          ),
        if (onAskAgent != null)
          PbMenuOption(
            title: 'Ask agent',
            leadingIconAssetName: 'message-square-plus',
            singleLine: true,
            onPressed: () => _runMenuAction(onAskAgent, onDismiss),
          ),
        if (onShare != null)
          PbMenuOption(
            title: 'Share',
            leadingIconAssetName: 'share',
            singleLine: true,
            onPressed: () => _runMenuAction(onShare, onDismiss),
          ),
        if (onExtract != null)
          PbMenuOption(
            title: pbArchiveExtractMenuLabel,
            leadingIconAssetName: 'folder-archive',
            singleLine: true,
            onPressed: () => _runMenuAction(onExtract, onDismiss),
          ),
        if (onDownload != null)
          PbMenuOption(
            title: 'Download',
            leadingIconAssetName: 'arrow-down-to-line',
            singleLine: true,
            onPressed: () => _runMenuAction(onDownload, onDismiss),
          ),
        if (onSaveCopyAs != null)
          PbMenuOption(
            title: 'Save a copy as...',
            leadingIconAssetName: 'folder-symlink',
            singleLine: true,
            onPressed: () => _runMenuAction(onSaveCopyAs, onDismiss),
          ),
      ],
    );
  }
}

class PbFilesRowMenu extends StatelessWidget {
  const PbFilesRowMenu({
    super.key,
    required this.item,
    this.onOpen,
    this.onBrowseFolder,
    this.onRemoveProcessingRow,
    this.onAskAgent,
    this.onShare,
    this.showExtract,
    this.onExtract,
    this.onDownload,
    this.onMoveTo,
    this.onRename,
    this.onDelete,
    this.onDismiss,
  });

  final PbFilesItemData item;
  final VoidCallback? onOpen;
  final VoidCallback? onBrowseFolder;
  final VoidCallback? onRemoveProcessingRow;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final bool? showExtract;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onMoveTo;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final extractVisible = showExtract ?? (onExtract != null && pbCanExtractArchive(item.toAttachmentData()));
    return switch (item.kind) {
      PbFilesItemKind.processing => PbMenuList(
        children: [
          PbMenuOption(
            title: 'Cancel process',
            leadingIconAssetName: 'circle-x',
            singleLine: true,
            onPressed: () => _runMenuAction(onRemoveProcessingRow, onDismiss),
          ),
        ],
      ),
      PbFilesItemKind.processingError => PbMenuList(
        children: [
          PbMenuOption(
            title: 'Delete',
            leadingIconAssetName: 'trash-alert',
            singleLine: true,
            alert: true,
            onPressed: () => _runMenuAction(onRemoveProcessingRow, onDismiss),
          ),
        ],
      ),
      PbFilesItemKind.folder => PbMenuList(
        children: [
          if (onBrowseFolder != null)
            PbMenuOption(
              title: 'Browse folder',
              leadingIconAssetName: 'arrow-up-right',
              singleLine: true,
              onPressed: () => _runMenuAction(onBrowseFolder, onDismiss),
            ),
          if (onAskAgent != null)
            PbMenuOption(
              title: 'Ask agent',
              leadingIconAssetName: 'message-square-plus',
              singleLine: true,
              onPressed: () => _runMenuAction(onAskAgent, onDismiss),
            ),
          if (onDownload != null)
            PbMenuOption(
              title: 'Download as zip',
              leadingIconAssetName: 'arrow-down-to-line',
              singleLine: true,
              onPressed: () => _runMenuAction(onDownload, onDismiss),
            ),
          if (onRename != null || onMoveTo != null || onDelete != null) const PbMenuDivider(),
          if (onRename != null)
            PbMenuOption(
              title: item.renameActionLabelOverride ?? 'Rename',
              leadingIconAssetName: 'text-cursor',
              singleLine: true,
              onPressed: () => _runMenuAction(onRename, onDismiss),
            ),
          if (onMoveTo != null)
            PbMenuOption(
              title: 'Move to...',
              leadingIconAssetName: 'folder-symlink',
              singleLine: true,
              onPressed: () => _runMenuAction(onMoveTo, onDismiss),
            ),
          if (onDelete != null)
            PbMenuOption(
              title: 'Delete',
              leadingIconAssetName: 'trash-alert',
              singleLine: true,
              alert: true,
              onPressed: () => _runMenuAction(onDelete, onDismiss),
            ),
        ],
      ),
      PbFilesItemKind.file => PbMenuList(
        children: [
          if (onOpen != null)
            PbMenuOption(
              title: 'Open',
              leadingIconAssetName: 'arrow-up-right',
              singleLine: true,
              onPressed: () => _runMenuAction(onOpen, onDismiss),
            ),
          if (onAskAgent != null)
            PbMenuOption(
              title: 'Ask agent',
              leadingIconAssetName: 'message-square-plus',
              singleLine: true,
              onPressed: () => _runMenuAction(onAskAgent, onDismiss),
            ),
          if (onShare != null)
            PbMenuOption(
              title: 'Share',
              leadingIconAssetName: 'share',
              singleLine: true,
              onPressed: () => _runMenuAction(onShare, onDismiss),
            ),
          if (extractVisible)
            PbMenuOption(
              title: pbArchiveExtractMenuLabel,
              leadingIconAssetName: 'folder-archive',
              singleLine: true,
              state: onExtract == null ? PbMenuOptionVisualState.disabled : null,
              onPressed: () => _runMenuAction(onExtract, onDismiss),
            ),
          if (onDownload != null)
            PbMenuOption(
              title: 'Download',
              leadingIconAssetName: 'arrow-down-to-line',
              singleLine: true,
              onPressed: () => _runMenuAction(onDownload, onDismiss),
            ),
          if (onRename != null || onMoveTo != null || onDelete != null) const PbMenuDivider(),
          if (onRename != null)
            PbMenuOption(
              title: 'Rename',
              leadingIconAssetName: 'text-cursor',
              singleLine: true,
              onPressed: () => _runMenuAction(onRename, onDismiss),
            ),
          if (onMoveTo != null)
            PbMenuOption(
              title: 'Move to...',
              leadingIconAssetName: 'folder-symlink',
              singleLine: true,
              onPressed: () => _runMenuAction(onMoveTo, onDismiss),
            ),
          if (onDelete != null)
            PbMenuOption(
              title: 'Delete',
              leadingIconAssetName: 'trash-alert',
              singleLine: true,
              alert: true,
              onPressed: () => _runMenuAction(onDelete, onDismiss),
            ),
        ],
      ),
    };
  }
}

class PbFilePreviewPaneOptionsMenu extends StatelessWidget {
  const PbFilePreviewPaneOptionsMenu({
    super.key,
    this.showAskAgent = true,
    this.showShare = true,
    this.showExtract = false,
    this.showDownload = true,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onDismiss,
  });

  final bool showAskAgent;
  final bool showShare;
  final bool showExtract;
  final bool showDownload;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return PbMenuList(
      children: [
        if (showAskAgent)
          PbMenuOption(
            title: 'Ask agent',
            leadingIconAssetName: 'message-square-plus',
            singleLine: true,
            state: onAskAgent == null ? PbMenuOptionVisualState.disabled : null,
            onPressed: () => _runMenuAction(onAskAgent, onDismiss),
          ),
        if (showShare)
          PbMenuOption(
            title: 'Share',
            leadingIconAssetName: 'share',
            singleLine: true,
            state: onShare == null ? PbMenuOptionVisualState.disabled : null,
            onPressed: () => _runMenuAction(onShare, onDismiss),
          ),
        if (showExtract)
          PbMenuOption(
            title: pbArchiveExtractMenuLabel,
            leadingIconAssetName: 'folder-archive',
            singleLine: true,
            state: onExtract == null ? PbMenuOptionVisualState.disabled : null,
            onPressed: () => _runMenuAction(onExtract, onDismiss),
          ),
        if (showDownload)
          PbMenuOption(
            title: 'Download',
            leadingIconAssetName: 'arrow-down-to-line',
            singleLine: true,
            state: onDownload == null ? PbMenuOptionVisualState.disabled : null,
            onPressed: () => _runMenuAction(onDownload, onDismiss),
          ),
      ],
    );
  }
}

void _runMenuAction(VoidCallback? action, VoidCallback? dismiss) {
  action?.call();
  dismiss?.call();
}
