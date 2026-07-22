import "package:flutter/material.dart";
import "package:meshagent_flutter_shadcn/file_preview/code.dart";
import "package:meshagent_flutter_shadcn/code_language_resolver.dart";
import "package:meshagent_flutter_shadcn/thread_typography.dart";
import "package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart";
import "package:path/path.dart";
import "package:shadcn_ui/shadcn_ui.dart";
import "package:url_launcher/url_launcher.dart";
import "package:meshagent/room_server_client.dart";

import "image.dart";
import "pdf.dart";
import "tsv.dart";
import "video.dart";
import "markdown.dart";
import "../chat/chat.dart";

enum FileKind { image, video, audio, pdf, code, parquet, office, markdown, thread, lance, tsv, custom, unknown }

final imageExtensions = <String>{"png", "jpg", "jpeg", "jfif", "heic", "heif", "webp", "tif", "tiff", "gif", "svg", "bmp"};
final pdfExtensions = <String>{"pdf"};
final markdownExtensions = <String>{"md"};
final threadExtensions = <String>{"thread"};
final lanceExtensions = <String>{"lance", "table"};
final videoExtensions = <String>{"mp4", "mkv", "mov"};
final audioExtensions = <String>{"mp3", "ogg", "wav"};
final officeExtensions = <String>{"docx", "pptx", "xlsx"};
final parquetExtensions = <String>{"parquet"};
final tsvExtensions = <String>{"tsv"};
const double _mobilePreviewScreenWidthMax = 600;

bool _usesMobilePreviewLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width < _mobilePreviewScreenWidthMax;
}

final Map<String, Widget Function({Key? key, required RoomClient room, required String filename, required Uri url})> customViewers = {};

String _ext(String path) {
  final base = basename(path);
  if (base.isEmpty) return "";
  return base.split(".").last.toLowerCase();
}

FileKind classifyFile(String path) {
  final ext = _ext(path);
  if (markdownExtensions.contains(ext)) return FileKind.markdown;
  if (threadExtensions.contains(ext)) return FileKind.thread;
  if (lanceExtensions.contains(ext)) return FileKind.lance;
  if (tsvExtensions.contains(ext)) return FileKind.tsv;
  if (customViewers.containsKey(ext)) return FileKind.custom;
  if (imageExtensions.contains(ext)) return FileKind.image;
  if (videoExtensions.contains(ext)) return FileKind.video;
  if (audioExtensions.contains(ext)) return FileKind.audio;
  if (pdfExtensions.contains(ext)) return FileKind.pdf;
  if (parquetExtensions.contains(ext)) return FileKind.parquet;
  if (officeExtensions.contains(ext)) return FileKind.office;

  final base = basename(path).toLowerCase();
  if (base == 'readme' || base == 'readme.txt') return FileKind.markdown;
  if (resolveLanguageIdForFilename(path) != null) return FileKind.code;
  if (isCodeFile(path)) return FileKind.code;

  return FileKind.unknown;
}

bool filePreviewLoadsFromRoomStorage(String path) {
  return switch (classifyFile(path)) {
    FileKind.markdown || FileKind.pdf || FileKind.code || FileKind.tsv => true,
    _ => false,
  };
}

Widget filePreview({Key? key, required RoomClient room, required String filename, required Uri url, BoxFit fit = BoxFit.cover}) {
  final kind = classifyFile(filename);

  switch (kind) {
    case FileKind.markdown:
      return MarkdownPreview(filename: filename, room: room, key: key);
    case FileKind.thread:
      return Text(url.pathSegments.last);
    case FileKind.lance:
      return const Center(child: Text("File preview not supported"));
    case FileKind.image:
      return ImagePreview(url: url, key: key, fit: fit);
    case FileKind.video:
      return VideoPreview(url: url, key: key, fit: fit);
    case FileKind.audio:
      return AudioPreview(url: url, key: key);
    case FileKind.pdf:
      return PdfPreview(room: room, path: filename, key: key);
    case FileKind.tsv:
      return TsvPreview(filename: filename, room: room, key: key);
    case FileKind.code:
      return CodePreview(room: room, filename: filename, url: url, key: key);
    case FileKind.custom:
      final ext = _ext(filename);
      return customViewers[ext]!(key: key, room: room, filename: filename, url: url);
    case FileKind.parquet:
    case FileKind.office:
    case FileKind.unknown:
      return Text(url.pathSegments.last);
  }
}

class FilePreview extends StatefulWidget {
  FilePreview({required this.room, required this.path, this.fit = BoxFit.cover}) : super(key: Key(path));

  final String path;
  final RoomClient room;
  final BoxFit fit;

  @override
  State createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  late final Future<String> urlLookup = widget.room.storage.downloadUrl(widget.path);

