import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/code_editor.dart';
import 'package:meshagent_flutter_shadcn/forms/metadata_editors.dart';
import 'package:meshagent_flutter_shadcn/secrets/keychain_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('metadata editor uses shad input decoration and editor surface colors', (tester) async {
    final restoreCodeForgeAssets = await _installCodeForgeFontAssets();
    addTearDown(restoreCodeForgeAssets);
    final controller = JsonMetadataEditingController(value: const {'service': 'github'});
    addTearDown(controller.dispose);
    final colorScheme = ShadNeutralColorScheme.dark();

    await tester.pumpWidget(
      ShadApp(
        themeMode: ThemeMode.dark,
        darkTheme: ShadThemeData(brightness: Brightness.dark, colorScheme: colorScheme),
        home: Builder(builder: (context) => JsonMetadataEditor(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final context = tester.element(find.byType(JsonMetadataEditor));
    final shadTheme = ShadTheme.of(context);
    final decorator = tester.widget<ShadDecorator>(find.ancestor(of: find.byType(CodeEditor), matching: find.byType(ShadDecorator)).first);

    expect(decorator.decoration, shadTheme.inputTheme.decoration);
    expect(editor.style?.backgroundColor, colorScheme.background);
    expect(editor.style?.textColor, colorScheme.foreground);
    expect(editor.style?.codeTheme?.theme['root']?.backgroundColor, colorScheme.background);
    expect(editor.style?.codeTheme?.theme['root']?.color, colorScheme.foreground);
  });

  testWidgets('annotations field is an unframed key value editor', (tester) async {
    Map<String, String>? changed;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: AnnotationsField(value: const {'meshagent.io/provider': 'github'}, onChanged: (value) => changed = value),
        ),
      ),
    );

    expect(find.byType(AnnotationsEditor), findsOneWidget);
    expect(find.byType(ShadCard), findsNothing);
    expect(find.byKey(const Key('annotation-key-0')), findsOneWidget);
    expect(find.byKey(const Key('annotation-value-0')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('annotation-key-0')), 'meshagent.io/secret.provider');
    await tester.enterText(find.byKey(const Key('annotation-value-0')), 'linear');

    expect(changed, {'meshagent.io/secret.provider': 'linear'});
  });

  testWidgets('annotations editor keeps cursor position while parent value updates', (tester) async {
    Map<String, String> annotations = const {'meshagent.io/provider': 'github'};

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AnnotationsField(value: annotations, onChanged: (value) => setState(() => annotations = value));
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('annotation-key-0')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'meshagent.io/provider-name', selection: TextSelection.collapsed(offset: 26)),
    );
    await tester.pump();
    expect(_editableTextForKey(tester, const Key('annotation-key-0')).controller.selection.baseOffset, 26);

    await tester.tap(find.byKey(const Key('annotation-value-0')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'github-enterprise', selection: TextSelection.collapsed(offset: 17)),
    );
    await tester.pump();
    expect(_editableTextForKey(tester, const Key('annotation-value-0')).controller.selection.baseOffset, 17);
  });

  testWidgets('user secrets pane lists secrets and manages proxy grants', (tester) async {
    final flutterErrors = _captureFlutterErrors();
    addTearDown(flutterErrors.restore);
    final requests = <_RecordedRequest>[];
    var proxyGranted = false;
    final client = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        requests.add(_RecordedRequest.from(request));
        if (request.method == 'GET' && request.url.path == '/accounts/users/me/secrets') {
          return _json({
            'secrets': [_secretJson()],
          });
        }
        if (request.method == 'GET' && request.url.path == '/accounts/projects/project-1/service-accounts') {
          return _json({
            'service_accounts': [_serviceAccountJson()],
          });
        }
        if (request.method == 'GET' && request.url.path == '/accounts/projects/project-1/iam/secret/secret-1/policy') {
          return _json({
            'resource': {'type': 'secret', 'id': 'secret-1', 'name': 'github'},
            'access_grants': proxyGranted
                ? [
                    {
                      'resource': {'type': 'secret', 'id': 'secret-1', 'name': 'github'},
                      'subject': {'type': 'service_account', 'id': 'sa-1'},
                      'direct_roles': ['use_proxy'],
                    },
                  ]
                : [],
          });
        }
        if (request.method == 'POST' && request.url.path == '/accounts/projects/project-1/iam/secret/secret-1/policy:grant') {
          proxyGranted = true;
          return _json({});
        }
        if (request.method == 'POST' && request.url.path == '/accounts/projects/project-1/iam/secret/secret-1/policy:revoke') {
          proxyGranted = false;
          return _json({});
        }
        return http.Response('unexpected ${request.method} ${request.url}', 500);
      }),
    );

    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShadApp(
        home: UserSecretsPane(client: client, projectId: 'project-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(flutterErrors.errors, isEmpty);

    expect(find.text('Name'), findsWidgets);
    expect(find.text('Type'), findsWidgets);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('github'), findsWidgets);
    expect(find.text('Proxy Access'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
    await _pumpEditorSheet(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Permissions...'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Permissions...'));
    await _pumpEditorSheet(tester);
    expect(find.text('github permissions'), findsOneWidget);
    expect(find.text('No service accounts have proxy access.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('secret-proxy-service-account')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(flutterErrors.errors, isEmpty);
    expect(find.text('All service accounts'), findsWidgets);
    await tester.tap(find.text('Builder <builder@service.example.test>').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grant-secret-proxy-access')));
    await tester.pumpAndSettle();

    expect(proxyGranted, isTrue);
    expect(
      requests.any((request) {
        return request.method == 'POST' &&
            request.path == '/accounts/projects/project-1/iam/secret/secret-1/policy:grant' &&
            request.body?['subject']?['type'] == 'service_account' &&
            request.body?['subject']?['id'] == 'sa-1' &&
            (request.body?['roles'] as List?)?.contains('use_proxy') == true &&
            (request.body?['roles'] as List?)?.contains('list') != true;
      }),
      isTrue,
    );
    expect(find.text('use_proxy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('revoke-secret-proxy-access-service_account:sa-1')));
    await tester.pumpAndSettle();

    expect(proxyGranted, isFalse);
    expect(
      requests.any((request) {
        return request.method == 'POST' &&
            request.path == '/accounts/projects/project-1/iam/secret/secret-1/policy:revoke' &&
            request.body?['subject']?['type'] == 'service_account' &&
            request.body?['subject']?['id'] == 'sa-1';
      }),
      isTrue,
    );
  });

  testWidgets('user secrets pane creates updates and deletes user secrets', (tester) async {
    final restoreCodeForgeAssets = await _installCodeForgeFontAssets();
    addTearDown(restoreCodeForgeAssets);
    final flutterErrors = _captureFlutterErrors();
    addTearDown(flutterErrors.restore);
    final requests = <_RecordedRequest>[];
    var secretName = 'github';
    final client = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        requests.add(_RecordedRequest.from(request));
        if (request.method == 'GET' && request.url.path == '/accounts/users/me/secrets') {
          return _json({
            'secrets': [_secretJson(name: secretName)],
          });
        }
        if (request.method == 'GET' && request.url.path == '/accounts/projects/project-1/service-accounts') {
          return _json({'service_accounts': <Object>[]});
        }
        if (request.method == 'POST' && request.url.path == '/accounts/users/me/secrets') {
          secretName = (jsonDecode(request.body) as Map<String, dynamic>)['name'] as String;
          return _json(_secretJson(name: secretName));
        }
        if (request.method == 'PATCH' && request.url.path == '/accounts/users/me/secrets/secret-1') {
          secretName = (jsonDecode(request.body) as Map<String, dynamic>)['name'] as String;
          return _json(_secretJson(name: secretName));
        }
        if (request.method == 'POST' && request.url.path == '/accounts/users/me/secrets/secret-1/versions') {
          return _json({
            'id': 'version-2',
            'secret_id': 'secret-1',
            'version': 2,
            'encryption_key_id': 'key-1',
            'created_at': '2026-01-01T00:00:00Z',
          });
        }
        if (request.method == 'DELETE' && request.url.path == '/accounts/users/me/secrets/secret-1') {
          return _json({});
        }
        return http.Response('unexpected ${request.method} ${request.url}', 500);
      }),
    );

    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShadApp(
        home: UserSecretsPane(client: client, projectId: 'project-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(flutterErrors.errors, isEmpty);

    await tester.tap(find.byKey(const Key('new-user-secret')));
    await _pumpEditorSheet(tester);
    expect(find.text('Name'), findsWidgets);
    expect(find.text('Type'), findsWidgets);
    expect(find.byKey(const Key('secret-value-input')), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('Annotations'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('secret-name-input')), 'linear');
    await tester.tap(find.byKey(const Key('secret-type-select')));
    await _pumpEditorSheet(tester);
    await tester.tap(find.text('Custom').last);
    await _pumpEditorSheet(tester);
    await tester.enterText(find.byKey(const Key('secret-custom-type-input')), 'application/x-linear-token');
    await tester.enterText(find.byKey(const Key('secret-value-input')), 'secret-value\nsecond-line');
    final metadataEditor = tester.widget<JsonMetadataEditor>(find.byKey(const Key('secret-metadata-input')));
    metadataEditor.controller.text = '{"service":"linear","account":"workspace-1"}';
    await tester.pump();
    await tester.enterText(find.byKey(const Key('annotation-key-0')), 'meshagent.io/secret.provider');
    await tester.enterText(find.byKey(const Key('annotation-value-0')), 'linear');
    await tester.tap(find.byKey(const Key('save-user-secret')));
    await _pumpEditorSheet(tester);
    expect(tester.takeException(), isNull);
    expect(flutterErrors.errors, isEmpty);

    expect(
      requests.any(
        (request) =>
            request.method == 'POST' &&
            request.path == '/accounts/users/me/secrets' &&
            request.body?['name'] == 'linear' &&
            request.body?['type'] == 'application/x-linear-token' &&
            request.body?['http_only'] == false &&
            request.body?['metadata']?['service'] == 'linear' &&
            request.body?['metadata']?['account'] == 'workspace-1' &&
            request.body?['annotations']?['meshagent.io/secret.provider'] == 'linear',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) =>
            request.method == 'POST' &&
            request.path == '/accounts/users/me/secrets/secret-1/versions' &&
            request.body?['value_base64'] == base64Encode(utf8.encode('secret-value\nsecond-line')),
      ),
      isTrue,
    );

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
    await _pumpEditorSheet(tester);
    await tester.tap(find.text('Edit').last);
    await _pumpEditorSheet(tester);
    await tester.enterText(find.byKey(const Key('secret-name-input')), 'linear-updated');
    await tester.tap(find.byKey(const Key('save-user-secret')));
    await _pumpEditorSheet(tester);

    expect(
      requests.any(
        (request) =>
            request.method == 'PATCH' && request.path == '/accounts/users/me/secrets/secret-1' && request.body?['name'] == 'linear-updated',
      ),
      isTrue,
    );

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical).first);
    await _pumpEditorSheet(tester);
    await tester.tap(find.text('Delete').last);
    await _pumpEditorSheet(tester);
    await tester.tap(find.widgetWithText(ShadButton, 'Delete').last);
    await _pumpEditorSheet(tester);

    expect(requests.any((request) => request.method == 'DELETE' && request.path == '/accounts/users/me/secrets/secret-1'), isTrue);
    expect(tester.takeException(), isNull);
    expect(flutterErrors.errors, isEmpty);
  });
}

