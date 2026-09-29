import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/data/dummy_data.dart';
import 'package:omniversify_social_app/main.dart' show FeedScreen;
import 'package:omniversify_social_app/models/post.dart';
import 'package:omniversify_social_app/services/mute_service.dart';
import 'package:omniversify_social_app/services/relationship_service.dart';
import 'package:omniversify_social_app/widgets/post_components.dart';
import 'package:omniversify_social_app/widgets/post_interaction_panel.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    RelationshipService.instance.following.value = {};
    RelationshipService.instance.requests.value = {};
  });

  group('Profile actions', () {
    testWidgets('get acquainted + keep up toggle on other profiles', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ProfileViewScreen(
          user: const PostUser(name: 'Amina', handle: '@amina_stream'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Get acquainted'), findsOneWidget);
      expect(find.text('Keep up'), findsOneWidget);

      await tester.tap(find.text('Keep up'));
      await tester.pump();
      expect(find.text('Keeping up'), findsOneWidget);
      expect(RelationshipService.instance.isFollowing('@amina_stream'), isTrue);

      await tester.tap(find.text('Get acquainted'));
      await tester.pump();
      expect(find.text('Request sent'), findsOneWidget);
      expect(RelationshipService.instance.hasRequested('@amina_stream'), isTrue);

      // Tapping again withdraws both.
      await tester.tap(find.text('Keeping up'));
      await tester.pump();
      expect(find.text('Keep up'), findsOneWidget);
      expect(RelationshipService.instance.isFollowing('@amina_stream'), isFalse);
    });
  });

  group('Comment sorting', () {
    testWidgets('newest and popular order the roots differently', (tester) async {
      // Tall viewport so every generated comment is laid out at once,
      // at a realistic narrow phone width (360 logical px).
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PostInteractionPanel(postId: '1', initialTab: 1),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sort by'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Popular'), findsOneWidget);

      // Newest: 'This is amazing!' is an hour old, 'Incredible work' is four.
      final newestFirst = tester.getTopLeft(find.text('This is amazing!')).dy;
      final newestLast = tester.getTopLeft(find.text('Incredible work')).dy;
      expect(newestFirst, lessThan(newestLast));

      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();

      // Popular: 'Incredible work' has 21 likes, 'This is amazing!' has none.
      final popularFirst = tester.getTopLeft(find.text('Incredible work')).dy;
      final popularLast = tester.getTopLeft(find.text('This is amazing!')).dy;
      expect(popularFirst, lessThan(popularLast));
    });
  });

  group('Post menu', () {
    tearDown(() => MuteService.instance.unmuteAll());

    testWidgets('the ⋮ opens the same sheet the scrolls menu uses',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PostHeader(
            name: 'Amina',
            handle: '@amina_stream',
            timestamp: DateTime.now(),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The exact rows the scrolls menu shows, plus block and copy link.
      expect(find.text('Report user'), findsOneWidget);
      expect(find.text('Report content'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Tell us about @amina_stream'), findsOneWidget);
      expect(find.text('Hide @amina_stream\'s posts for now'), findsOneWidget);

      // Choosing one closes the sheet and confirms on the screen behind it.
      await tester.tap(find.text('Mute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mute'), findsNothing);
      expect(MuteService.instance.isMuted('@amina_stream'), isTrue);
      expect(find.text('@amina_stream muted'), findsOneWidget);
    });

    testWidgets('muted accounts drop out of the feed until unmuted',
        (tester) async {
      const mine = 'Just finished setting up my entire media tracking system';

      await tester.pumpWidget(ProviderScope(
        child: const MaterialApp(
          home: Scaffold(body: FeedScreen()),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(mine), findsOneWidget);

      // Muting the author takes both of their posts off the feed.
      MuteService.instance.mute('@phaylali');
      await tester.pump();
      expect(find.textContaining(mine), findsNothing);
      expect(find.textContaining('Finally watched Dune Part Two'), findsNothing);

      // Everyone hidden at once still leaves a way back out.
      for (final post in dummyPosts) {
        MuteService.instance.mute(post.user.handle);
      }
      await tester.pump();
      expect(find.text('Everyone is hidden'), findsOneWidget);

      await tester.tap(find.text('Unmute everyone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(mine), findsOneWidget);
      expect(MuteService.instance.muted.value, isEmpty);
    });

    testWidgets('the UNDO on the mute snackbar puts the posts back',
        (tester) async {
      const mine = 'Just finished setting up my entire media tracking system';

      await tester.pumpWidget(ProviderScope(
        child: const MaterialApp(
          home: Scaffold(body: FeedScreen()),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Mute from the post's own menu — the sheet closes, the notice follows.
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Mute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(mine), findsNothing);
      expect(find.text('@phaylali muted'), findsOneWidget);

      await tester.tap(find.text('UNDO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(MuteService.instance.muted.value, isEmpty);
      expect(find.textContaining(mine), findsOneWidget);
    });
  });

  group('Privacy', () {
    late Post original;

    setUp(() {
      original = dummyPosts[0];
      dummyPosts[0] = Post(
        id: '1',
        user: currentUser,
        type: PostType.text,
        text: 'Only my close friends see this.',
        timestamp: DateTime.now(),
        comments: 5,
        shares: 3,
        visibility: PostVisibility.private,
      );
    });

    tearDown(() {
      dummyPosts[0] = original;
    });

    testWidgets('header shows the private indicator', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PostHeader(
            name: 'Phaylali',
            handle: '@phaylali',
            timestamp: DateTime.now(),
            visibility: PostVisibility.private,
          ),
        ),
      ));

      expect(find.text('Private'), findsOneWidget);
    });

    testWidgets('share button is replaced by a lock', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: PostFooter(postId: '1')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.share_outlined), findsNothing);
      final lock = find.byIcon(Icons.lock_outline);
      expect(lock, findsOneWidget);

      await tester.tap(lock);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sharing is off for private posts'), findsOneWidget);
    });

    testWidgets('panel drops the Shares tab', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PostInteractionPanel(postId: '1', initialTab: 2),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Shares'), findsNothing);
      // Tab 2 no longer exists, so the panel lands on comments.
      expect(find.text('Sort by'), findsOneWidget);
    });
  });
}