  Widget? _buildStorageBackedPreview() {
    final kind = classifyFile(widget.path);
    return switch (kind) {
      FileKind.markdown => MarkdownPreview(filename: widget.path, room: widget.room),
      FileKind.pdf => PdfPreview(room: widget.room, path: widget.path),
      FileKind.code => CodePreview(room: widget.room, filename: widget.path),
      FileKind.tsv => TsvPreview(filename: widget.path, room: widget.room),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Text/code-like previews load directly from room storage, so they should
    // not block on signed download URL generation.
    if (filePreviewLoadsFromRoomStorage(widget.path)) {
      final storageBackedPreview = _buildStorageBackedPreview();
      if (storageBackedPreview == null) {
        return ColoredBox(color: ShadTheme.of(context).colorScheme.background);
      }
      return storageBackedPreview;
    }

    return FutureBuilder(
      future: urlLookup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final preview = filePreview(room: widget.room, filename: widget.path, url: Uri.parse(snapshot.data!), fit: widget.fit);
          if (_usesMobilePreviewLayout(context)) {
            return preview;
          }

          return CoordinatedShadContextMenuRegion(
            items: [
              ShadContextMenuItem(
                trailing: Icon(LucideIcons.download),
                onPressed: () {
                  launchUrl(Uri.parse(snapshot.data!));
                },
                child: Text("Download"),
              ),
            ],
            child: preview,
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Unable to load file preview: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: threadTypographyTextStyle(context, TextStyle(color: ShadTheme.of(context).colorScheme.destructive)),
              ),
            ),
          );
        } else {
          return ColoredBox(color: ShadTheme.of(context).colorScheme.background);
        }
      },
    );
  }
}

class FileDefaultAttachmentPreview extends StatefulWidget {
  const FileDefaultAttachmentPreview({super.key, required this.attachment, required this.onRemove, this.onOpen, this.maxWidth = 200});

  final FileAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  final double maxWidth;

  @override
  State<FileDefaultAttachmentPreview> createState() => _FileDefaultAttachmentPreviewState();
}

class _FileDefaultAttachmentPreviewState extends State<FileDefaultAttachmentPreview> {
  UploadStatus status = UploadStatus.initial;

