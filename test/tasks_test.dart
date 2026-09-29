import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/ranks_screen.dart';
import 'package:omniversify_social_app/screens/tasks_screen.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Pumps a fixed stretch of time instead of settling.
  ///
  /// The progress tab ticks its reset countdown once a second, so
  /// `pumpAndSettle` there would wait for a frame that never stops coming.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('tasks page', () {
    testWidgets('opens from the ranks page with both tabs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RanksScreen(highlightLevel: 1)),
      );
      await pumpFrames(tester);

      expect(find.text('Tasks'), findsOneWidget);

      await tester.tap(find.text('Tasks'));
      await pumpFrames(tester);

      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('TODAY\'S TASKS'), findsOneWidget);
      expect(find.text('Daily login'), findsOneWidget);
    });

    testWidgets('progress tab tracks the live tasks', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
      await pumpFrames(tester);

      // Daily login hasn't been stamped in this test run.
      expect(find.text('0/1'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);

      // The keep-up task sits below the fold and counts the real follows.
      await tester.drag(find.byType(Scrollable), const Offset(0, -300));
      await pumpFrames(tester);

      expect(find.text('Keep up'), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);
    });

    testWidgets('guide tab lists the xp rules and the curve', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
      await pumpFrames(tester);

      await tester.tap(find.text('Guide'));
      await pumpFrames(tester);

      expect(find.text('HOW XP IS EARNED'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);

      await tester.drag(find.byType(Scrollable), const Offset(0, -200));
      await pumpFrames(tester);

      expect(
        find.text('Everyone starts on rank 1 with 0 XP — there is no rank 0.'),
        findsOneWidget,
      );
      expect(
        find.text('69,420,767 XP in total reaches the last rank.'),
        findsOneWidget,
      );

      // Milestones read off the same table as the Ranks page.
      await tester.drag(find.byType(Scrollable), const Offset(0, -400));
      await pumpFrames(tester);

      expect(find.text('Rank 69'), findsOneWidget);
      expect(find.text('69,420,767 XP'), findsOneWidget);
    });

    testWidgets('progress tab counts down to the UTC reset', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
      await tester.pump();

      expect(find.text('DAILY RESET IN'), findsOneWidget);
      expect(find.textContaining('roll over at 00:00 UTC'), findsOneWidget);

      final readout = find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$'));
      expect(readout, findsOneWidget);

      // The once-a-second ticker keeps the card alive across frames …
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('DAILY RESET IN'), findsOneWidget);

      // … and is cancelled when the page goes away, so no timer outlives it.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
