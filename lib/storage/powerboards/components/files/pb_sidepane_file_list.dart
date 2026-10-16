import 'package:flutter/material.dart';

import '../../models/pb_attachment_file_metadata.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../menus/pb_sidepane_item_menu.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_file_menus.dart';

const double _sidepaneInlinePadding = 22;
const double _sidepaneScrollTopPadding = 8;
const double _sidepaneScrollBottomPadding = 24;

class PbSidepaneFileListItem {
  const PbSidepaneFileListItem({
    required this.data,
    this.onPressed,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onSaveCopyAs,
  });

  final PbAttachmentListItemData data;
  final VoidCallback? onPressed;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onSaveCopyAs;
}

class PbSidepaneFileEmptyStateData {
  const PbSidepaneFileEmptyStateData({
    required this.title,
    required this.subtitle,
    this.fileType = PbAttachmentFileType.generic,
    this.iconAssetName = 'file',
    this.iconColor = PbColors.textSubtle,
  });

  final String title;
  final String subtitle;
  final PbAttachmentFileType fileType;
  final String iconAssetName;
  final Color iconColor;

  PbAttachmentListItemData get attachmentData {
    return PbAttachmentListItemData(title: title, subtitle: subtitle, fileType: fileType);
  }
}

class PbSidepaneFileList extends StatelessWidget {
  const PbSidepaneFileList({
    super.key,
    required this.files,
    required this.emptyState,
    this.gap = 10,
    this.topPadding = _sidepaneScrollTopPadding,
    this.expand = true,
  });

  final List<PbSidepaneFileListItem> files;
  final PbSidepaneFileEmptyStateData emptyState;
  final double gap;
  final double topPadding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return PbSidepaneFileEmptyState(data: emptyState, gap: gap, topPadding: topPadding, expand: expand);
    }

    return PbSidepaneScrollViewport.separated(
      itemCount: files.length,
      gap: gap,
      topPadding: topPadding,
      expand: expand,
      itemBuilder: (context, index) {
        final file = files[index];
        return PbAttachmentCard(
          data: file.data,
          onPressed: file.onPressed,
          onAskAgent: file.onAskAgent,
          onShare: file.onShare,
          onExtract: file.onExtract,
          onDownload: file.onDownload,
          onSaveCopyAs: file.onSaveCopyAs,
        );
      },
    );
  }
}

class PbSidepaneFileEmptyState extends StatelessWidget {
  const PbSidepaneFileEmptyState({
    super.key,
    required this.data,
    this.gap = 10,
    this.topPadding = _sidepaneScrollTopPadding,
    this.expand = true,
  });

  final PbSidepaneFileEmptyStateData data;
  final double gap;
  final double topPadding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return PbSidepaneScrollViewport.separated(
      itemCount: 1,
      gap: gap,
      topPadding: topPadding,
      expand: expand,
      itemBuilder: (context, index) => PbAttachmentCard(
        data: data.attachmentData,
        emptyState: true,
        emptyIconAssetName: data.iconAssetName,
        emptyIconColor: data.iconColor,
      ),
    );
  }
}

class PbSidepaneScrollViewport extends StatelessWidget {
  const PbSidepaneScrollViewport.separated({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.gap,
    this.controller,
    this.expand = true,
    this.topPadding = _sidepaneScrollTopPadding,
    this.viewportKey,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final ScrollController? controller;
  final bool expand;
  final double topPadding;
  final Key? viewportKey;

  @override
  Widget build(BuildContext context) {
    final viewport = LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth + (_sidepaneInlinePadding * 2);

        return OverflowBox(
          alignment: Alignment.center,
          minWidth: viewportWidth,
          maxWidth: viewportWidth,
          minHeight: constraints.maxHeight,
          maxHeight: constraints.maxHeight,
          child: SizedBox(
            key: viewportKey,
            width: viewportWidth,
            height: constraints.maxHeight,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView.separated(
                controller: controller,
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.fromLTRB(_sidepaneInlinePadding, topPadding, _sidepaneInlinePadding, _sidepaneScrollBottomPadding),
                itemCount: itemCount,
                separatorBuilder: (_, _) => SizedBox(height: gap),
                itemBuilder: itemBuilder,
              ),
            ),
          ),
        );
      },
    );

    return expand ? Expanded(child: viewport) : viewport;
  }
}