  void onAttachmentUpdate() {
    final nextStatus = widget.attachment.status;

    if (mounted) {
      if (status != UploadStatus.failed && nextStatus == UploadStatus.failed) {
        final buildContext = this.context;

        ShadToaster.of(buildContext).show(
          ShadToast.destructive(
            title: const Text("Attachment upload failed"),
            description: Text("Unable to upload ${widget.attachment.filename}. Remove it or try again."),
          ),
        );
      }

      setState(() {
        status = nextStatus;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    status = widget.attachment.status;

    widget.attachment.addListener(onAttachmentUpdate);
  }

  @override
  void dispose() {
    super.dispose();

    widget.attachment.removeListener(onAttachmentUpdate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final destructiveColor = theme.colorScheme.destructive;
    final isUploading = status == UploadStatus.initial || status == UploadStatus.uploading;
    final hasFailed = status == UploadStatus.failed;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: isUploading
                  ? CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 2.0)
                  : Center(
                      child: Icon(
                        hasFailed ? LucideIcons.triangleAlert : LucideIcons.file,
                        size: 20,
                        color: hasFailed ? destructiveColor : null,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(widget.attachment.filename, style: ShadTheme.of(context).textTheme.small, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      content = ShadGestureDetector(cursor: SystemMouseCursors.click, onTap: onOpen, child: content);
    }

    final preview = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: ShadCard(
        backgroundColor: hasFailed ? destructiveColor.withValues(alpha: 0.1) : Colors.transparent,
        border: hasFailed ? ShadBorder.all(color: destructiveColor.withValues(alpha: 0.5), width: 1) : null,
        radius: BorderRadius.circular(16),
        padding: EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 8),
        rowCrossAxisAlignment: CrossAxisAlignment.center,
        trailing: ShadGestureDetector(cursor: SystemMouseCursors.click, onTap: widget.onRemove, child: Icon(LucideIcons.x, size: 20)),
        child: content,
      ),
    );

    return ShadTooltip(
      waitDuration: const Duration(seconds: 1),
      builder: (context) {
        return Text(hasFailed ? 'Upload failed: ${widget.attachment.filename}' : widget.attachment.filename, style: theme.textTheme.small);
      },
      child: preview,
    );
  }
}

class FileDefaultPreviewCard extends StatefulWidget {
  const FileDefaultPreviewCard({
    super.key,
    required this.icon,
    required this.text,
    this.onClose,
    this.onDownload,
    this.showActionIcon = false,
    this.useThreadAttachmentStyle = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final bool showActionIcon;
  final bool useThreadAttachmentStyle;

  @override
  State<FileDefaultPreviewCard> createState() => _FileDefaultPreviewCardState();
}

class _FileDefaultPreviewCardState extends State<FileDefaultPreviewCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final useThreadAttachmentStyle = widget.useThreadAttachmentStyle;
    final attachmentSurfaceColor = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentSurfaceColorOf(context) : null;
    final attachmentBorderColor = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentBorderColorOf(context) : null;
    final attachmentIconColor = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentIconColorOf(context) : null;
    final attachmentActionColor = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentActionColorOf(context) : null;
    final attachmentHoverSurfaceColor = useThreadAttachmentStyle
        ? ThreadTypographyOverride.maybeAttachmentHoverSurfaceColorOf(context)
        : null;
    final attachmentHoverShadows = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentHoverShadowsOf(context) : null;
    final attachmentIconBuilder = useThreadAttachmentStyle ? ThreadTypographyOverride.maybeAttachmentIconBuilderOf(context) : null;
    final attachmentActionIconBuilder = useThreadAttachmentStyle
        ? ThreadTypographyOverride.maybeAttachmentActionIconBuilderOf(context)
        : null;
    final backgroundColor = attachmentSurfaceColor ?? Colors.transparent;
    final hoverTintColor = attachmentActionColor ?? theme.colorScheme.foreground;
    final effectiveBackgroundColor = useThreadAttachmentStyle && _hovered
        ? attachmentHoverSurfaceColor ?? Color.lerp(backgroundColor, hoverTintColor, 0.03) ?? backgroundColor
        : backgroundColor;
    final effectiveBorderColor = attachmentBorderColor;
    final border = effectiveBorderColor != null ? ShadBorder.all(color: effectiveBorderColor, width: 1) : null;
    final cardPadding = useThreadAttachmentStyle
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
        : const EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 8);
    final labelStyle = useThreadAttachmentStyle
        ? threadTypographyTextStyle(context, theme.textTheme.small.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2))
        : threadTypographyTextStyle(context, theme.textTheme.small);
    final leadingIconColor = attachmentIconColor;
    final actionIconColor = attachmentActionColor;
    final leadingBoxSize = useThreadAttachmentStyle ? 32.0 : 24.0;
    final contentGap = useThreadAttachmentStyle ? 10.0 : 8.0;
    final actionGap = useThreadAttachmentStyle ? 10.0 : 0.0;
    final actionBoxSize = useThreadAttachmentStyle ? 18.0 : 0.0;
    final showActionIcon = useThreadAttachmentStyle && (widget.showActionIcon || widget.onDownload != null);
    final actionIcon = showActionIcon
        ? IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered ? 1.0 : 0.3,
              child: SizedBox(
                width: actionBoxSize,
                height: 24,
                child: Center(
                  child:
                      attachmentActionIconBuilder?.call(context, color: actionIconColor, hovered: _hovered) ??
                      Icon(LucideIcons.arrowUpRight, size: 16, color: actionIconColor),
                ),
              ),
            ),
          )
        : null;
    final trailing = widget.onClose != null
        ? ShadIconButton.ghost(width: 24, height: 24, icon: Icon(LucideIcons.x, size: 16), onPressed: widget.onClose)
        : null;

    final card = AnimatedSlide(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      offset: useThreadAttachmentStyle && _hovered ? const Offset(0, -0.03) : Offset.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardHorizontalChrome = useThreadAttachmentStyle ? cardPadding.horizontal + (border == null ? 0 : 2) : 0.0;
          final textMaxWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth -
                        cardHorizontalChrome -
                        (leadingBoxSize + contentGap + (actionIcon == null ? 0 : actionGap + actionBoxSize)))
                    .clamp(0.0, double.infinity)
                    .toDouble()
              : double.infinity;
          return ShadCard(
            backgroundColor: effectiveBackgroundColor,
            border: border,
            shadows: useThreadAttachmentStyle && _hovered ? attachmentHoverShadows : (useThreadAttachmentStyle ? const [] : null),
            radius: BorderRadius.circular(16),
            padding: cardPadding,
            rowCrossAxisAlignment: CrossAxisAlignment.center,
            trailing: trailing,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: leadingBoxSize,
                  height: leadingBoxSize,
                  child: Center(
                    child:
                        attachmentIconBuilder?.call(
                          context,
                          fileName: widget.text,
                          fallbackIcon: widget.icon,
                          color: leadingIconColor,
                          hovered: _hovered,
                        ) ??
                        Icon(widget.icon, size: 20, color: leadingIconColor),
                  ),
                ),
                SizedBox(width: contentGap),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: Text(widget.text, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (actionIcon != null) ...[SizedBox(width: actionGap), actionIcon],
              ],
            ),
          );
        },
      ),
    );

    if (!showActionIcon) {
      return card;
    }

    final onDownload = widget.onDownload;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: onDownload == null ? card : GestureDetector(onTap: onDownload, behavior: HitTestBehavior.opaque, child: card),
    );
  }
}
