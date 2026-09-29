import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniversify_social_app/models/rank.dart';
import 'package:omniversify_social_app/screens/ranks_screen.dart';

void main() {
  group('rank curve', () {
    test('there are 69 ranks and none of them is rank 0', () {
      expect(Rank.minLevel, 1);
      expect(Rank.maxLevel, 69);
      expect(Rank.all.length, 69);
      expect(Rank.gaps.length, Rank.maxLevel);
      expect(Rank.totals.length, Rank.maxLevel + 1);
      // Everyone starts on rank 1 for free.
      expect(Rank.xpForLevel(Rank.minLevel), 0);
      expect(Rank.fromLevel(0).level, Rank.minLevel);
      expect(Rank.levelForXp(0), Rank.minLevel);
      expect(Rank.levelForXp(-5), Rank.minLevel);
    });

    test('the final total is exactly 69,420,767 XP', () {
      expect(Rank.finalTotal, 69420767);
      expect(Rank.xpForLevel(Rank.maxLevel), 69420767);
      // The last rank is reached, not surpassed.
      expect(Rank.levelForXp(Rank.finalTotal), Rank.maxLevel);
      expect(Rank.levelForXp(Rank.finalTotal - 1), Rank.maxLevel - 1);
      expect(Rank.levelForXp(Rank.xpForLevel(10)), 10);
    });

    test('gaps never reset at a tier and grow by about 1.2x', () {
      for (var i = 1; i < Rank.gaps.length; i++) {
        final ratio = Rank.gaps[i] / Rank.gaps[i - 1];
        expect(ratio, greaterThan(1.15), reason: 'gap $i must keep growing');
        expect(ratio, lessThan(1.25), reason: 'gap $i must stay on 1.2x');
      }
    });

    test('tiers are 20 levels wide until black', () {
      expect(Rank.fromLevel(1).tier, RankTier.bronze);
      expect(Rank.fromLevel(19).tier, RankTier.bronze);
      expect(Rank.fromLevel(20).tier, RankTier.silver);
      expect(Rank.fromLevel(39).tier, RankTier.silver);
      expect(Rank.fromLevel(40).tier, RankTier.gold);
      expect(Rank.fromLevel(59).tier, RankTier.gold);
      expect(Rank.fromLevel(60).tier, RankTier.black);
      expect(Rank.fromLevel(69).tier, RankTier.black);
    });

    test('every rank has its insignia asset on disk', () {
      for (final rank in Rank.all) {
        expect(
          File(rank.assetPath).existsSync(),
          isTrue,
          reason: 'missing ${rank.assetPath}',
        );
      }
    });
  });

  testWidgets('ranks page frames the profile rank it was opened with',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RanksScreen(highlightLevel: 69, highlightHandle: '@amina_stream'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LEVEL 69'), findsOneWidget);
    // The framed row is tagged with that profile's handle.
    expect(find.text('@amina_stream'), findsOneWidget);
    expect(find.text('69 RANKS'), findsOneWidget);
    expect(find.text('69,420,767 XP TO THE LAST'), findsOneWidget);
    // The top rank has no next step.
    expect(find.text('MAX'), findsOneWidget);
  });
}