http.Response _json(Object body) {
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}

Future<VoidCallback> _installCodeForgeFontAssets() async {
  var directory = File(Platform.resolvedExecutable).parent;
  File? fontFile;
  while (true) {
    final candidates = [
      File(
        '${directory.path}/cache/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto_Mono/RobotoMono-Regular.ttf',
      ),
      File(
        '${directory.path}/bin/cache/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto_Mono/RobotoMono-Regular.ttf',
      ),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) {
        fontFile = candidate;
        break;
      }
    }
    if (fontFile != null || directory.parent.path == directory.path) {
      break;
    }
    directory = directory.parent;
  }
  final resolvedFontFile = fontFile;
  if (resolvedFontFile == null) {
    throw StateError('Unable to locate a local monospace font for source editor tests.');
  }
  final fontBytes = resolvedFontFile.readAsBytesSync();
  const assets = [
    'packages/code_forge/assets/icons/method.ttf',
    'packages/code_forge/assets/icons/variable.ttf',
    'packages/code_forge/assets/icons/class.ttf',
    'packages/code_forge/assets/icons/reference.ttf',
    'packages/code_forge/assets/icons/struct.ttf',
    'packages/code_forge/assets/icons/event.ttf',
    'packages/code_forge/assets/icons/operator.ttf',
    'packages/code_forge/assets/icons/parameter.ttf',
    'packages/code_forge/assets/icons/interface.ttf',
    'packages/code_forge/assets/icons/field.ttf',
  ];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (message) async {
    if (message == null) {
      return null;
    }
    final key = utf8.decode(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final asset in assets)
          asset: [
            {'asset': asset},
          ],
      });
    }
    if (assets.contains(key)) {
      return ByteData.sublistView(fontBytes);
    }
    return null;
  });
  return () => messenger.setMockMessageHandler('flutter/assets', null);
}

