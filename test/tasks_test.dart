import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/ranks_screen.dart';
import 'package:omniversify_social_app/screens/tasks_screen.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('tasks page', () {
    testWidgets('opens from the ranks page with both tabs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RanksScreen(highlightLevel: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsOneWidget);

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('TODAY\'S TASKS'), findsOneWidget);
      expect(find.text('Daily login'), findsOneWidget);
    });

    testWidgets('progress tab tracks the live tasks', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
      await tester.pumpAndSettle();

      // Daily login hasn't been stamped in this test run.
      expect(find.text('0/1'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);

      // The keep-up task sits below the fold and counts the real follows.
      await tester.drag(find.byType(Scrollable), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('Keep up'), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);
    });

    testWidgets('guide tab lists the xp rules and the curve', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();

      expect(find.text('HOW XP IS EARNED'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);

      await tester.drag(find.byType(Scrollable), const Offset(0, -200));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.text('Rank 69'), findsOneWidget);
      expect(find.text('69,420,767 XP'), findsOneWidget);
    });
  });
}
