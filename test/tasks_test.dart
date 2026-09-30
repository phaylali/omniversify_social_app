import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/data/dummy_data.dart';
import 'package:omniversify_social_app/data/post_state.dart';
import 'package:omniversify_social_app/screens/ranks_screen.dart';
import 'package:omniversify_social_app/screens/tasks_screen.dart';
import 'package:omniversify_social_app/services/daily_tasks.dart';

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
      expect(find.text('0/3'), findsNWidgets(2)); // Create a post + Keep up

      // The counters that only real actions move all open at zero.
      expect(find.text('0/5'), findsOneWidget); // Comment
      expect(find.text('0/10'), findsOneWidget); // Like
      expect(find.text('0/2'), findsOneWidget); // Share
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

  // Last: the counters are a process-wide singleton, so the widget tests
  // above must see them untouched first.
  test('daily counters count real actions and are written down', () async {
    final daily = DailyTasks.instance;
    await daily.init();
    expect(daily.likes, 0);
    expect(daily.comments, 0);
    expect(daily.shares, 0);

    final posts = PostStateNotifier();
    addTearDown(posts.dispose);
    final post = dummyPosts.first;

    // A like that turns on counts; taking it straight back off doesn't.
    posts.toggleLike(post.id);
    expect(daily.likes, 1);
    posts.toggleLike(post.id);
    expect(daily.likes, 1);
    posts.toggleLike(post.id);
    expect(daily.likes, 2);

    posts.addComment(post.id, 'nicely put', post.user);
    expect(daily.comments, 1);

    posts.share(post.id);
    expect(daily.shares, 1);

    // One listener hears every move, so the Tasks tab can rebuild once.
    expect(daily.revision.value, greaterThan(0));

    // The day's counts are filed under the UTC day they belong to, which is
    // the only thing a midnight reset wipes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('daily_tasks_day_v1'), isNotNull);
    expect(prefs.getInt('daily_tasks_likes_v1'), 2);
    expect(prefs.getInt('daily_tasks_comments_v1'), 1);
    expect(prefs.getInt('daily_tasks_shares_v1'), 1);
  });
}
