import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/services/messages_service.dart';
import 'package:omniversify_social_app/services/share_in_service.dart';
import 'package:omniversify_social_app/widgets/share_sheet.dart';

import 'account_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessagesService.instance.reset();
    // Picking people to send to needs a confirmed email; these tests are
    // about what lands in the thread, so they start already signed in.
    signInForTest();
  });

  group('shares', () {
    test('the same link goes into every conversation that was picked',
        () async {
      await MessagesService.instance.shareTo(
        const ['@amina_stream', '@omar_gamer'],
        'https://omniversify.com/c/42',
      );

      final amina = MessagesService.instance.thread('@amina_stream').single;
      expect(amina.text, 'https://omniversify.com/c/42');
      expect(amina.fromMe, isTrue);
      // Omar's conversation had a message before, so the share joins it.
      final omar = MessagesService.instance.thread('@omar_gamer');
      expect(omar, hasLength(2));
      expect(omar.last.text, 'https://omniversify.com/c/42');
      expect(omar.first.fromMe, isFalse);

      // Conversations nobody picked keep what they already had.
      expect(MessagesService.instance.thread('@ahmed_m').single.fromMe, isFalse);

      // …and it is still there after the app is reopened.
      MessagesService.instance.reset();
      await MessagesService.instance.init();
      expect(MessagesService.instance.thread('@amina_stream'), hasLength(1));
    });

    test('opening a thread takes it off the unread list', () async {
      await MessagesService.instance.init();
      expect(MessagesService.instance.unread.value, contains('@sara_dev'));

      await MessagesService.instance.markRead('@sara_dev');

      expect(
        MessagesService.instance.unread.value,
        isNot(contains('@sara_dev')),
      );
    });

    test('a file with no words counts as nothing to send', () {
      const nothing = SharedIn();
      expect(nothing.fileOnly, isTrue);
      expect(nothing.preview, isEmpty);

      const link = SharedIn(text: ' https://example.com/x ');
      expect(link.fileOnly, isFalse);
      expect(link.looksLikeLink, isTrue);
      expect(link.preview, 'https://example.com/x');
    });
  });

  group('share sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      // Tall phone viewport so every row of the sheet fits on screen.
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const ValueKey('open-share'),
                onPressed: () => ShareSheet.show(
                  context,
                  shareText: 'https://reels.example.com/x',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('open-share')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('https://reels.example.com/x'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    }

    testWidgets('you pick people and the link lands in their threads',
        (tester) async {
      await MessagesService.instance.init();
      await openSheet(tester);

      // Nothing picked: sending is not possible yet.
      await tester.tap(find.byKey(const ValueKey('share-send')));
      await tester.pump();
      expect(MessagesService.instance.thread('@omar_gamer'), hasLength(1));

      await tester
          .tap(find.byKey(const ValueKey('share-person-@amina_stream')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('share-person-@omar_gamer')));
      await tester.pump();

      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('share-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The sheet closes, the confirmation lands behind it, and both threads
      // now hold the link.
      expect(find.text('Share'), findsNothing);
      expect(find.text('Sent to Omar, Amina'), findsOneWidget);
      expect(
        MessagesService.instance.thread('@amina_stream').single.text,
        'https://reels.example.com/x',
      );
      expect(
        MessagesService.instance.thread('@omar_gamer').last.fromMe,
        isTrue,
      );
      // Nobody else was picked.
      expect(MessagesService.instance.thread('@ahmed_m'), hasLength(1));
    });

    testWidgets('a share arriving from another app is what opens the picker',
        (tester) async {
      const name = 'omniversify/share_in';
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(name), (call) async {
        // The "listen" Android needs before it starts pushing shares.
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(const MethodChannel(name), null));
      // The subscription must not outlive the run.
      addTearDown(ShareInService.instance.dispose);

      ShareInService.instance.init();
      await tester.pump();

      // …as if Instagram had just chosen Omniversify in its share sheet.
      await messenger.handlePlatformMessage(
        name,
        codec.encodeSuccessEnvelope(
          const {
            'text': 'Check this reel https://reels.example.com/y',
            'subject': 'Instagram',
          },
        ),
        (data) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final share = ShareInService.instance.incoming.value;
      expect(share, isNotNull);
      expect(share!.text, 'Check this reel https://reels.example.com/y');
      expect(share.subject, 'Instagram');
      expect(share.fileOnly, isFalse);

      ShareInService.instance.consume();
      expect(ShareInService.instance.incoming.value, isNull);
    });
  });
}
