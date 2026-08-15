import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/room_idle_disconnect.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('room client timeout annotation is parsed as minutes', () {
    expect(roomClientIdleTimeoutFromAnnotations(const {}), defaultRoomClientIdleTimeout);
    expect(roomClientIdleTimeoutFromAnnotations(const {roomClientTimeoutAnnotation: '15'}), const Duration(minutes: 15));
    expect(roomClientIdleTimeoutFromAnnotations(const {roomClientTimeoutAnnotation: '0.5'}), const Duration(seconds: 30));
    expect(roomClientIdleTimeoutFromAnnotations(const {roomClientTimeoutAnnotation: 'invalid'}), defaultRoomClientIdleTimeout);
    expect(roomClientIdleTimeoutFromAnnotations(const {roomClientTimeoutAnnotation: '0'}), defaultRoomClientIdleTimeout);
  });

  testWidgets('warns for 30 seconds before disconnecting an idle room', (tester) async {
    final startedAt = DateTime(2026);
    var now = startedAt;
    var disconnected = false;
    await tester.pumpWidget(
      ShadApp(
        home: ShadToaster(
          child: RoomIdleDisconnectGuard(
            idleTimeout: const Duration(seconds: 31),
            clock: () => now,
            isMeetingActive: () => false,
            onIdleDisconnect: () => disconnected = true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    now = startedAt.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Room inactive'), findsOneWidget);
    expect(find.text('This room will be shut down in 30 seconds due to inactivity.'), findsOneWidget);

    now = startedAt.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 29));
    expect(disconnected, isFalse);
    now = startedAt.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    expect(disconnected, isTrue);
  });

  testWidgets('keyboard activity resets the room idle timer', (tester) async {
    final startedAt = DateTime(2026);
    var now = startedAt;
    var disconnected = false;
    await tester.pumpWidget(
      ShadApp(
        home: ShadToaster(
          child: RoomIdleDisconnectGuard(
            idleTimeout: const Duration(seconds: 35),
            clock: () => now,
            isMeetingActive: () => false,
            onIdleDisconnect: () => disconnected = true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    now = startedAt.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    now = startedAt.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 5));
    now = startedAt.add(const Duration(seconds: 39));
    await tester.pump(const Duration(seconds: 29));
    expect(disconnected, isFalse);
    now = startedAt.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 1));
    expect(disconnected, isTrue);
  });

  testWidgets('mouse activity resets the room idle timer', (tester) async {
    final startedAt = DateTime(2026);
    var now = startedAt;
    var disconnected = false;
    await tester.pumpWidget(
      ShadApp(
        home: ShadToaster(
          child: RoomIdleDisconnectGuard(
            idleTimeout: const Duration(seconds: 35),
            clock: () => now,
            isMeetingActive: () => false,
            onIdleDisconnect: () => disconnected = true,
            child: const SizedBox.expand(key: ValueKey('room')),
          ),
        ),
      ),
    );

    now = startedAt.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('room'))));
    now = startedAt.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 5));
    now = startedAt.add(const Duration(seconds: 39));
    await tester.pump(const Duration(seconds: 29));
    expect(disconnected, isFalse);
    now = startedAt.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 1));
    expect(disconnected, isTrue);
    await mouse.removePointer();
  });

  testWidgets('an active meeting defers the warning and disconnect', (tester) async {
    final startedAt = DateTime(2026);
    var now = startedAt;
    var meetingActive = true;
    var disconnected = false;
    await tester.pumpWidget(
      ShadApp(
        home: ShadToaster(
          child: RoomIdleDisconnectGuard(
            idleTimeout: const Duration(seconds: 31),
            clock: () => now,
            isMeetingActive: () => meetingActive,
            onIdleDisconnect: () => disconnected = true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    now = startedAt.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 40));
    expect(find.text('Room inactive'), findsNothing);
    expect(disconnected, isFalse);

    meetingActive = false;
    now = startedAt.add(const Duration(seconds: 41));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Room inactive'), findsOneWidget);
    now = startedAt.add(const Duration(seconds: 71));
    await tester.pump(const Duration(seconds: 30));
    expect(disconnected, isTrue);
  });
}
