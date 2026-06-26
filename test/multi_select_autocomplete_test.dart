import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/forms/multi_select_autocomplete.dart';
import 'package:meshagent_flutter_shadcn/forms/select_users.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';

void main() {
  testWidgets('renders dropdown option text visibly in dark mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final darkTheme = ShadThemeData(colorScheme: const ShadSlateColorScheme.dark(), brightness: Brightness.dark);

    await tester.pumpWidget(
      ShadApp(
        themeMode: ThemeMode.dark,
        darkTheme: darkTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SizedBox(
                width: 500,
                child: MultiSelectAutocomplete(
                  debounceDuration: Duration.zero,
                  minimumSearchLength: 1,
                  search: (_) async => const ['jesse'],
                  optionBuilder: (context, item) => const Text('Jesse Ezell <jesse.ezell@timu.com>', key: Key('jesse-option')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'jes');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jesse-option')), findsOneWidget);

    final richText = tester.widget<RichText>(
      find.descendant(of: find.byKey(const Key('jesse-option')), matching: find.byType(RichText)).first,
    );
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'Jesse Ezell <jesse.ezell@timu.com>');
    expect(span.style?.color, darkTheme.colorScheme.popoverForeground);
  });

  testWidgets('closes dropdown after the visible option is selected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SizedBox(
                width: 500,
                child: MultiSelectAutocomplete(
                  debounceDuration: Duration.zero,
                  minimumSearchLength: 0,
                  search: (_) async => const ['jesse'],
                  optionBuilder: (context, item) => const Text('Jesse Ezell', key: Key('jesse-option')),
                  selectedItemBuilder: (context, item) => const Text('Jesse Ezell', key: Key('jesse-chip')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'jes');
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jesse-chip')), findsOneWidget);
    expect(find.byKey(const Key('jesse-option')), findsNothing);
  });

  testWidgets('select subjects can search and select service accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <AccessSubject>[];
    final client = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/service-accounts')) {
          return http.Response(
            jsonEncode({
              'service_accounts': [
                {
                  'id': 'service-account-1',
                  'project_id': 'project-1',
                  'key': 'builder',
                  'name': 'builder',
                  'email': 'builder@service.demo.example.test',
                  'description': '',
                  'metadata': {'display_name': 'Builder'},
                  'annotations': {},
                  'created_at': '2026-01-01T00:00:00Z',
                  'updated_at': '2026-01-01T00:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'users': [], 'agents': [], 'groups': []}), 200);
      }),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SizedBox(
                width: 500,
                child: SelectSubjects(
                  client: client,
                  projectId: 'project-1',
                  allowedTypes: const {SelectSubjectType.serviceAccount},
                  onChanged: (subjects) => selected
                    ..clear()
                    ..addAll(subjects),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'build');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Builder <builder@service.demo.example.test>'), findsOneWidget);
    expect(find.text('Service Account'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(selected.single.type, 'service_account');
    expect(selected.single.id, 'service-account-1');
    expect(selected.single.name, 'Builder');
    expect(tester.takeException(), isNull);
  });

  testWidgets('select subjects includes all service accounts userset when allowed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <AccessSubject>[];
    final client = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/service-accounts')) {
          return http.Response(jsonEncode({'service_accounts': []}), 200);
        }
        return http.Response(jsonEncode({}), 404);
      }),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SizedBox(
                width: 500,
                child: SelectSubjects(
                  client: client,
                  projectId: 'project-1',
                  allowedTypes: const {SelectSubjectType.projectServiceAccounts},
                  onChanged: (subjects) => selected
                    ..clear()
                    ..addAll(subjects),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('All service accounts'), findsOneWidget);
    expect(find.text('All project users'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(selected.single.type, 'userset');
    expect(selected.single.id, 'project-1');
    expect(selected.single.objectType, 'project');
    expect(selected.single.relation, 'service_account');
    expect(tester.takeException(), isNull);
  });

  testWidgets('select subjects resolves service account emails', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <AccessSubject>[];
    final client = Meshagent(
      baseUrl: 'http://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/subjects:resolve')) {
          expect(request.url.queryParameters['email'], 'builder@service.demo.example.test');
          return http.Response(
            jsonEncode({
              'type': 'service_account',
              'id': 'service-account-1',
              'name': 'Builder',
              'email': 'builder@service.demo.example.test',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'service_accounts': []}), 200);
      }),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SizedBox(
                width: 500,
                child: SelectSubjects(
                  client: client,
                  projectId: 'project-1',
                  allowedTypes: const {SelectSubjectType.serviceAccount},
                  onChanged: (subjects) => selected
                    ..clear()
                    ..addAll(subjects),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'builder@service.demo.example.test');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Builder <builder@service.demo.example.test>'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(selected.single.type, 'service_account');
    expect(selected.single.id, 'service-account-1');
    expect(selected.single.email, 'builder@service.demo.example.test');
    expect(tester.takeException(), isNull);
  });
}
