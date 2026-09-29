import 'package:flutter/foundation.dart';

/// Authors the player has muted or blocked in this session.
///
/// Both social menus (the scroll's `⋮` and a post's `⋮`) write here, and the
/// feed, the stories row and every scrolls tab read it — so hiding someone in
/// one place hides them everywhere until the app restarts. The value is a
/// [ValueNotifier] so the lists rebuild themselves the moment it changes.
class MuteService {
  MuteService._();

  static final MuteService instance = MuteService._();

  /// Handles hidden from the feed.
  final ValueNotifier<Set<String>> muted = ValueNotifier(<String>{});

  bool isMuted(String handle) => muted.value.contains(handle);

  /// Hides [handle]. Returns true when newly muted.
  bool mute(String handle) {
    if (muted.value.contains(handle)) return false;
    muted.value = {...muted.value, handle};
    return true;
  }

  /// Brings [handle] back.
  void unmute(String handle) {
    if (!muted.value.contains(handle)) return;
    muted.value = {...muted.value}..remove(handle);
  }

  /// Restores everyone — the escape hatch behind "Unmute everyone".
  void unmuteAll() => muted.value = <String>{};
}
