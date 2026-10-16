import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/storage/save_download_io.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('files-download-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('streams binary data and atomically replaces an existing destination', () async {
    final destination = File('${directory.path}/data.bin');
    await destination.writeAsBytes([7]);
    final chunk = Uint8List.fromList([0, 255, 13, 10]);
    await saveDownloadToFile(destination, Stream.fromIterable([chunk, chunk]));
    expect(await destination.readAsBytes(), [...chunk, ...chunk]);
    expect(await directory.list().length, 1);
  });
  test('a failed stream preserves the destination and removes staging', () async {
    final destination = File('${directory.path}/data.bin');
    await destination.writeAsString('keep');
    Stream<List<int>> failing() async* {
      yield [0, 255];
      throw StateError('interrupted');
    }

    await expectLater(saveDownloadToFile(destination, failing()), throwsStateError);
    expect(await destination.readAsString(), 'keep');
    expect(await directory.list().length, 1);
  });
}
