import 'package:flutter_test/flutter_test.dart';
import 'package:omniversify_social_app/services/daily_reset.dart';

void main() {
  group('daily reset', () {
    test('counts down to midnight UTC, not to the local day', () {
      // 23:30 UTC on the 29th — a Moroccan phone is already showing the 30th
      // at 00:30, but the reset is still half an hour away.
      final moment = DateTime.utc(2026, 9, 29, 23, 30);

      expect(DailyReset.stamp(moment), '2026-09-29');
      expect(DailyReset.nextUtcMidnight(moment), DateTime.utc(2026, 9, 30));
      expect(DailyReset.remaining(moment), const Duration(minutes: 30));
    });

    test('midnight in Morocco is not the reset', () {
      // Casablanca runs UTC+1, so its midnight on the 30th is 23:00 UTC on
      // the 29th — an hour of countdown still to go.
      final moroccanMidnight = DateTime.utc(2026, 9, 29, 23, 0);

      expect(DailyReset.remaining(moroccanMidnight), const Duration(hours: 1));
      expect(DailyReset.stamp(moroccanMidnight), '2026-09-29');
    });

    test('formats the countdown as digits with padded fields', () {
      expect(
        DailyReset.format(DailyReset.remaining(DateTime.utc(2026, 1, 1, 12))),
        '12:00:00',
      );
      expect(
        DailyReset.format(
            DailyReset.remaining(DateTime.utc(2026, 1, 1, 23, 59, 59))),
        '00:00:01',
      );
      expect(DailyReset.format(Duration.zero), '00:00:00');
      // A day late never shows more than the hours left today.
      expect(DailyReset.format(const Duration(hours: 30)), '23:59:59');
    });

    test('stamps the day zero-padded', () {
      expect(DailyReset.stamp(DateTime.utc(2026, 3, 5)), '2026-03-05');
      expect(DailyReset.stamp(DateTime.utc(2026, 12, 24)), '2026-12-24');
    });

    test('the readout names UTC so the time zone is never ambiguous', () {
      expect(DailyReset.label, '00:00 UTC');
    });
  });
}
