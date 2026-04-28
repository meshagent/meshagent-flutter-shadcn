import 'package:flutter/widgets.dart';
import 'package:meshagent/meshagent.dart';

bool get supportsNativeThreadAttachmentShare => false;

Future<void> shareThreadAttachment({required BuildContext context, required RoomClient room, required String path}) {
  throw UnsupportedError('Native thread attachment sharing is unavailable on this platform.');
}
