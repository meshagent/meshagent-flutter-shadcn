import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'keeps the reaction action visible while the reaction menu is open',
    (tester) async {
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
      final hiddenIgnorePointer = reactionContext
          .findAncestorWidgetOfExactType<IgnorePointer>();
      final hiddenOpacity = reactionContext
          .findAncestorWidgetOfExactType<Opacity>();
      expect(hiddenIgnorePointer, isNotNull);
      expect(hiddenOpacity, isNotNull);
      expect(hiddenIgnorePointer!.ignoring, isTrue);
      expect(hiddenOpacity!.opacity, 0);

      expect(reactionController, isNotNull);
      reactionController!.show();
      await tester.pump();

      final visibleIgnorePointer = reactionContext
          .findAncestorWidgetOfExactType<IgnorePointer>();
      final visibleOpacity = reactionContext
          .findAncestorWidgetOfExactType<Opacity>();
      expect(visibleIgnorePointer, isNotNull);
      expect(visibleOpacity, isNotNull);
      expect(visibleIgnorePointer!.ignoring, isFalse);
      expect(visibleOpacity!.opacity, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('keeps the reaction action visible through the close animation', (
    tester,
  ) async {
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
    final closingOpacity = reactionContext
        .findAncestorWidgetOfExactType<Opacity>();
    expect(closingOpacity, isNotNull);
    expect(closingOpacity!.opacity, 1);

    await tester.pump(const Duration(milliseconds: 151));

    final hiddenOpacity = reactionContext
        .findAncestorWidgetOfExactType<Opacity>();
    expect(hiddenOpacity, isNotNull);
    expect(hiddenOpacity!.opacity, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
