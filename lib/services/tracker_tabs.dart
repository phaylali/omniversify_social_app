import 'package:flutter/material.dart';

/// One list a category keeps its items in — the `Reading` shelf, the `Owned`
/// pile — named the way people actually talk about that medium.
///
/// A slot is both a tab on the tracker screen and a button in the detail
/// dialog, so the words only ever exist once.
class TrackerSlot {
  const TrackerSlot({
    required this.id,
    required this.label,
    required this.icon,
    required this.empty,
  });

  /// Storage key: 'reading', 'watched', 'owned'…
  final String id;

  /// What it is called on screen.
  final String label;

  final IconData icon;

  /// Shown when the list is empty.
  final String empty;
}

/// How one category's tracker screen is laid out.
///
/// Every category opens on Discovery and then keeps its own collections in
/// its own words: a series is Upcoming / Watching / Watched, a game travels
/// Wishlist → Owned → Played, music skips collections for playlists.
class TrackerTabs {
  const TrackerTabs({
    this.slots = const [],
    this.upcoming = false,
    this.playlists = false,
  });

  /// The collections, in tab order (Discovery always comes first).
  final List<TrackerSlot> slots;

  /// Series and anime: episodes that have not aired yet, counted down in days.
  final bool upcoming;

  /// Music: named playlists instead of collections.
  final bool playlists;

  /// Tab labels, Discovery first — what the TabBar shows.
  List<String> get labels => [
        'Discovery',
        if (upcoming) 'Upcoming',
        for (final slot in slots) slot.label,
        if (playlists) 'Playlists',
      ];

  /// True when this screen has nothing but Discovery (no API to collect from).
  bool get discoveryOnly => slots.isEmpty && !upcoming && !playlists;
}

// ─── Slots, once per medium ────────────────────────────────

const TrackerSlot _watching = TrackerSlot(
  id: 'watching',
  label: 'Watching',
  icon: Icons.videocam_outlined,
  empty: 'Nothing in progress — tick an episode, or add a series from Discovery',
);

const TrackerSlot _watched = TrackerSlot(
  id: 'watched',
  label: 'Watched',
  icon: Icons.done_all_outlined,
  empty: 'Series you have seen to the end land here',
);

const TrackerSlot _reading = TrackerSlot(
  id: 'reading',
  label: 'Reading',
  icon: Icons.menu_book_outlined,
  empty: 'Books you are in the middle of sit here',
);

const TrackerSlot _read = TrackerSlot(
  id: 'read',
  label: 'Read',
  icon: Icons.check_circle_outline,
  empty: 'Books you have finished land here',
);

const TrackerSlot _movieWatchlist = TrackerSlot(
  id: 'watchlist',
  label: 'Watchlist',
  icon: Icons.bookmark_outline,
  empty: 'Films you mean to see sit here',
);

const TrackerSlot _movieWatched = TrackerSlot(
  id: 'watched',
  label: 'Watched',
  icon: Icons.done_all_outlined,
  empty: 'Films you have seen land here',
);

const TrackerSlot _gameWishlist = TrackerSlot(
  id: 'wishlist',
  label: 'Wishlist',
  icon: Icons.favorite_outline,
  empty: 'Games you want sit here',
);

const TrackerSlot _gameOwned = TrackerSlot(
  id: 'owned',
  label: 'Owned',
  icon: Icons.inventory_2_outlined,
  empty: 'Games you have sit here',
);

const TrackerSlot _gamePlayed = TrackerSlot(
  id: 'played',
  label: 'Played',
  icon: Icons.sports_esports_outlined,
  empty: 'Games you have played land here',
);

const TrackerSlot _listening = TrackerSlot(
  id: 'listening',
  label: 'Listening',
  icon: Icons.headphones_outlined,
  empty: 'Shows you are part way through sit here',
);

const TrackerSlot _listened = TrackerSlot(
  id: 'listened',
  label: 'Listened',
  icon: Icons.done_all_outlined,
  empty: 'Shows you have heard to the end land here',
);

const TrackerSlot _legacyWishlist = TrackerSlot(
  id: 'wishlist',
  label: 'Wishlist',
  icon: Icons.favorite_outline,
  empty: 'Your wishlist is empty',
);

const TrackerSlot _legacyLibrary = TrackerSlot(
  id: 'library',
  label: 'Library',
  icon: Icons.bookmark_outline,
  empty: 'Your library is empty',
);

/// Which collections a category gets. Anything without a catalogue of its
/// own (Workout, or a category the backend has not named yet) keeps the two
/// generic lists it always had.
TrackerTabs trackerTabsFor(String? category) {
  switch (category) {
    case 'tv':
    case 'anime':
      // Checkmarks move a series between Watching and Watched; Upcoming is
      // the episodes that have not aired yet.
      return const TrackerTabs(slots: [_watching, _watched], upcoming: true);
    case 'books':
      return const TrackerTabs(slots: [_reading, _read]);
    case 'movies':
      return const TrackerTabs(slots: [_movieWatchlist, _movieWatched]);
    case 'games':
      return const TrackerTabs(slots: [_gameWishlist, _gameOwned, _gamePlayed]);
    case 'podcasts':
      return const TrackerTabs(slots: [_listening, _listened]);
    case 'music':
      return const TrackerTabs(playlists: true);
    default:
      return const TrackerTabs(slots: [_legacyWishlist, _legacyLibrary]);
  }
}
