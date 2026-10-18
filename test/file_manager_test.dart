import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
// ignore: depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/storage/file_data_source.dart';
import 'package:meshagent_flutter_shadcn/storage/file_manager.dart';
import 'package:meshagent_flutter_shadcn/storage/powerboards/components/files/pb_files_header.dart';
import 'package:meshagent_flutter_shadcn/storage/powerboards/components/files/pb_files_table.dart';
import 'package:meshagent_flutter_shadcn/storage/powerboards/components/files/pb_files_side_pane.dart';
import 'package:meshagent_flutter_shadcn/storage/powerboards/components/menus/pb_sidepane_item_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

StorageEntry entry(String name, {bool folder = false}) =>
    StorageEntry(name: name, isFolder: folder, size: folder ? null : 5, createdAt: null, updatedAt: null);

class TestSource implements FileDataSource {
  final requests = <String>[];
  final changesController = StreamController<void>.broadcast();
  Object? failure;
  Completer<void>? pendingMkdir;
  bool writable = false;
  bool paginate = false;
  @override
  bool get supportsAbortTrigger => true;
  @override
  Stream<void> get changes => changesController.stream;
  @override
  Future<FilesPage> listPage(String path, {String? continuationToken}) async {
    requests.add('list:$path:${continuationToken ?? ''}');
    if (failure != null) throw failure!;
    return FilesPage(
      entries: path.isNotEmpty
          ? [entry('nested.txt')]
          : continuationToken != null
          ? [entry('last.txt')]
          : [entry('zebra.txt'), entry('alpha.txt'), entry('folder', folder: true)],
      continuationToken: paginate && path.isEmpty && continuationToken == null ? 'next /%+' : null,
    );
  }

  @override
  Future<FilePermissions> permissions(String path) async => FilePermissions(
    actions: {FileAction.list, FileAction.read, if (writable) FileAction.write, if (writable) FileAction.delete},
    recursiveActions: {FileAction.list, FileAction.read, if (writable) FileAction.write, if (writable) FileAction.delete},
  );
  @override
  Stream<List<int>> download(String path, {Future<void>? abortTrigger}) async* {
    requests.add('read:$path');
    yield utf8.encode('hello');
  }

  @override
  Future<void> upload(
    String path,
    Stream<List<int>> data, {
    int? size,
    String? contentType,
    bool overwrite = false,
    Future<void>? abortTrigger,
  }) async {
    requests.add('upload:$path');
    await data.drain<void>();
  }

  @override
  Future<void> mkdir(String path) async {
    requests.add('mkdir:$path');
    await pendingMkdir?.future;
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    requests.add('delete:$path:$recursive');
  }

  @override
  Future<void> move(String source, String destination, {bool overwrite = false}) async {
    requests.add('move:$source:$destination');
  }
}

class PendingSource extends TestSource {
  bool pending = false;
  final aborted = Completer<void>();
  @override
  Stream<List<int>> download(String path, {Future<void>? abortTrigger}) async* {
    if (!pending) {
      yield* super.download(path, abortTrigger: abortTrigger);
      return;
    }
    await abortTrigger;
    aborted.complete();
    throw StateError('Transfer aborted');
  }
}

