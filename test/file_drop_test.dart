import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat/folder_drop.dart';

void main() {
  test('room attachment URLs normalize to storage paths', () {
    const filename = 'Screenshot 2026-07-26 at 8.49.31\u202fAM.png';

    expect(normalizeRoomStorageAttachmentPath('room:///$filename'), filename);
    expect(normalizeRoomStorageAttachmentPath('room://screenshots/$filename'), 'screenshots/$filename');
    expect(normalizeRoomStorageAttachmentPath('/screenshots/$filename'), 'screenshots/$filename');
    expect(normalizeRoomStorageAttachmentPath(filename), filename);
  });

  test('native file URI drops read the original file bytes', () async {
    final directory = await Directory.systemTemp.createTemp('meshagent-file-drop-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/Screenshot.png');
    final expected = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4];
    await file.writeAsBytes(expected);

    final dropped = await resolveFileDrop(file.uri);

    expect(dropped, isNotNull);
    expect(dropped!.relativePath, 'Screenshot.png');
    expect(dropped.fileSize, expected.length);
    expect(await dropped.dataStream.expand((chunk) => chunk).toList(), expected);
  });
}