class PbAttachmentCard extends StatefulWidget {
  const PbAttachmentCard({
    super.key,
    required this.data,
    this.onPressed,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onSaveCopyAs,
    this.emptyState = false,
    this.emptyIconAssetName = 'file',
    this.emptyIconColor = PbColors.textSubtle,
  });

  final PbAttachmentListItemData data;
  final VoidCallback? onPressed;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onSaveCopyAs;
  final bool emptyState;
  final String emptyIconAssetName;
  final Color emptyIconColor;

  @override
  State<PbAttachmentCard> createState() => _PbAttachmentCardState();
}

class _PbAttachmentCardState extends State<PbAttachmentCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final unavailable = widget.data.previewState == PbAttachmentPreviewState.unavailable;
    final loading = widget.data.isLoading;
    final lifted = !widget.emptyState && _hovered && !_pressed && !_menuOpen;
    final showAction = !widget.emptyState && !unavailable && !loading && (_hovered || _pressed || _menuOpen);
    final iconAssetName = widget.emptyState ? widget.emptyIconAssetName : widget.data.iconAssetName;
    final iconColor = widget.emptyState || unavailable ? PbColors.textSubtle : widget.data.iconColor;

    return MouseRegion(
      cursor: widget.emptyState ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: widget.emptyState ? null : (_) => setState(() => _hovered = true),
      onExit: widget.emptyState
          ? null
          : (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.emptyState ? null : (_) => setState(() => _pressed = true),
        onPointerUp: widget.emptyState ? null : (_) => setState(() => _pressed = false),
        onPointerCancel: widget.emptyState ? null : (_) => setState(() => _pressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.emptyState ? null : widget.onPressed,
          child: Transform.translate(
            offset: Offset(0, lifted ? -1 : 0),
            child: AnimatedContainer(
              duration: _pressed ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.fromLTRB(21, 11, 12, 11),
              decoration: BoxDecoration(
                color: widget.emptyState
                    ? null
                    : _menuOpen
                    ? PbColors.dynamicCustomMenuOpenSurface
                    : _pressed
                    ? PbColors.dynamicCustomStateSelectedSurface
                    : null,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.emptyState
                      ? PbColors.borderSoft.withValues(alpha: 0.92)
                      : _menuOpen
                      ? Colors.transparent
                      : _pressed
                      ? PbColors.dynamicCustomStateSelectedBorder
                      : PbColors.borderSoft,
                ),
                gradient: widget.emptyState
                    ? LinearGradient(
                        colors: [
                          Color.lerp(PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft, 0.08)!,
                          PbColors.dynamicSurfacePanelSoft.withValues(alpha: 0.96),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : _menuOpen || _pressed
                    ? null
                    : LinearGradient(
                        colors: [PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                boxShadow: widget.emptyState
                    ? null
                    : _menuOpen
                    ? null
                    : _pressed
                    ? const [
                        BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.inner),
                      ]
                    : lifted
                    ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
                    : null,
              ),
              child: Row(
                children: [
                  if (loading)
                    Semantics(
                      label: 'Generating image',
                      child: const SizedBox.square(
                        dimension: 28,
                        child: Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2, color: PbColors.textSubtle),
                        ),
                      ),
                    )
                  else
                    PbSvgIcon(assetName: iconAssetName, size: 28, color: iconColor),
                  const SizedBox(width: 23),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.data.title,
                          style: widget.emptyState ? PowerboardsTypography.listEmptyState : PowerboardsTypography.button,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4.5),
                        Text(
                          widget.data.subtitle,
                          style: PowerboardsTypography.textXSmall.copyWith(
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: widget.emptyState ? PbColors.textSubtle : PbColors.textMuted,
                          ),
                          maxLines: widget.emptyState ? 2 : 1,
                          overflow: widget.emptyState ? TextOverflow.visible : TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!widget.emptyState && !unavailable && !loading) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: showAction ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showAction,
                          child: PbSidepaneItemMenu(
                            onOpenChanged: (open) => setState(() => _menuOpen = open),
                            panelBuilder: (closeMenu) => PbFileItemMenu(
                              onOpen: widget.onPressed,
                              onAskAgent: widget.onAskAgent,
                              onExtract: widget.onExtract,
                              onDownload: widget.onDownload,
                              onSaveCopyAs: widget.onSaveCopyAs,
                              onDismiss: closeMenu,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