Future<void> _pumpEditorSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

EditableText _editableTextForKey(WidgetTester tester, Key key) {
  return tester.widget<EditableText>(find.descendant(of: find.byKey(key), matching: find.byType(EditableText)));
}

Map<String, dynamic> _secretJson({String name = 'github'}) {
  return {
    'id': 'secret-1',
    'project_id': 'project-1',
    'owner_user_id': 'user-1',
    'type': 'opaque',
    'name': name,
    'http_only': true,
    'metadata': <String, dynamic>{},
    'annotations': <String, dynamic>{},
    'current_version_id': 'version-1',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };
}

Map<String, dynamic> _serviceAccountJson() {
  return {
    'id': 'sa-1',
    'project_id': 'project-1',
    'key': 'builder',
    'name': 'builder',
    'email': 'builder@service.example.test',
    'description': '',
    'metadata': {'display_name': 'Builder'},
    'annotations': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };
}

class _RecordedRequest {
  const _RecordedRequest({required this.method, required this.path, this.body});

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  static _RecordedRequest from(http.Request request) {
    final decoded = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>;
    return _RecordedRequest(method: request.method, path: request.url.path, body: decoded);
  }
}

_CapturedFlutterErrors _captureFlutterErrors() {
  final previous = FlutterError.onError;
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    errors.add(details);
    FlutterError.dumpErrorToConsole(details);
  };
  return _CapturedFlutterErrors(errors: errors, restore: () => FlutterError.onError = previous);
}

class _CapturedFlutterErrors {
  const _CapturedFlutterErrors({required this.errors, required this.restore});

  final List<FlutterErrorDetails> errors;
  final VoidCallback restore;
}
