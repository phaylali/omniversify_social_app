import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/series_tracking_screen.dart';
import 'package:omniversify_social_app/screens/tracker_screen.dart';
import 'package:omniversify_social_app/screens/upcoming_tab.dart';
import 'package:omniversify_social_app/services/episode_tracker_service.dart';
import 'package:omniversify_social_app/services/tracker_collection_service.dart';
import 'package:omniversify_social_app/services/tracker_tabs.dart';

/// A future air date, written the way the API writes dates.
String isoIn(int days) {
  final date = DateTime.now().add(Duration(days: days));
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

SeriesEpisode episode(
  String key, {
  String? date,
  String? title,
  int number = 1,
}) {
  final digits = int.parse(key.substring(1));
  return SeriesEpisode(
    seasonKey: 'S01',
    episodeKey: key,
    seasonNumber: 1,
    episodeNumber: digits,
    date: date,
    title: title,
  );
}

void setUpCleanPrefs() {
  SharedPreferences.setMockInitialValues({});
  TrackerCollectionService.instance.reset();
  EpisodeTrackerService.instance.reset();
}

/// A scrollable tab strip is wider than a phone, so scroll the tab into view
/// before tapping it — exactly what a thumb does. Two pump rounds follow: one
/// for the page change, one for the page's own first load.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(setUpCleanPrefs);

  // ─── Which tabs each category gets ───────────────────────

  test('series and anime keep Discovery, Upcoming, Watching, Watched', () {
    expect(
      trackerTabsFor('tv').labels,
      ['Discovery', 'Upcoming', 'Watching', 'Watched'],
    );
    expect(
      trackerTabsFor('anime').labels,
      ['Discovery', 'Upcoming', 'Watching', 'Watched'],
    );
  });

  test('books read, games travel Wishlist → Owned → Played', () {
    expect(trackerTabsFor('books').labels,
        ['Discovery', 'Reading', 'Read']);
    expect(
      trackerTabsFor('games').labels,
      ['Discovery', 'Wishlist', 'Owned', 'Played'],
    );
    expect(trackerTabsFor('movies').labels,
        ['Discovery', 'Watchlist', 'Watched']);
    expect(trackerTabsFor('podcasts').labels,
        ['Discovery', 'Listening', 'Listened']);
    expect(trackerTabsFor('music').labels, ['Discovery', 'Playlists']);
    expect(trackerTabsFor(null).labels, ['Discovery', 'Wishlist', 'Library']);
  });

  test('every shelf says what it is for', () {
    for (final category in const [
      'tv',
      'anime',
      'books',
      'movies',
      'games',
      'podcasts',
      'music',
    ]) {
      for (final slot in trackerTabsFor(category).slots) {
        expect(slot.empty, isNotEmpty, reason: slot.label);
        expect(slot.label, isNotEmpty);
      }
    }
  });

  // ─── Shelves ─────────────────────────────────────────────

  test('a title sits on one shelf at a time', () async {
    final service = TrackerCollectionService.instance;
    const show = {'id': 42, 'name': 'The Test Show'};

    await service.add('tv', show, 'watching');
    expect(await service.contains('tv', 42, 'watching'), isTrue);

    await service.add('tv', show, 'watched');
    expect(await service.contains('tv', 42, 'watched'), isTrue);
    expect(await service.contains('tv', 42, 'watching'), isFalse);
  });

  test('toggling adds then takes away', () async {
    final service = TrackerCollectionService.instance;
    const book = {'id': 7, 'title': 'Dune'};

    expect(await service.toggle('books', book, 'reading'), isTrue);
    expect(await service.contains('books', 7, 'reading'), isTrue);
    expect(await service.toggle('books', book, 'reading'), isFalse);
    expect(await service.contains('books', 7, 'reading'), isFalse);
    expect(await service.itemsFor('books', 'reading'), isEmpty);
  });

  test('the old wishlist and library move onto the new shelves', () async {
    SharedPreferences.setMockInitialValues({
      'tracker_wishlist_v1': '{"books":[{"id":1,"title":"Wish"}]}',
      'tracker_library_v1':
          '{"books":[{"id":2,"title":"Done"}],"games":[{"id":3,"name":"Ow"}]}',
    });
    TrackerCollectionService.instance.reset();
    final service = TrackerCollectionService.instance;

    // A wishlist is still to get to; a library is already had.
    expect((await service.itemsFor('books', 'reading')).single['title'],
        'Wish');
    expect((await service.itemsFor('books', 'read')).single['title'], 'Done');
    // Games keep Owned for what you have, not the last shelf.
    expect((await service.itemsFor('games', 'owned')).single['name'], 'Ow');
    expect(await service.itemsFor('games', 'played'), isEmpty);
  });

  test('playlists hold tracks, once each, and can be emptied', () async {
    final service = TrackerCollectionService.instance;
    const track = {'id': 5, 'title': 'Song'};

    expect(await service.createPlaylist('  Road trip '), isTrue);
    expect(await service.createPlaylist('Road trip'), isFalse);
    expect(await service.createPlaylist('   '), isFalse);

    expect(await service.addToPlaylist('Road trip', track), isTrue);
    expect(await service.addToPlaylist('Road trip', track), isFalse);
    expect(await service.playlistCount('Road trip'), 1);
    expect(await service.inPlaylist('Road trip', 5), isTrue);
    expect(await service.playlists(), ['Road trip']);

    expect(await service.removeFromPlaylist('Road trip', 5), isTrue);
    expect(await service.removeFromPlaylist('Road trip', 5), isFalse);
    expect(await service.deletePlaylist('Road trip'), isTrue);
    expect(await service.playlists(), isEmpty);
  });

  // ─── Airing ──────────────────────────────────────────────

  test('an episode airs today or any time before', () {
    expect(isAired(isoIn(-30)), isTrue);
    expect(isAired(isoIn(0)), isTrue);
    expect(isAired(isoIn(1)), isFalse);
    expect(isAired(isoIn(5)), isFalse);
    // Nothing readable means nothing to wait for.
    expect(isAired(null), isTrue);
    expect(isAired(''), isTrue);
    expect(isAired('TBA'), isTrue);
    expect(isAired('sometime'), isTrue);
  });

  test('days left counts up from tomorrow and stops at airing', () {
    expect(daysUntilAired(isoIn(-1)), isNull);
    expect(daysUntilAired(isoIn(0)), isNull);
    expect(daysUntilAired(isoIn(1)), 1);
    expect(daysUntilAired(isoIn(9)), 9);
    expect(daysUntilAired(null), isNull);
    expect(daysLeftText(1), 'in 1 day');
    expect(daysLeftText(6), 'in 6 days');
  });

  test('the upcoming rows are only the ones still to come, soonest first',
      () {
    final series = {'id': 1, 'name': 'Test Show'};
    final rows = [
      {'episode': 'E01', 'date': isoIn(-40)},
      {'episode': 'E02', 'date': isoIn(9)},
      {'episode': 'E03', 'date': isoIn(2)},
      {'episode': 'E04', 'date': null},
      {'episode': 'E05', 'date': 'TBA'},
      {'episode': 'E06', 'date': isoIn(2)},
    ];

    final upcoming = upcomingEpisodes(series, rows);

    expect(
      upcoming.map((e) => e.episode.key).toList(),
      ['E03', 'E06', 'E02'],
    );
    expect(upcoming.first.days, 2);
    expect(upcoming.last.days, 9);
    expect(upcoming.every((e) => e.series['name'] == 'Test Show'), isTrue);
  });

  // ─── The page itself ─────────────────────────────────────

  testWidgets('the series tracker opens with its four tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Series',
        icon: Icons.tv_outlined,
        accentColor: Color(0xFF6C8CFF),
        apiCategory: 'tv',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final labels =
        tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
    expect(labels, ['Discovery', 'Upcoming', 'Watching', 'Watched']);

    // Watching starts empty, and says so in its own words.
    await tapTab(tester, 'Watching');
    expect(find.textContaining('tick an episode'), findsOneWidget);
  });

  testWidgets('music opens on Discovery and Playlists', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Music',
        icon: Icons.music_note_outlined,
        accentColor: Color(0xFFB15CFF),
        apiCategory: 'music',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final labels =
        tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
    expect(labels, ['Discovery', 'Playlists']);
    // No collection shelves — there is no Wishlist here any more.
    expect(find.text('Wishlist'), findsNothing);

    await tapTab(tester, 'Playlists');
    expect(find.byKey(const ValueKey('new-playlist')), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
  });

  testWidgets('a playlist is named from the Playlists tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Music',
        icon: Icons.music_note_outlined,
        accentColor: Color(0xFFB15CFF),
        apiCategory: 'music',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tapTab(tester, 'Playlists');

    await tester.tap(find.byKey(const ValueKey('new-playlist')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The name travels: dialog closes, the playlist is written, the tab
    // reloads — give each of those a frame of its own.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(await TrackerCollectionService.instance.playlists(), ['Road trip']);
    expect(find.byKey(const ValueKey('playlist-Road trip')), findsOneWidget);
  });

  testWidgets('the detail dialog offers the shelves this category has',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () => showMediaDetailDialog(
                context: context,
                category: 'games',
                item: const {'id': 3, 'name': 'Hollow'},
                accent: const Color(0xFF107C10),
                collection: TrackerCollectionService.instance,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Wishlist'), findsWidgets);
    expect(find.text('Owned'), findsWidgets);
    expect(find.text('Played'), findsWidgets);
    expect(find.text('Library'), findsNothing);
  });

  // ─── Ticking ─────────────────────────────────────────────

  testWidgets('an episode that has not aired cannot be ticked',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: SeriesTrackingScreen(
        category: 'tv',
        item: const {'id': 9, 'name': 'The Test Show'},
        accent: const Color(0xFF6C8CFF),
        episodes: [
          episode('E01', date: isoIn(-7), title: 'Out already'),
          episode('E02', date: isoIn(3), title: 'Still to come'),
        ],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final aired =
        tester.widget<CheckboxListTile>(find.byKey(const ValueKey('ep-S01E01')));
    final pending =
        tester.widget<CheckboxListTile>(find.byKey(const ValueKey('ep-S01E02')));

    expect(aired.onChanged, isNotNull);
    expect(pending.onChanged, isNull);
    expect(find.textContaining('in 3 days'), findsOneWidget);

    // Season marking skips the future one entirely.
    await tester.tap(find.byKey(const ValueKey('season-S01-mark')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final tracker = EpisodeTrackerService.instance;
    expect(tracker.isWatched('tv:9', 'S01E01'), isTrue);
    expect(tracker.isWatched('tv:9', 'S01E02'), isFalse);
  });

  testWidgets('checkmarks carry a series from Watching to Watched',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final collection = TrackerCollectionService.instance;
    await tester.pumpWidget(MaterialApp(
      home: SeriesTrackingScreen(
        category: 'tv',
        item: const {'id': 11, 'name': 'Two Parter'},
        accent: const Color(0xFF6C8CFF),
        episodes: [
          episode('E01', date: isoIn(-30)),
          episode('E02', date: isoIn(-30)),
        ],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('ep-S01E01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(await collection.contains('tv', 11, 'watching'), isTrue);
    expect(await collection.contains('tv', 11, 'watched'), isFalse);

    await tester.tap(find.byKey(const ValueKey('ep-S01E02')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(await collection.contains('tv', 11, 'watched'), isTrue);
    expect(await collection.contains('tv', 11, 'watching'), isFalse);

    // Taking one back puts the show on Watching again.
    await tester.tap(find.byKey(const ValueKey('ep-S01E02')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(await collection.contains('tv', 11, 'watching'), isTrue);
    expect(await collection.contains('tv', 11, 'watched'), isFalse);
  });

  // ─── Upcoming ────────────────────────────────────────────

  testWidgets('upcoming with nothing followed says how to start', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: UpcomingTab(
        apiCategory: 'tv',
        accent: Color(0xFF6C8CFF),
        title: 'Series',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Nothing on the horizon'), findsOneWidget);
    expect(find.textContaining('Watching'), findsOneWidget);
  });

  testWidgets('upcoming lists what a followed series has left to air',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await TrackerCollectionService.instance
        .add('tv', const {'id': 68261, 'name': 'The Boys'}, 'watching');

    await tester.pumpWidget(const MaterialApp(
      home: UpcomingTab(
        apiCategory: 'tv',
        accent: Color(0xFF6C8CFF),
        title: 'Series',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The backend is not answering in a test, so nothing can be counted
    // down — but the series is known, and the tab says so rather than
    // pretending it looked.
    expect(find.textContaining('Everything your 1 series'), findsOneWidget);
    expect(find.textContaining('Nothing on the horizon'), findsNothing);
  });
}
