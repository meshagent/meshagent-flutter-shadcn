import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Color? _bubbleBackgroundColor(WidgetTester tester) {
  for (final container in tester.widgetList<Container>(find.byType(Container))) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.borderRadius != null) {
      return decoration.color;
    }
  }
  return null;
}

void main() {
  testWidgets('uses the accent background for non-assistant bubbles in dark mode', (tester) async {
    final darkTheme = ShadThemeData(colorScheme: const ShadSlateColorScheme.dark(), brightness: Brightness.dark);

    await tester.pumpWidget(
      ShadApp(
        themeMode: ThemeMode.dark,
        darkTheme: darkTheme,
        home: const Scaffold(body: ChatBubble(mine: false, accented: true, text: 'Hello')),
      ),
    );

    expect(_bubbleBackgroundColor(tester), darkTheme.colorScheme.accent);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('keeps the reaction action visible while the reaction menu is open', (tester) async {
    const reactionKey = Key('reaction-action');
    ShadContextMenuController? reactionController;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ChatBubble(
            mine: true,
            text: 'Hello',
            showReactionAction: true,
            reactionActionBuilder: (controller) {
              reactionController = controller;
              return const SizedBox(key: reactionKey, width: 30, height: 30);
            },
          ),
        ),
      ),
    );

    final reactionContext = tester.element(find.byKey(reactionKey));
    final hiddenIgnorePointer = reactionContext.findAncestorWidgetOfExactType<IgnorePointer>();
    final hiddenOpacity = reactionContext.findAncestorWidgetOfExactType<Opacity>();
    expect(hiddenIgnorePointer, isNotNull);
    expect(hiddenOpacity, isNotNull);
    expect(hiddenIgnorePointer!.ignoring, isTrue);
    expect(hiddenOpacity!.opacity, 0);

    expect(reactionController, isNotNull);
    reactionController!.show();
    await tester.pump();

    final visibleIgnorePointer = reactionContext.findAncestorWidgetOfExactType<IgnorePointer>();
    final visibleOpacity = reactionContext.findAncestorWidgetOfExactType<Opacity>();
    expect(visibleIgnorePointer, isNotNull);
    expect(visibleOpacity, isNotNull);
    expect(visibleIgnorePointer!.ignoring, isFalse);
    expect(visibleOpacity!.opacity, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('keeps the reaction action visible through the close animation', (tester) async {
    const reactionKey = Key('reaction-action-close');
    ShadContextMenuController? reactionController;

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ChatBubble(
            mine: true,
            text: 'Hello',
            showReactionAction: true,
            reactionActionBuilder: (controller) {
              reactionController = controller;
              return const SizedBox(key: reactionKey, width: 30, height: 30);
            },
          ),
        ),
      ),
    );

    expect(reactionController, isNotNull);
    reactionController!.show();
    await tester.pump();
    reactionController!.hide();
    await tester.pump();

    final reactionContext = tester.element(find.byKey(reactionKey));
    final closingOpacity = reactionContext.findAncestorWidgetOfExactType<Opacity>();
    expect(closingOpacity, isNotNull);
    expect(closingOpacity!.opacity, 1);

    await tester.pump(const Duration(milliseconds: 151));

    final hiddenOpacity = reactionContext.findAncestorWidgetOfExactType<Opacity>();
    expect(hiddenOpacity, isNotNull);
    expect(hiddenOpacity!.opacity, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('suppresses agent-only context when typography opts in', (tester) async {
    const text = 'Please create a one-page site\n\nAdditional context:\nKeep this guidance hidden from the user bubble.';

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: ThreadTypographyOverride(suppressAgentOnlyChatContext: true, child: const ChatBubble(mine: true, text: text)),
        ),
      ),
    );

    final viewer = tester.widget<MarkdownViewer>(find.byType(MarkdownViewer));
    expect(viewer.markdown, 'Please create a one-page site');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  test('deduplicates repeated webserver link replies', () {
    final repeated = [
      "Here's the link to your webserver:",
      '',
      'https://test.meshagent.dev',
      '',
      'You can also open the preview/files area here: [Open to view](powerboards://preview/webserver)',
    ].join('\n');

    expect(deduplicateRepeatedChatBubbleText('$repeated\n\n$repeated'), repeated);
  });
}
