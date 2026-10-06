import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omniversify_social_app/data/dummy_data.dart';
import 'package:omniversify_social_app/screens/story_viewer_screen.dart';
import 'package:omniversify_social_app/widgets/stories_row.dart';

import 'account_fixtures.dart';

void main() {
  tearDown(signOutForTest);

  testWidgets('tapping a story opens the placeholder story viewer',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StoriesRow())),
    );
    await tester.pump();

    final name = dummyPosts.first.user.name;
    await tester.tap(find.text(name));

    // The route animation only starts on the following frame, then runs the
    // usual 300ms transition. Settling instead would let the 5s segment
    // timer finish and close the viewer this test just opened.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(StoryViewerScreen), findsOneWidget);
    expect(find.text('Story coming soon'), findsOneWidget);
    expect(find.textContaining('hasn\'t posted a story yet'), findsOneWidget);
    // The poster's identity sits over the placeholder art.
    expect(find.text(name), findsWidgets);

    // Closing it puts the story row back.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StoryViewerScreen), findsNothing);
    expect(find.text('Your story'), findsOneWidget);
  });

  testWidgets('the reply box and the like button keep the story in place',
      (tester) async {
    // A reply is a message, so the gate needs a confirmed email behind it.
    signInForTest();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StoriesRow())),
    );
    await tester.pump();

    final name = dummyPosts.first.user.name;
    final handle = dummyPosts.first.user.handle;
    await tester.tap(find.text(name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The heart likes the story it belongs to.
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byType(StoryViewerScreen), findsOneWidget);

    // Tapping the reply box focuses it — it must not skip to the next story.
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StoryViewerScreen), findsOneWidget);
    expect(find.text(name), findsWidgets);
    expect(find.text('Reply to $handle'), findsOneWidget);

    // Typing enables send, and sending confirms without leaving the story.
    await tester.enterText(find.byType(TextField), 'nice one');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(find.text('Reply sent to $handle'), findsOneWidget);
    expect(find.byType(StoryViewerScreen), findsOneWidget);
    expect(find.text('nice one'), findsNothing);
  });
}
