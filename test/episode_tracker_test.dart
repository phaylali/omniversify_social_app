import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/series_tracking_screen.dart';
import 'package:omniversify_social_app/services/episode_tracker_service.dart';

/// Two seasons, three episodes: a titled one, a bare one, and one whose
/// air date the API still hasn't filled in.
List<SeriesEpisode> _episodes() => [
      const SeriesEpisode(
        seasonKey: 'S01',
        episodeKey: 'E01',
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Pilot',
        date: '2019-01-01',
      ),
      const SeriesEpisode(
        seasonKey: 'S01',
        episodeKey: 'E02',
        seasonNumber: 1,
        episodeNumber: 2,
      ),
      const SeriesEpisode(
        seasonKey: 'S02',
        episodeKey: 'E01',
        seasonNumber: 2,
        episodeNumber: 1,
        title: 'Back',
        date: 'TBA',
      ),
    ];

const Map<String, dynamic> _show = {
  'id': 7,
  'name': 'Test Show',
  'status': 'Ended',
  'rating': 8.5,
  'runtime': 60,
  'premiered': '2019-01-01',
  'ended': '2026-01-01',
  'genres': ['Drama', 'Comedy'],
  'network': 'HBO',
};

bool _checked(WidgetTester tester, String key) =>
    tester.widget<CheckboxListTile>(find.byKey(ValueKey(key))).value ?? false;

String? _nextUp(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('track-next'))).data;

