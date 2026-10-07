import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omniversify_social_app/widgets/video_player.dart';

/// A video opens quiet, and the corner of it says so: the switch is the one
/// control that is never hidden behind a tap, because sound being off is a
/// thing the person needs to see and be able to undo at a glance.
void main() {
  /// Pumps the switch around a flag the test can read back after tapping.
  Future<void> pumpSwitch(WidgetTester tester, ValueNotifier<bool> muted) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: muted,
          builder: (context, value, _) => MuteButton(
            muted: value,
            onToggle: () => muted.value = !muted.value,
          ),
        ),
      ),
    ));
  }

  testWidgets('a quiet video offers the way back to sound', (tester) async {
    final muted = ValueNotifier(true);
    addTearDown(muted.dispose);
    await pumpSwitch(tester, muted);

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();

    expect(muted.value, isFalse);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('a video that is audible offers a way to silence it',
      (tester) async {
    final muted = ValueNotifier(false);
    addTearDown(muted.dispose);
    await pumpSwitch(tester, muted);

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();

    expect(muted.value, isTrue);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
  });

  testWidgets('the bare variant for media_kit\'s bar behaves the same',
      (tester) async {
    final muted = ValueNotifier(true);
    addTearDown(muted.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: muted,
          builder: (context, value, _) => MuteButton(
            muted: value,
            filled: false,
            onToggle: () => muted.value = !muted.value,
          ),
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('video-mute')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-mute')));
    await tester.pump();

    expect(muted.value, isFalse);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });
}
