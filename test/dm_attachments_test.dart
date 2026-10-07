import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/main.dart';
import 'package:omniversify_social_app/screens/chat_screen.dart';
import 'package:omniversify_social_app/services/messages_service.dart';

import 'account_fixtures.dart';

Future<void> _openChat(WidgetTester tester, {String handle = '@ahmed_m'}) async {
  await tester.pumpWidget(MaterialApp(
    home: ChatScreen(handle: handle, name: MessagesService.nameFor(handle)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Opens the attach menu the way the paperclip does.
Future<void> _openAttachMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-attach')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessagesService.instance.reset();
    signInForTest();
  });

  group('DM attachments', () {
    testWidgets('the paperclip offers a photo, a video, a file and a voice note',
        (tester) async {
      await MessagesService.instance.init();
      await _openChat(tester);
      await _openAttachMenu(tester);

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Voice note'), findsOneWidget);
      expect(find.text('From your gallery'), findsNWidgets(2));
      expect(find.text('Record it instead of typing it'), findsOneWidget);
    });

    testWidgets('the voice note sheet waits to be started', (tester) async {
      await MessagesService.instance.init();
      await _openChat(tester);
      await _openAttachMenu(tester);

      await tester.tap(find.text('Voice note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Nothing has asked for the microphone yet, so there is no spinner to
      // sit behind and no timer pretending to run.
      expect(find.text('Say it instead of typing it.'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-cancel')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-timer')), findsNothing);
      expect(find.byKey(const ValueKey('voice-send')), findsNothing);

      // Backing out leaves the conversation untouched.
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        MessagesService.instance
            .thread('@ahmed_m')
            .where((m) => m.hasAttachment),
        isEmpty,
      );
    });

    testWidgets('a voice note arrives with no words and the drawer still names it',
        (tester) async {
      await MessagesService.instance.init();
      await MessagesService.instance.sendAttachment(
        '@ahmed_m',
        attachment: ChatAttachment.audio,
        path: '/tmp/voice.m4a',
        seconds: 7,
      );

      await _openChat(tester);

      // No caption, so the bubble carries the recording alone.
      expect(find.byKey(const ValueKey('bubble-audio')), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      expect(MessagesService.instance.lastOf('@ahmed_m')!.text, isEmpty);

      // Back out to the drawer: the line under the name still says what it is.
      expect(
        MessagesService.instance.lastOf('@ahmed_m')!.label,
        'Voice note · 0:07',
      );
    });

    testWidgets('a photo and a file get their own bubbles', (tester) async {
      await MessagesService.instance.init();
      await MessagesService.instance
          .sendAttachment('@sara_dev', attachment: ChatAttachment.image, path: '/tmp/a.jpg', name: 'IMG_0042.jpg');
      await MessagesService.instance
          .sendAttachment('@sara_dev', attachment: ChatAttachment.file, path: '/tmp/r.pdf', name: 'report.pdf');

      await _openChat(tester, handle: '@sara_dev');

      expect(find.byKey(const ValueKey('bubble-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-file')), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);

      // Nothing was typed with either, so there is no text to copy.
      await tester.longPress(find.byKey(const ValueKey('bubble-file')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.text('Copy text'), findsNothing);
    });

    testWidgets('clearing a conversation clears its attachments too',
        (tester) async {
      await MessagesService.instance.init();
      await MessagesService.instance
          .sendAttachment('@omar_gamer', attachment: ChatAttachment.video, path: '/tmp/v.mp4', name: 'clip.mp4');
      expect(MessagesService.instance.thread('@omar_gamer'), isNotEmpty);

      await _openChat(tester, handle: '@omar_gamer');
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Clear conversation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(MessagesService.instance.thread('@omar_gamer'), isEmpty);
      expect(find.byKey(const ValueKey('bubble-video')), findsNothing);
    });

    testWidgets('the drawer line under the name reads as what was sent',
        (tester) async {
      await MessagesService.instance.init();
      await MessagesService.instance.sendAttachment(
        '@ahmed_m',
        attachment: ChatAttachment.audio,
        path: '/tmp/voice.m4a',
        seconds: 7,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          endDrawer: const DmsDrawer(),
          body: Builder(
            builder: (context) => Center(
              child: IconButton(
                key: const ValueKey('open-drawer'),
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-drawer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const ValueKey('dm-@ahmed_m')), findsOneWidget);
      expect(find.text('Voice note · 0:07'), findsOneWidget);
    });

    testWidgets('the long-press menu still copies words when there are some',
        (tester) async {
      await MessagesService.instance.init();
      await _openChat(tester);

      final bubble = find.text("Sure, let's watch it together!");
      await tester.longPress(bubble);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Delete for me'), findsOneWidget);
    });
  });

  group('attachment messages', () {
    test('a message keeps its attachment through a save and a reload', () {
      final message = ChatMessage(
        text: '',
        fromMe: true,
        at: DateTime(2026, 10, 7, 21, 4),
        attachment: ChatAttachment.audio,
        path: '/docs/shared/voice.m4a',
        seconds: 64,
      );

      final reloaded = ChatMessage.fromJson(message.toJson());

      expect(reloaded.attachment, ChatAttachment.audio);
      expect(reloaded.path, '/docs/shared/voice.m4a');
      expect(reloaded.seconds, 64);
      expect(reloaded.label, 'Voice note · 1:04');
      expect(reloaded.hasAttachment, isTrue);
    });

    test('a message written before attachments still reads as one', () {
      final plain = ChatMessage.fromJson(const {
        'text': 'hello',
        'fromMe': false,
        'at': '2026-10-07T21:04:00.000',
      });

      expect(plain.attachment, isNull);
      expect(plain.hasAttachment, isFalse);
      expect(plain.label, 'hello');
    });

    test('a file keeps its name, a photo does not need one', () {
      expect(
        ChatMessage(
          text: '',
          fromMe: true,
          at: DateTime(2026),
          attachment: ChatAttachment.file,
          path: '/docs/shared/r.pdf',
          name: 'report.pdf',
        ).label,
        'File · report.pdf',
      );
      expect(
        ChatMessage(
          text: '',
          fromMe: true,
          at: DateTime(2026),
          attachment: ChatAttachment.image,
          path: '/docs/shared/i.jpg',
        ).label,
        'Photo',
      );
    });

    test('an attachment from a future version reads as a plain message', () {
      final message = ChatMessage.fromJson(const {
        'text': '',
        'fromMe': true,
        'at': '2026-10-07T21:04:00.000',
        'attachment': 'hologram',
        'path': '/docs/shared/x',
      });

      expect(message.attachment, isNull);
      expect(message.hasAttachment, isFalse);
    });

    test('nothing can be sent without a path', () async {
      SharedPreferences.setMockInitialValues({});
      MessagesService.instance.reset();
      await MessagesService.instance.init();

      await MessagesService.instance.sendAttachment(
        '@ahmed_m',
        attachment: ChatAttachment.image,
        path: '',
      );

      expect(MessagesService.instance.thread('@ahmed_m').where((m) => m.hasAttachment),
          isEmpty);
    });
  });

  group('staged attachment', () {
    Future<void> pumpStaged(
      WidgetTester tester, {
      required ChatAttachment kind,
      String? name,
      int? seconds,
    }) async {
      final cs = ThemeData().colorScheme;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StagedAttachmentBar(
            kind: kind,
            path: kind == ChatAttachment.audio
                ? '/tmp/voice.m4a'
                : '/docs/report.pdf',
            name: name,
            seconds: seconds,
            cs: cs,
            gold: cs.primary,
            onRemove: () {},
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a staged voice note can be listened to before it is sent',
        (tester) async {
      await pumpStaged(tester, kind: ChatAttachment.audio, seconds: 7);

      expect(find.byKey(const ValueKey('chat-attach-preview')), findsOneWidget);
      expect(find.text('Voice note · 0:07'), findsOneWidget);
      expect(find.text('Tap to listen before sending'), findsOneWidget);

      // Playing it is not sending it, and it does not drop the note either.
      await tester.tap(find.byKey(const ValueKey('chat-attach-preview')));
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-attach-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-attach-remove')), findsOneWidget);
    });

    testWidgets('anything that cannot be played shows the plain row',
        (tester) async {
      await pumpStaged(tester, kind: ChatAttachment.file, name: 'report.pdf');

      expect(find.byKey(const ValueKey('chat-attach-preview')), findsNothing);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('Ready to send'), findsOneWidget);
    });
  });
}