Future<void> _pumpTracking(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SeriesTrackingScreen(
        category: 'tv',
        item: _show,
        episodes: _episodes(),
      ),
    ),
  );
  // The episode list is handed to the screen, but the store still loads
  // from prefs — pump() then a beat, never pumpAndSettle (the progress bar
  // animates forever).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EpisodeTrackerService.instance.reset();
  });

  group('episode tracking store', () {
    test('a tick survives a reload from storage', () async {
      final tracker = EpisodeTrackerService.instance;
      await tracker.load();
      await tracker.setEpisode('tv:7', 'S01E01', true);
      expect(tracker.isWatched('tv:7', 'S01E01'), isTrue);
      expect(tracker.watchedCount('tv:7'), 1);

      // A reload reads what was written, not what was left in memory.
      tracker.reset();
      await tracker.load();
      expect(tracker.isWatched('tv:7', 'S01E01'), isTrue);
      expect(tracker.watchedCount('tv:7'), 1);
    });

    test('a whole season ticks and unticks in one call', () async {
      final tracker = EpisodeTrackerService.instance;
      await tracker.load();
      await tracker.setSeason('tv:7', ['S01E01', 'S01E02', 'S01E03'], true);
      expect(tracker.watchedCount('tv:7'), 3);

      await tracker.setSeason('tv:7', ['S01E02', 'S01E03'], false);
      expect(tracker.watchedCount('tv:7'), 1);
      expect(tracker.isWatched('tv:7', 'S01E01'), isTrue);
    });

    test('the same number in two catalogues stays two shows', () async {
      final tracker = EpisodeTrackerService.instance;
      await tracker.load();
      await tracker.setEpisode(
        EpisodeTrackerService.seriesKey('tv', 7),
        'S01E01',
        true,
      );
      expect(
        tracker.isWatched(EpisodeTrackerService.seriesKey('anime', 7), 'S01E01'),
        isFalse,
      );
    });

    test('clearing a series drops its whole entry', () async {
      final tracker = EpisodeTrackerService.instance;
      await tracker.load();
      await tracker.setEpisode('tv:7', 'S01E01', true);
      await tracker.clear('tv:7');
      expect(tracker.watchedCount('tv:7'), 0);
      expect(tracker.watched.value.containsKey('tv:7'), isFalse);
    });
  });

  group('episode parsing', () {
    test('the season map becomes an ordered episode list', () {
      final list = SeriesEpisode.fromEpisodeMap(const {
        'S02': {'E01': {}},
        'S01': {
          'E10': {},
          'E02': {'title': 'Second', 'date': '2020-05-04'},
        },
      });

      // Numeric order, not dictionary order: E02 before E10.
      expect(list.map((e) => e.key), ['S01E02', 'S01E10', 'S02E01']);
      expect(list.first.title, 'Second');
      expect(list.first.seasonNumber, 1);
      expect(list.first.episodeNumber, 2);
      expect(SeriesEpisode.fromEpisodeMap(null), isEmpty);
    });

    test('air dates read the way the app writes dates', () {
      expect(airDateText('2019-02-28'), '28 Feb 2019');
      expect(airDateText('2019'), '2019');
      expect(airDateText('TBA'), isNull);
      expect(airDateText(null), isNull);
      expect(airDateText('   '), isNull);
      // A month that cannot exist is left exactly as the API sent it.
      expect(airDateText('2020-13-05'), '2020-13-05');
    });
  });

  group('tracking page', () {
    testWidgets('the series details sit above its checkmarks', (tester) async {
      await _pumpTracking(tester);

      expect(find.byKey(const ValueKey('track-details')), findsOneWidget);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('★ 8.5'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
      expect(find.text('1 Jan 2019 – 1 Jan 2026'), findsOneWidget);
      expect(find.text('HBO'), findsOneWidget);
      expect(find.text('Drama · Comedy'), findsOneWidget);
      // The title is in the app bar, the episode list below it.
      expect(find.text('Test Show'), findsOneWidget);
    });

    testWidgets('progress counts as boxes are ticked', (tester) async {
      await _pumpTracking(tester);

      expect(find.byKey(const ValueKey('track-progress')), findsOneWidget);
      expect(find.text('0 of 3'), findsOneWidget);
      expect(find.text('0 of 2'), findsOneWidget); // season 1
      expect(find.text('0 of 1'), findsOneWidget); // season 2

      await tester.tap(find.byKey(const ValueKey('ep-S01E01')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(_checked(tester, 'ep-S01E01'), isTrue);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      // The air date shows up under the episode it belongs to.
      expect(find.text('1 Jan 2019'), findsOneWidget);
    });

    testWidgets('the season button ticks every episode of that season',
        (tester) async {
      await _pumpTracking(tester);

      await tester.tap(find.byKey(const ValueKey('season-S01-mark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('2 of 2'), findsOneWidget); // season 1 is full
      expect(find.text('2 of 3'), findsOneWidget); // progress
      expect(_checked(tester, 'ep-S01E01'), isTrue);
      expect(_checked(tester, 'ep-S01E02'), isTrue);
      // Season 2 is untouched.
      expect(_checked(tester, 'ep-S02E01'), isFalse);

      // Pressing it again clears that season only.
      await tester.tap(find.byKey(const ValueKey('season-S01-mark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('0 of 3'), findsOneWidget);
      expect(_checked(tester, 'ep-S01E01'), isFalse);
    });

    testWidgets('next up walks forward and ends with every episode watched',
        (tester) async {
      await _pumpTracking(tester);

      expect(_nextUp(tester), 'Season 1 · Episode 1 · Pilot');

      for (final expected in [
        'Season 1 · Episode 2',
        'Season 2 · Episode 1 · Back',
      ]) {
        await tester.tap(find.byKey(const ValueKey('mark-next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(_nextUp(tester), expected);
      }

      await tester.tap(find.byKey(const ValueKey('mark-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Every episode watched'), findsOneWidget);
      expect(find.byKey(const ValueKey('mark-next')), findsNothing);
    });

    testWidgets('the menu clears every checkmark at once', (tester) async {
      await _pumpTracking(tester);

      await tester.tap(find.byKey(const ValueKey('season-S01-mark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('track-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Clear tracking for this series'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('0 of 3'), findsOneWidget);
      expect(_checked(tester, 'ep-S01E01'), isFalse);
    });
  });
}
