import 'package:flutter/material.dart';

import '../../models/pb_attachment_file_metadata.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_archive_extract.dart';

class PbFilePreviewStateCard extends StatelessWidget {
  const PbFilePreviewStateCard({
    super.key,
    required this.file,
    required this.state,
    this.label,
    this.showExtractArchive = false,
    this.extractArchiveDisabled = false,
    this.onExtractArchive,
  });

  final PbAttachmentListItemData file;
  final PbAttachmentPreviewState state;
  final String? label;
  final bool showExtractArchive;
  final bool extractArchiveDisabled;
  final VoidCallback? onExtractArchive;

  String get _label {
    final customLabel = label;
    if (customLabel != null) {
      return customLabel;
    }

    return switch (state) {
      PbAttachmentPreviewState.unavailable => 'No preview available',
      PbAttachmentPreviewState.unsupported => 'File preview not supported',
      PbAttachmentPreviewState.none => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final canShowArchiveExtract = pbCanExtractArchive(file) && (showExtractArchive || onExtractArchive != null);
    if (canShowArchiveExtract) {
      final enabled = !extractArchiveDisabled && onExtractArchive != null;
      return _ArchiveExtractStateCard(file: file, onPressed: enabled ? onExtractArchive : null);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: PbColors.dynamicSurfacePanel,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(17, 24, 39, 0.03), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PbSvgIcon(assetName: file.iconAssetName, size: 28, color: PbColors.textSubtle),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _label,
              style: PowerboardsTypography.labelSmall.copyWith(color: PbColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveExtractStateCard extends StatefulWidget {
  const _ArchiveExtractStateCard({required this.file, required this.onPressed});

  final PbAttachmentListItemData file;
  final VoidCallback? onPressed;

  @override
  State<_ArchiveExtractStateCard> createState() => _ArchiveExtractStateCardState();
}

class _ArchiveExtractStateCardState extends State<_ArchiveExtractStateCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final lifted = enabled && _hovered && !_pressed;
    final subtitle = widget.file.sizeLabel.trim().isNotEmpty && widget.file.sizeLabel.trim() != '-'
        ? widget.file.sizeLabel.trim()
        : pbArchiveExtractFallbackSubtitle;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onPointerCancel: enabled ? (_) => setState(() => _pressed = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Transform.translate(
            offset: Offset(0, lifted ? -1 : 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: enabled ? 1 : 0.56,
              child: AnimatedContainer(
                duration: _pressed ? Duration.zero : const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                constraints: const BoxConstraints(maxWidth: 360, minHeight: 68),
                padding: const EdgeInsets.fromLTRB(21, 11, 24, 11),
                decoration: BoxDecoration(
                  color: _pressed ? PbColors.dynamicCustomStateSelectedSurface : null,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _pressed ? PbColors.dynamicCustomStateSelectedBorder : PbColors.borderSoft),
                  gradient: _pressed
                      ? null
                      : LinearGradient(
                          colors: [PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                  boxShadow: _pressed
                      ? const [
                          BoxShadow(
                            color: Color.fromRGBO(15, 23, 42, 0.08),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                            blurStyle: BlurStyle.inner,
                          ),
                        ]
                      : lifted
                      ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PbSvgIcon(assetName: 'folder-archive', size: 28, color: enabled ? widget.file.iconColor : PbColors.textSubtle),
                    const SizedBox(width: 23),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pbArchiveExtractTriggerLabel,
                            style: PowerboardsTypography.button.copyWith(color: enabled ? null : PbColors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4.5),
                          Text(
                            subtitle,
                            style: PowerboardsTypography.textXSmall.copyWith(
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: PbColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
