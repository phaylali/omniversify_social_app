import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/main.dart';
import 'package:omniversify_social_app/data/dummy_data.dart';
import 'package:omniversify_social_app/models/post.dart';
import 'package:omniversify_social_app/screens/account_screen.dart';
import 'package:omniversify_social_app/screens/create_post_screen.dart';
import 'package:omniversify_social_app/data/post_state.dart';
import 'package:omniversify_social_app/services/user_posts.dart';

import 'account_fixtures.dart';

Future<void> _openComposer(WidgetTester tester) async {
  // Pushed the way the `+` button pushes it, so popping it has somewhere to go.
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open-composer'),
                onPressed: () => CreatePostScreen.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('open-composer')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

FilledButton _postButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('composer-post')));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserPosts.instance.reset();
    signInForTest();
  });

  testWidgets('three kinds, and no publishing until there is something to say',
      (tester) async {
    await _openComposer(tester);

    expect(find.text('Thought'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(_postButton(tester).onPressed, isNull);

    // A bare word is not a link, so the button stays shut.
    await tester.tap(find.text('Link'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'go and read this');
    await tester.pump();
    expect(_postButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'omniversify.com');
    await tester.pump();
    expect(_postButton(tester).onPressed, isNotNull);
  });

  testWidgets('a thought lands in front of the feed and can be liked',
      (tester) async {
    await _openComposer(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CreatePostScreen)),
    );

    await tester.enterText(
      find.byType(TextField),
      'Shipped the composer today.',
    );
    await tester.pump();
    expect(_postButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('composer-post')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CreatePostScreen), findsNothing);
    expect(UserPosts.instance.posts.value, hasLength(1));
    expect(UserPosts.instance.posts.value.first.text,
        'Shipped the composer today.');
    expect(UserPosts.instance.posts.value.first.type, PostType.text);

    // Without a state entry the heart would do nothing on a new post.
    final state = container.read(postStateProvider);
    expect(state.keys, contains(UserPosts.instance.posts.value.first.id));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: Scaffold(body: FeedScreen()))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Shipped the composer today.'), findsOneWidget);
  });

  testWidgets('private is offered, and the post keeps it', (tester) async {
    await _openComposer(tester);

    expect(find.text('Anyone on Omniversify can see this'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-visibility')));
    await tester.pump();
    expect(find.text('Only you can see this'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Just for me');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-post')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(UserPosts.instance.posts.value.single.visibility,
        PostVisibility.private);
  });

  testWidgets('writing waits for a confirmed email, and keeps the draft',
      (tester) async {
    signOutForTest();
    await _openComposer(tester);

    await tester.enterText(find.byType(TextField), 'Half-written thought');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-post')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AccountScreen), findsOneWidget);
    expect(UserPosts.instance.posts.value, isEmpty);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AccountScreen), findsNothing);
    expect(find.widgetWithText(TextField, 'Half-written thought'),
        findsOneWidget);
    expect(_postButton(tester).onPressed, isNotNull);
  });

  testWidgets('what you publish is still there next launch', (tester) async {
    await _openComposer(tester);
    await tester.enterText(find.byType(TextField), 'Written once, kept once');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-post')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    UserPosts.instance.reset();
    expect(UserPosts.instance.posts.value, isEmpty);

    await UserPosts.instance.init();
    expect(UserPosts.instance.posts.value, hasLength(1));
    expect(UserPosts.instance.posts.value.first.text,
        'Written once, kept once');
  });

  test('a post from a previous session still has a state entry', () async {
    // Written the way the composer writes, then started over the way a
    // relaunch starts over.
    await UserPosts.instance.add(Post(
      id: 'kept-1',
      user: currentUser,
      type: PostType.text,
      text: 'Still here',
      timestamp: DateTime(2026, 10, 7),
    ));
    UserPosts.instance.reset();
    await UserPosts.instance.init();

    expect(UserPosts.instance.posts.value.single.id, 'kept-1');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(postStateProvider).keys, contains('kept-1'));
  });

  testWidgets('switching kind drops what does not carry over', (tester) async {
    await _openComposer(tester);

    await tester.enterText(find.byType(TextField), 'A thought');
    await tester.pump();
    expect(find.widgetWithText(TextField, 'A thought'), findsOneWidget);

    await tester.tap(find.text('Media'));
    await tester.pump();

    // No photo chosen yet, so nothing can go out.
    expect(find.byType(TextField), findsOneWidget);
    expect(_postButton(tester).onPressed, isNull);
    expect(find.text('Choose a photo or video'), findsOneWidget);
  });
}
