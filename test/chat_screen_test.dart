import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/main.dart';
import 'package:omniversify_social_app/screens/account_screen.dart';
import 'package:omniversify_social_app/screens/chat_screen.dart';
import 'package:omniversify_social_app/services/messages_service.dart';

import 'account_fixtures.dart';

/// Opens the DMs drawer the way the menu button does.
Future<void> _openDrawer(WidgetTester tester) async {
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
}

Future<void> _openChat(WidgetTester tester, {String handle = '@ahmed_m'}) async {
  await tester.pumpWidget(MaterialApp(
    home: ChatScreen(handle: handle, name: MessagesService.nameFor(handle)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessagesService.instance.reset();
    // Sending anything needs a confirmed email now — these tests are about
    // the thread, not the gate, so they start already signed in.
    signInForTest();
  });

  group('DMs drawer', () {
    testWidgets('the conversations are there before anything has been sent',
        (tester) async {
      // setUp only resets. Nothing has hydrated the thread map yet — the
      // exact state a cold start opens the drawer in.
      await _openDrawer(tester);

      expect(find.byKey(const ValueKey('dm-@ahmed_m')), findsOneWidget);
      expect(find.text("Sure, let's watch it together!"), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
    });

    testWidgets('every conversation with something in it is listed',
        (tester) async {
      await MessagesService.instance.init();
      await _openDrawer(tester);

      expect(find.byKey(const ValueKey('dm-@ahmed_m')), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-@karim_w')), findsOneWidget);
      expect(find.text("Sure, let's watch it together!"), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
      // Nobody has a thread yet, so she isn't a conversation.
      expect(find.byKey(const ValueKey('dm-@amina_stream')), findsNothing);
    });

    testWidgets('tapping a conversation opens the chat over the drawer',
        (tester) async {
      await MessagesService.instance.init();
      await _openDrawer(tester);

      await tester.tap(find.byKey(const ValueKey('dm-@sara_dev')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('I just finished the book!'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);
      // Opening it clears the unread flag that made the row bold.
      expect(
        MessagesService.instance.unread.value,
        isNot(contains('@sara_dev')),
      );
    });

    testWidgets('an acquaintance opens the same way', (tester) async {
      await MessagesService.instance.init();
      await _openDrawer(tester);

      await tester.tap(find.text('Acquaintances'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The activity block sits above the list, so scroll her into view.
      final row = find.byKey(const ValueKey('acq-@amina_stream'));
      await tester.dragUntilVisible(
        row,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ChatScreen), findsOneWidget);
      // No conversation yet, so the screen invites the first message.
      expect(find.text('Say hi to Amina 👋'), findsOneWidget);
    });
  });

  group('chat', () {
    testWidgets('the history is waiting before the first message is sent',
        (tester) async {
      // No init() here either: opening a conversation has to load it.
      await _openChat(tester);

      expect(find.text("Sure, let's watch it together!"), findsOneWidget);
      expect(find.text('Say hi to Ahmed 👋'), findsNothing);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the day chip heads its group instead of trailing it',
        (tester) async {
      await _openChat(tester);

      // The list is reversed, so a chip emitted before its group would sit at
      // the bottom — underneath the very messages it is meant to head.
      final newest =
          MessagesService.instance.thread('@ahmed_m').last.text;
      final chip = tester.getTopLeft(find.text('Today'));
      final message = tester.getTopLeft(find.text(newest).first);

      expect(chip.dy, lessThan(message.dy));
    });

    testWidgets('sending writes into the thread and stamps it Today',
        (tester) async {
      await MessagesService.instance.init();
      await _openChat(tester);

      expect(find.text("Sure, let's watch it together!"), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Nothing to send until something is typed.
      final send = find.byKey(const ValueKey('chat-send'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);

      await tester.tap(send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('On my way'), findsOneWidget);
      expect(
        MessagesService.instance.thread('@ahmed_m').last.text,
        'On my way',
      );
      // The composer is empty again, and the send button with it.
      expect(find.widgetWithText(TextField, 'On my way'), findsNothing);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
    });

    testWidgets('the GIF button holds the left and attach stands by send',
        (tester) async {
      await _openChat(tester);

      final gif = tester.getCenter(find.byKey(const ValueKey('chat-gif')));
      final attach =
          tester.getCenter(find.byKey(const ValueKey('chat-attach')));
      final send = tester.getCenter(find.byKey(const ValueKey('chat-send')));

      expect(gif.dx, lessThan(attach.dx));
      expect(attach.dx, lessThan(send.dx));
      // The field sits between the GIF and the attach; attach and send are
      // neighbours, not two ends of the composer.
      expect(attach.dx - gif.dx, greaterThan(80));
      expect(send.dx - attach.dx, lessThan(80));
    });

    testWidgets('sending waits for a confirmed email first', (tester) async {
      signOutForTest();
      await MessagesService.instance.init();
      await _openChat(tester);

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Nothing was sent: the account screen opened instead.
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
      expect(
        MessagesService.instance
            .thread('@ahmed_m')
            .any((m) => m.text == 'On my way'),
        isFalse,
      );

      // And the draft is still in the box for when they come back
      // confirmed: backing out of the screen puts it where it was.
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.widgetWithText(TextField, 'On my way'), findsOneWidget);
      expect(find.byType(AccountScreen), findsNothing);
    });

    testWidgets('the conversation menu can clear it', (tester) async {
      await MessagesService.instance.init();
      await _openChat(tester);

      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Clear conversation'), findsOneWidget);
      expect(find.text('Report user'), findsOneWidget);

      await tester.tap(find.text('Clear conversation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(MessagesService.instance.thread('@ahmed_m'), isEmpty);
      expect(find.text('Say hi to Ahmed 👋'), findsOneWidget);
    });

    testWidgets('a share lands here as an ordinary message', (tester) async {
      await MessagesService.instance.shareTo(
        const ['@amina_stream'],
        'https://reels.example.com/y',
      );
      await _openChat(tester, handle: '@amina_stream');

      expect(find.text('https://reels.example.com/y'), findsOneWidget);
      expect(find.text('Say hi to Amina 👋'), findsNothing);
      // Sent by me, so it sits on the right.
      expect(MessagesService.instance.thread('@amina_stream').last.fromMe,
          isTrue);
    });
  });
}
