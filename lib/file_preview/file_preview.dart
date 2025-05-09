import "package:meshagent/room_server_client.dart";
import 'package:flutter/widgets.dart';
import "package:shadcn_ui/shadcn_ui.dart";
import "package:url_launcher/url_launcher.dart";

import "image.dart";
import "pdf.dart";
import "video.dart";

final imageExtensions = <String>{"png", "jpeg", "jfif", "jpg", "heic", "webp", "tif", "tiff", "gif", "svg"};
final pdfExtensions = <String>{"pdf"};
final videoExtensions = <String>{"mp4", "mkv", "mov"};
final audioExtensions = <String>{"mp3", "ogg", "wav"};
final officeExtensions = <String>{"docx", "pptx", "xlsx"};

final Map<String, Widget Function({Key? key, required RoomClient room, required String filename, required Uri url})> customViewers = {};

Widget filePreview({Key? key, required RoomClient room, required String filename, required Uri url, BoxFit fit = BoxFit.cover}) {
  // assuming URL has extension, which is generally bad
  final extension = filename.split(".").last.toLowerCase();
  if (imageExtensions.contains(extension)) {
    return ImagePreview(url: url, key: key, fit: fit);
  } else if (videoExtensions.contains(extension)) {
    return VideoPreview(url: url, key: key, fit: fit);
  } else if (audioExtensions.contains(extension)) {
    return AudioPreview(url: url, key: key);
  } else if (pdfExtensions.contains(extension)) {
    return PdfPreview(url: url, key: key, fit: fit);
  } else if (customViewers.containsKey(extension)) {
    return customViewers[extension]!(key: key, room: room, filename: filename, url: url);
  } else {
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: urlLookup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ShadContextMenuRegion(
            items: [
              ShadContextMenuItem(
                trailing: Icon(LucideIcons.download),
                onPressed: () {
                  launchUrl(Uri.parse(snapshot.data!));
                },
                child: Text("Download"),
              ),
            ],
            child: filePreview(room: widget.room, filename: widget.path, url: Uri.parse(snapshot.data!), fit: widget.fit),
          );
        } else {
          return ColoredBox(color: ShadTheme.of(context).colorScheme.background);
        }
      },
    );
  }
}

class FilePreviewCard extends StatelessWidget {
  const FilePreviewCard({super.key, required this.icon, required this.text, this.onClose, this.onDownload});

  final IconData icon;
  final String text;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return ShadContextMenuRegion(
      items:
          onDownload != null
              ? [ShadContextMenuItem(trailing: Icon(LucideIcons.download), onPressed: onDownload, child: Text("Download"))]
              : [],
      child: ShadCard(
        radius: BorderRadius.circular(16),
        padding: EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 8),
        rowCrossAxisAlignment: CrossAxisAlignment.center,
        trailing:
            onClose != null ? ShadIconButton.ghost(width: 24, height: 24, icon: Icon(LucideIcons.x, size: 16), onPressed: onClose) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 24, child: Center(child: Icon(icon, size: 20))),
            const SizedBox(width: 12),
            Text(text, style: ShadTheme.of(context).textTheme.small),
          ],
        ),
      ),
    );
  }
}