Future<void> mount(
  WidgetTester tester,
  TestSource source, {
  FileManagerDownload? download,
  FileManagerStyle style = FileManagerStyle.powerboards,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(source.changesController.close);
  await tester.pumpWidget(
    ShadApp(
      home: Scaffold(
        body: FileManager(source: source, onDownload: download, style: style),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.irondash.engine_context'),
    (call) async => call.method == 'getEngineHandle' ? 0 : null,
  );
  final nativeContext = superNativeExtensionsContext;
  if (nativeContext is MockMessageChannelContext) {
    nativeContext.registerMockMethodCallHandler('DropManager', (MethodCall call) async => null);
    nativeContext.registerMockMethodCallHandler('DragManager', (MethodCall call) async => null);
  }
  testWidgets('Studio styling retains writable creation, text editing and navigation', (tester) async {
    final source = TestSource()..writable = true;
    await mount(tester, source, style: FileManagerStyle.shadcn);
    expect(find.byType(PbFilesTable), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(tester.widget<ShadButton>(find.widgetWithText(ShadButton, 'Upload')).onPressed, isNotNull);
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'Quarter 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.requests, contains('mkdir:Quarter 1'));
    await tester.tap(find.text('alpha.txt'));
    await tester.pumpAndSettle();
    expect(find.byType(PbFilesSidePane), findsNothing);
    expect(find.text('hello'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'updated');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.requests, contains('upload:alpha.txt'));
    await tester.tap(find.byIcon(LucideIcons.x).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('folder'));
    await tester.pumpAndSettle();
    expect(find.text('nested.txt'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsNothing);
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Studio loading errors show Retry instead of a blank browser', (tester) async {
    final source = TestSource()..failure = MeshagentException('Access denied', statusCode: 403);
    await mount(tester, source, style: FileManagerStyle.shadcn);
    expect(find.text('Unable to load files: Access denied'), findsOneWidget);
    expect(find.textContaining('You do not have permission to upload'), findsNothing);
    source.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.textContaining('You do not have permission to upload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Studio does not report missing upload permission during a file operation', (tester) async {
    final operation = Completer<void>();
    final source = TestSource()
      ..writable = true
      ..pendingMkdir = operation;
    await mount(tester, source, style: FileManagerStyle.shadcn);
    expect(find.textContaining('You do not have permission to upload'), findsNothing);
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Quarter 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.requests, contains('mkdir:Quarter 1'));
    expect(tester.widget<ShadButton>(find.widgetWithText(ShadButton, 'Upload')).onPressed, isNull);
    expect(find.textContaining('You do not have permission to upload'), findsNothing);
    operation.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<ShadButton>(find.widgetWithText(ShadButton, 'Upload')).onPressed, isNotNull);
    expect(find.textContaining('You do not have permission to upload'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the browser aborts an active streamed download', (tester) async {
    final source = PendingSource();
    await mount(tester, source, download: (name, bytes) => bytes.drain<void>());
    await tester.tap(find.text('alpha.txt').first);
    await tester.pumpAndSettle();
    source.pending = true;
    await tester.tap(find.descendant(of: find.byType(PbFilesSidePane), matching: find.byType(PbSidepaneItemMenu)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download').last);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(source.aborted.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('writable storage creates a folder through the retained toolbar', (tester) async {
    final source = TestSource()..writable = true;
    await mount(tester, source);
    await tester.tap(find.text('New folder').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Quarter 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.requests, contains('mkdir:Quarter 1'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared table supports sorting, filtering, folder navigation and opaque pagination', (tester) async {
    final source = TestSource()..paginate = true;
    await mount(tester, source);
    expect(find.byType(PbFilesTable), findsOneWidget);
    expect(find.byType(PbFilesHeader), findsOneWidget);
    expect(tester.getTopLeft(find.text('alpha.txt')).dy, lessThan(tester.getTopLeft(find.text('zebra.txt')).dy));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(source.requests, contains('list::next /%+'));
    expect(find.text('last.txt'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('zebra.txt'), findsNothing);
    expect(find.text('alpha.txt'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('folder').first);
    await tester.pumpAndSettle();
    expect(source.requests, contains('list:folder:'));
    expect(find.text('nested.txt'), findsOneWidget);
    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only permission snapshots disable creation and preview uses authenticated source', (tester) async {
    final source = TestSource();
    await mount(tester, source);
    final toolbar = tester.widget<PbFilesToolbar>(find.byType(PbFilesToolbar));
    expect(toolbar.onCreateFolder, isNull);
    expect(toolbar.onCreateTextFile, isNull);
    expect(toolbar.onUpload, isNull);
    await tester.tap(find.text('alpha.txt').first);
    await tester.pumpAndSettle();
    expect(source.requests, contains('read:alpha.txt'));
    expect(find.text('hello'), findsWidgets);
    expect(source.requests.where((request) => request.startsWith('upload:')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listing errors are visible and retry reloads the resource', (tester) async {
    final source = TestSource()..failure = MeshagentException('Access denied', statusCode: 403);
    await mount(tester, source);
    expect(find.text('Access denied'), findsOneWidget);
    source.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downloads use the supplied streaming destination and retain binary data', (tester) async {
    final source = TestSource();
    String? downloadedName;
    List<int>? bytes;
    await mount(
      tester,
      source,
      download: (name, stream) async {
        downloadedName = name;
        bytes = await stream.expand((chunk) => chunk).toList();
      },
    );
    await tester.tap(find.text('alpha.txt').first);
    await tester.pumpAndSettle();
    // The original preview toolbar provides the download action.
    await tester.tap(find.descendant(of: find.byType(PbFilesSidePane), matching: find.byType(PbSidepaneItemMenu)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download').last);
    await tester.pumpAndSettle();
    expect(downloadedName, 'alpha.txt');
    expect(bytes, utf8.encode('hello'));
    expect(tester.takeException(), isNull);
  });
}
