import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('opening a coordinated region closes an open coordinated menu', (tester) async {
    final menuController = ShadContextMenuController();
    final regionController = ShadContextMenuController();
    addTearDown(menuController.dispose);
    addTearDown(regionController.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Row(
            children: [
              CoordinatedShadContextMenu(
                controller: menuController,
                items: const [ShadContextMenuItem(child: Text('Menu item'))],
                child: ShadButton(onPressed: menuController.toggle, child: const Text('Open menu')),
              ),
              const SizedBox(width: 24),
              CoordinatedShadContextMenuRegion(
                controller: regionController,
                tapEnabled: false,
                longPressEnabled: false,
                items: const [ShadContextMenuItem(child: Text('Region item'))],
                child: ShadButton(onPressed: regionController.toggle, child: const Text('Open region')),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    expect(menuController.isOpen, isTrue);
    expect(regionController.isOpen, isFalse);

    await tester.tap(find.text('Open region'));
    await tester.pumpAndSettle();

    expect(menuController.isOpen, isFalse);
    expect(regionController.isOpen, isTrue);
  });

  testWidgets('tapping outside closes a coordinated menu', (tester) async {
    final controller = ShadContextMenuController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SizedBox()),
              Align(
                alignment: Alignment.topLeft,
                child: CoordinatedShadContextMenu(
                  controller: controller,
                  items: const [ShadContextMenuItem(child: Text('Menu item'))],
                  child: ShadButton(onPressed: controller.toggle, child: const Text('Open menu')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
  });
}
