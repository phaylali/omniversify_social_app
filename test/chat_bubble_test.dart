import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/chat_screen.dart';
import 'package:omniversify_social_app/services/messages_service.dart';

import 'account_fixtures.dart';

/// The decoration of the bubble [finder] sits in: the decorated container
/// walked up to from whatever is on show inside it.
BoxDecoration bubbleAround(WidgetTester tester, Finder finder) {
  BoxDecoration? found;
  tester.element(finder).visitAncestorElements((node) {
    final widget = node.widget;
    if (widget is Container && widget.decoration is BoxDecoration) {
      found = widget.decoration as BoxDecoration;
      return false;
    }
    return true;
  });
  final decoration = found;
  if (decoration == null) fail('no bubble around $finder');
  return decoration;
}

BoxDecoration bubbleOf(WidgetTester tester, String text) =>
    bubbleAround(tester, find.text(text));

Future<void> _openChat(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home:
        ChatScreen(handle: '@ahmed_m', name: MessagesService.nameFor('@ahmed_m')),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessagesService.instance.reset();
    signInForTest();
  });

  testWidgets('a message of mine is a fifth of the gold, barely visible',
      (tester) async {
    await MessagesService.instance.init();
    await MessagesService.instance.send('@ahmed_m', 'On my way');
    await _openChat(tester);

    final mine = bubbleOf(tester, 'On my way');

    // 0.2 of the gold: a wash you can just make out, nothing more.
    expect(mine.color?.a, moreOrLessEquals(0.2, epsilon: 0.005));
    expect(mine.border, isNull);
  });

  testWidgets('a message of theirs is an outline with nothing behind it',
      (tester) async {
    await MessagesService.instance.init();
    await _openChat(tester);

    final theirs = bubbleOf(tester, "Sure, let's watch it together!");

    expect(theirs.color, Colors.transparent);
    expect(theirs.border, isNotNull);
    expect((theirs.border as Border).top.color.a,
        moreOrLessEquals(110 / 255, epsilon: 0.005));
  });

  testWidgets('a photo is still the picture: no fill and no outline for mine',
      (tester) async {
    await MessagesService.instance.init();
    await MessagesService.instance.sendAttachment(
      '@ahmed_m',
      attachment: ChatAttachment.image,
      path: '/docs/shared/lanterns.jpg',
    );
    await _openChat(tester);

    final mine = bubbleAround(tester, find.byKey(const ValueKey('bubble-image')));

    expect(mine.color, Colors.transparent);
    expect(mine.border, isNull);
  });
}
