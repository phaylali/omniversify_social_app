import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/integrations_screen.dart';
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
        ['Discovery', 'To read', 'Reading', 'Read']);
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

    // A wishlist is still to get to — that is exactly what To read means;
    // a library is already had.
    expect((await service.itemsFor('books', 'to_read')).single['title'],
        'Wish');
    expect(await service.itemsFor('books', 'reading'), isEmpty);
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

  // ─── Importing a library ──────────────────────────────────

  test('an import lands a whole shelf in one write', () async {
    final service = TrackerCollectionService.instance;
    await service.add(
        'games', const {'id': 1, 'name': 'Still wished'}, 'wishlist');

    final added = await service.addAll('games', [
      {'id': 2, 'name': 'Portal 2', 'owned_minutes': 90, 'last_played': '2024-05-01'},
      {'id': 3, 'name': 'Hades'},
      {'id': 3, 'name': 'Hades again'},  // the same game, twice in the batch
    ], 'owned');

    // One new row each, in the order Steam sent them.
    expect(added, 2);
    final owned = await service.itemsFor('games', 'owned');
    expect(owned.map((e) => e['id']).toList(), [2, 3]);
    // The minutes with it, and the last evening, travel with the game.
    expect(owned.first['owned_minutes'], 90);
    expect(owned.first['last_played'], '2024-05-01');
    // Anything the import did not mention keeps its own shelf.
    expect(await service.contains('games', 1, 'wishlist'), isTrue);
  });

  test('an import takes a game off the shelf it was already on', () async {
    final service = TrackerCollectionService.instance;
    await service.add(
        'games', const {'id': 9, 'name': 'Wished first'}, 'wishlist');

    await service.addAll('games', [
      {'id': 9, 'name': 'Wished first'},
    ], 'owned');

    expect(await service.contains('games', 9, 'owned'), isTrue);
    expect(await service.contains('games', 9, 'wishlist'), isFalse);
    // Already there, so nothing new was written the second time round.
    expect(
      await service.addAll('games', [
        {'id': 9, 'name': 'Wished first'},
      ], 'owned'),
      0,
    );
  });

  test('a shelf on screen hears about every write', () async {
    final service = TrackerCollectionService.instance;
    final before = service.version.value;

    await service.add('games', const {'id': 4, 'name': 'One'}, 'owned');
    expect(service.version.value, before + 1);

    await service.addAll('games', const [
      {'id': 5, 'name': 'Two'},
    ], 'owned');
    expect(service.version.value, before + 2);

    // A write that changes nothing stays quiet.
    await service.addAll('games', const [
      {'id': 5, 'name': 'Two'},
    ], 'owned');
    expect(service.version.value, before + 2);
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

  // ─── Steam ────────────────────────────────────────────────

  testWidgets('the games tracker offers the Steam import, and only on Owned',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Games',
        icon: Icons.sports_esports_outlined,
        accentColor: Color(0xFF107C10),
        apiCategory: 'games',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('steam-import')), findsOneWidget);

    await tapTab(tester, 'Owned');
    expect(find.text('Import from Steam'), findsOneWidget);

    // A shelf nothing can be imported onto offers nothing.
    await tapTab(tester, 'Wishlist');
    expect(find.text('Import from Steam'), findsNothing);
  });

  testWidgets('the Steam sheet asks for a profile and explains a failure',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Games',
        icon: Icons.sports_esports_outlined,
        accentColor: Color(0xFF107C10),
        apiCategory: 'games',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('steam-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    const profileField = ValueKey('steam-profile');
    expect(find.byKey(profileField), findsOneWidget);
    expect(find.text('They land on your Owned shelf.'), findsOneWidget);

    // Nothing typed in yet.
    await tester.tap(find.text('Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Enter a Steam profile URL or name'), findsOneWidget);

    // A profile nothing can be fetched for keeps the sheet open and says
    // why, rather than closing on an empty shelf.
    await tester.enterText(
        find.byKey(profileField), 'steamcommunity.com/id/phaylali');
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final field = tester.widget<TextField>(find.byKey(profileField));
    expect(field.decoration?.errorText, isNotNull);
    expect(find.byKey(profileField), findsOneWidget);
    expect(await TrackerCollectionService.instance.itemsFor('games', 'owned'),
        isEmpty);
  });

  testWidgets('the Owned shelf says how long you have really had a game',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await TrackerCollectionService.instance.addAll('games', const [
      {'id': 1, 'name': 'Long Loved', 'owned_minutes': 90},
      {'id': 2, 'name': 'Barely Touched', 'owned_minutes': 20},
      {'id': 3, 'name': 'Untouched', 'owned_minutes': 0},
      {'id': 4, 'name': 'Never Told Us'},
    ], 'owned');

    await tester.pumpWidget(const MaterialApp(
      home: TrackerScreen(
        title: 'Games',
        icon: Icons.sports_esports_outlined,
        accentColor: Color(0xFF107C10),
        apiCategory: 'games',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tapTab(tester, 'Owned');

    expect(find.text('1.5 h played'), findsOneWidget);
    expect(find.text('20 min played'), findsOneWidget);
    // Only Steam saying zero gets to say this — and nothing is claimed
    // where Steam told us nothing at all.
    expect(find.text('Never played'), findsOneWidget);
    expect(find.textContaining('played'), findsNWidgets(3));
  });

  testWidgets('Integrations is honest about what each service offers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Steam'), findsOneWidget);
    expect(find.text('Works now'), findsOneWidget);
    // Epic will not hand over a library to anyone, and says so.
    expect(find.text('Epic Games'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Goodreads'), findsOneWidget);
    expect(find.text('Letterboxd'), findsOneWidget);
    expect(find.text('Next'), findsNWidgets(2));
  });
}
