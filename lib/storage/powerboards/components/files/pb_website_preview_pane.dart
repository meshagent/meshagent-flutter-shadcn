import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_button.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_website_preview_frame.dart';

class PbWebsitePreviewPane extends StatelessWidget {
  const PbWebsitePreviewPane({
    super.key,
    required this.title,
    this.previewHtml,
    this.previewUrl,
    this.onOpenSite,
    this.onDownloadZip,
    this.onClose,
  }) : assert(previewHtml != null || previewUrl != null);

  final String title;
  final String? previewHtml;
  final Uri? previewUrl;
  final VoidCallback? onOpenSite;
  final VoidCallback? onDownloadZip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PbColors.surfacePanelWash,
      child: Column(
        children: [
          Container(
            height: 82,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: const BoxDecoration(
              color: PbColors.surfacePanelWash,
              border: Border(bottom: BorderSide(color: PbColors.borderSoft)),
            ),
            child: Row(
              children: [
                const PbSvgIcon(assetName: 'folder-code', size: 28, color: PbColors.customBrandInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: PowerboardsTypography.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
                PbButton(
                  iconAssetName: 'arrow-up-right',
                  label: 'Go to site',
                  variant: PbButtonVariant.secondary,
                  height: 36,
                  horizontalPadding: 16,
                  iconGap: 10,
                  onPressed: onOpenSite,
                ),
                const SizedBox(width: 8),
                PbButton(
                  iconAssetName: 'arrow-down-to-line',
                  label: 'Download as ZIP',
                  variant: PbButtonVariant.secondary,
                  height: 36,
                  horizontalPadding: 16,
                  iconGap: 10,
                  onPressed: onDownloadZip,
                ),
                const SizedBox(width: 10),
                _WebsitePreviewCloseButton(onPressed: onClose),
              ],
            ),
          ),
          Expanded(
            child: PbWebsitePreviewFrame(htmlDocument: previewHtml, url: previewUrl),
          ),
        ],
      ),
    );
  }
}

class _WebsitePreviewCloseButton extends StatefulWidget {
  const _WebsitePreviewCloseButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_WebsitePreviewCloseButton> createState() => _WebsitePreviewCloseButtonState();
}

class _WebsitePreviewCloseButtonState extends State<_WebsitePreviewCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final color = _pressed
        ? PbColors.textPrimary
        : _hovered
        ? PbColors.textPrimary
        : PbColors.textMuted;

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: PbSvgIcon(assetName: 'x', size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
