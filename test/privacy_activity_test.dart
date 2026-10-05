import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/privacy_screen.dart';
import 'package:omniversify_social_app/screens/reader_screen.dart';
import 'package:omniversify_social_app/services/activity_service.dart';
import 'package:omniversify_social_app/services/privacy_service.dart';
import 'package:omniversify_social_app/widgets/acquaintance_activity.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    ActivityService.instance.reading.value = null;
    await PrivacyService.instance.set(ShareAudience.acquaintances);
  });

  group('privacy setting', () {
    test('defaults to acquaintances and persists each choice', () async {
      await PrivacyService.instance.load();
      expect(
        PrivacyService.instance.audience.value,
        ShareAudience.acquaintances,
      );

      await PrivacyService.instance.set(ShareAudience.public);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('privacy_share_audience_v1'), 'public');
      expect(PrivacyService.instance.isShared, isTrue);

      await PrivacyService.instance.set(ShareAudience.private);
      expect(PrivacyService.instance.isShared, isFalse);
      expect(ShareAudience.private.shareLine, 'Not shared');
      expect(ShareAudience.public.blurb, contains('Everyone'));
    });

    testWidgets('the privacy page offers the three audiences', (tester) async {
      await PrivacyService.instance.set(ShareAudience.acquaintances);
      await tester.pumpWidget(
        const MaterialApp(home: PrivacyScreen()),
      );
      await tester.pump();

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Acquaintances'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      // Custom lists are promised, not offered yet.
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('SOON'), findsOneWidget);

      await tester.tap(find.text('Public'));
      await tester.pump();
      expect(
        PrivacyService.instance.audience.value,
        ShareAudience.public,
      );
    });
  });

  group('activity', () {
    test('the player owns no activity until something is open', () {
      expect(ActivityService.instance.own(), isNull);
    });

    test('the reader shows up as the book you are reading', () {
      ActivityService.instance.reading.value = 'Dune';

      final own = ActivityService.instance.own();
      expect(own, isNotNull);
      expect(own!.kind, ActivityKind.reading);
      expect(own.title, 'Dune');
      expect(own.line, 'Reading Dune');
    });

    test('only your own row is gated by the privacy setting', () {
      const mine = ActivityEntry(
        name: 'You',
        handle: '@phaylali',
        kind: ActivityKind.reading,
        title: 'Dune',
      );
      final theirs = ActivityService.acquaintances.first;

      expect(ActivityService.visibleTo(mine, isOwn: true, shared: true), isTrue);
      expect(ActivityService.visibleTo(mine, isOwn: true, shared: false),
          isFalse);
      expect(
          ActivityService.visibleTo(theirs, isOwn: false, shared: false), isTrue);
      expect(theirs.line, contains('Listening to'));
    });

    testWidgets('the acquaintances tab shows what everyone is doing',
        (tester) async {
      ActivityService.instance.reading.value = 'Dune';
      await PrivacyService.instance.set(ShareAudience.acquaintances);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: const [AcquaintanceActivity()]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('RIGHT NOW'), findsOneWidget);
      expect(find.text('Reading Dune', findRichText: true), findsOneWidget);
      expect(find.text('ACQUAINTANCES'), findsOneWidget);
      expect(find.textContaining('Listening to', findRichText: true),
          findsWidgets);

      // The act wears its own colour; the title beside it does not.
      // Text.rich wraps the span once, so the act sits one level down.
      final wrapper = tester
          .widget<RichText>(
            find.text('Reading Dune', findRichText: true),
          )
          .text as TextSpan;
      final act = wrapper.children!.first as TextSpan;
      final rest = act.children!.first as TextSpan;
      expect(act.text, 'Reading');
      expect(rest.text, ' Dune');
      expect(act.style?.color, isNot(rest.style?.color));

      // Private stops sharing your row but never hides other people's.
      await PrivacyService.instance.set(ShareAudience.private);
      await tester.pump();

      expect(find.text('Reading Dune', findRichText: true), findsNothing);
      expect(find.text('Nothing shared right now'), findsOneWidget);
      expect(find.text('PRIVATE'), findsOneWidget);
      expect(find.textContaining('Listening to', findRichText: true),
          findsWidgets);
    });
  });

  group('reader landing', () {
    testWidgets('offers a book, the four formats and the privacy choice',
        (tester) async {
      await PrivacyService.instance.set(ShareAudience.acquaintances);
      await tester.pumpWidget(
        const MaterialApp(home: ReaderScreen()),
      );
      await tester.pump();

      expect(find.text('Reader'), findsOneWidget);
      expect(find.text('Open a book'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('CBZ'), findsOneWidget);
      expect(find.text('CBR'), findsOneWidget);
      expect(find.textContaining('Sharing: Acquaintances'), findsOneWidget);

      // The reader reports itself as reading as soon as a book is open —
      // nothing is open here, so the strip stays empty.
      expect(ActivityService.instance.own(), isNull);
    });
  });
}
