import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/ui/ui.dart';

void main() {
  group('timeAgo', () {
    test('shows seconds for recent past timestamps', () {
      final now = DateTime.utc(2026, 5, 28, 16, 12, 10);

      expect(timeAgo(DateTime.utc(2026, 5, 28, 16, 11, 48), now: now), '22 seconds ago');
    });

    test('keeps just now for near-identical timestamps', () {
      final now = DateTime.utc(2026, 5, 28, 16, 12, 10);

      expect(timeAgo(DateTime.utc(2026, 5, 28, 16, 12, 7), now: now), 'just now');
    });

    test('shows seconds for near future timestamps', () {
      final now = DateTime.utc(2026, 5, 28, 16, 12, 10);

      expect(timeAgo(DateTime.utc(2026, 5, 28, 16, 12, 32), now: now), 'in 22 seconds');
    });
  });
}
