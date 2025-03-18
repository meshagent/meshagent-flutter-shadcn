import "package:meshagent/room_server_client.dart";
import 'package:flutter/widgets.dart';
import "package:shadcn_ui/shadcn_ui.dart";
import "package:url_launcher/url_launcher.dart";

import "image.dart";
import "pdf.dart";
import "video.dart";
import "code.dart";

final imageExtensions = <String>{"png", "jpeg", "jfif", "jpg", "heic", "webp", "tif", "tiff", "gif", "svg"};
final pdfExtensions = <String>{"pdf"};
final videoExtensions = <String>{"mp4", "mkv", "mov"};
final audioExtensions = <String>{"mp3", "ogg", "wav"};
final codeExtension = <String>{"json"};

final officeExtensions = <String>{"docx", "pptx", "xlsx"};

Widget filePreview({Key? key, required String filename, required Uri url, BoxFit fit = BoxFit.cover}) {
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
  } else if (codeExtension.contains(extension)) {
    return CodePreview(url: url, key: key);
  } else {
    return Text(url.pathSegments.last);
  }
}

class FilePreview extends StatefulWidget {
  FilePreview({required this.client, required this.path, this.fit = BoxFit.cover}) : super(key: Key(path));

  final String path;
  final RoomClient client;
  final BoxFit fit;

  @override
  State createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  late final Future<String> urlLookup = widget.client.storage.downloadUrl(widget.path);

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
            child: filePreview(filename: widget.path, url: Uri.parse(snapshot.data!), fit: widget.fit),
          );
        } else {
          return ColoredBox(color: ShadTheme.of(context).colorScheme.background);
        }
      },
    );
  }
}
