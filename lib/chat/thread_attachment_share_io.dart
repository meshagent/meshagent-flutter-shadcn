import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:meshagent/meshagent.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get supportsNativeThreadAttachmentShare => true;

Future<void> shareThreadAttachment({required BuildContext context, required RoomClient room, required String path}) async {
  final box = context.findRenderObject() as RenderBox?;
  final sharePositionOrigin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

  final url = await room.storage.downloadUrl(path);
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Download failed with status ${response.statusCode}', uri: Uri.parse(url));
  }

  final fileName = p.basename(path);
  final tempDirectory = await getTemporaryDirectory();
  final file = File(p.join(tempDirectory.path, fileName));
  await file.writeAsBytes(response.bodyBytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: lookupMimeType(fileName))],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}
