import 'package:flutter/foundation.dart';

import '../models/song_item.dart';
import 'audio_player_service.dart';

/// What kind of thing someone is doing right now.
enum ActivityKind { listening, reading }

/// One row in the "right now" strip of the Acquaintances tab.
class ActivityEntry {
  const ActivityEntry({
    required this.name,
    required this.handle,
    required this.kind,
    required this.title,
    this.subtitle,
    this.when = 'now',
  });

  final String name;
  final String handle;
  final ActivityKind kind;
  final String title;
  final String? subtitle;

  /// Age of the activity, shown as `now` / `3m` / `1h`.
  final String when;

  /// The act on its own — `Reading` / `Listening to` — so a row can paint it
  /// in the accent colour and leave what follows in the ordinary one.
  String get act => switch (kind) {
    ActivityKind.listening => 'Listening to',
    ActivityKind.reading => 'Reading',
  };

  /// What the act is about: the title, plus the artist when there is one.
  String get subject => switch (kind) {
    ActivityKind.listening =>
      subtitle == null ? title : '$title · $subtitle',
    ActivityKind.reading => title,
  };

  /// `Listening to …` / `Reading …` — [act] then [subject].
  String get line => '$act $subject';

  ActivityEntry copyWith({String? when}) => ActivityEntry(
    name: name,
    handle: handle,
    kind: kind,
    title: title,
    subtitle: subtitle,
    when: when ?? this.when,
  );
}

/// What the player is up to, and (placeholder) what their acquaintances are.
///
/// The player's own activity is never stored twice: [own] reads the music
/// service and the reader live, so the strip is always in sync with reality.
/// The acquaintance rows are placeholders until presence lands on the
/// backend — they exist so the tab has something real to show.
class ActivityService {
  ActivityService._();

  static final ActivityService instance = ActivityService._();

  /// Title of the book the reader has open, or null when nothing is open.
  final ValueNotifier<String?> reading = ValueNotifier<String?>(null);

  /// Placeholder presence from acquaintances, newest first.
  static const List<ActivityEntry> acquaintances = [
    ActivityEntry(
      name: 'Amina',
      handle: '@amina_stream',
      kind: ActivityKind.listening,
      title: 'Blinding Lights',
      subtitle: 'The Weeknd',
      when: 'now',
    ),
    ActivityEntry(
      name: 'Omar',
      handle: '@omar_gamer',
      kind: ActivityKind.reading,
      title: 'The Martian',
      when: '2m',
    ),
    ActivityEntry(
      name: 'Fatima',
      handle: '@fatima_art',
      kind: ActivityKind.reading,
      title: 'Understanding Comics',
      when: '9m',
    ),
    ActivityEntry(
      name: 'Karim',
      handle: '@karim_w',
      kind: ActivityKind.listening,
      title: 'Lost Kites',
      subtitle: 'Burrak',
      when: '14m',
    ),
  ];

  /// The signed-in player's own current activity, or null when idle.
  ActivityEntry? own({String name = 'You', String handle = '@phaylali'}) {
    final book = reading.value;
    if (book != null) {
      return ActivityEntry(
        name: name,
        handle: handle,
        kind: ActivityKind.reading,
        title: book,
        when: 'now',
      );
    }
    final audio = AudioPlayerService.maybeInstance;
    final song = audio?.currentSong;
    if (song != null && (audio?.isPlaying ?? false)) {
      return ActivityEntry(
        name: name,
        handle: handle,
        kind: ActivityKind.listening,
        title: song.title,
        subtitle: song.artist,
        when: 'now',
      );
    }
    return null;
  }

  /// Convenience for tests: an entry straight from a [SongItem].
  static ActivityEntry fromSong(String name, String handle, SongItem song) =>
      ActivityEntry(
        name: name,
        handle: handle,
        kind: ActivityKind.listening,
        title: song.title,
        subtitle: song.artist,
      );

  /// Whether [entry] may be shown at the given audience level.
  ///
  /// Acquaintance rows always pass (they are already scoped to your
  /// acquaintances); your own row is gated by the privacy setting.
  static bool visibleTo(
    ActivityEntry entry, {
    required bool isOwn,
    required bool shared,
  }) => isOwn ? shared : true;
}
