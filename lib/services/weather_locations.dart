import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weather_service.dart';

/// The places you have looked up in the weather screen.
///
/// Three lists, one source of truth:
///
///  * [current] — the last place you chose, what the Current tab opens on;
///  * [starred] — the ones you starred, most recently starred first;
///  * [history] — the last [maxHistory] visits that are *not* starred, so a
///    starred place never shows up twice.
///
/// Mirrored into [ValueNotifier]s and persisted in [SharedPreferences], so the
/// Locations tab rebuilds the moment a star toggles and the list survives a
/// restart.
class WeatherLocations {
  WeatherLocations._();

  static final WeatherLocations instance = WeatherLocations._();

  static const String _kStore = 'weather_locations_v1';

  /// How many un-starred visits are kept.
  static const int maxHistory = 10;

  /// The last place opened in the Current tab.
  final ValueNotifier<GeoLocation?> current = ValueNotifier<GeoLocation?>(null);

  /// Starred places, most recently starred first.
  final ValueNotifier<List<GeoLocation>> starred =
      ValueNotifier<List<GeoLocation>>(const []);

  /// Visits, newest first, minus anything starred.
  final ValueNotifier<List<GeoLocation>> history =
      ValueNotifier<List<GeoLocation>>(const []);

  bool _loaded = false;

  /// Reads the stored place lists once. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStore);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        current.value = data['current'] == null
            ? null
            : GeoLocation.fromJson(data['current'] as Map<String, dynamic>);
        starred.value = _decode(data['starred']);
        history.value = _decode(data['history']);
      } catch (_) {
        // A store we cannot read is a store we start over from.
        current.value = null;
        starred.value = const [];
        history.value = const [];
      }
    }
    _loaded = true;
  }

  /// Whether [loc] is starred.
  bool isStarred(GeoLocation loc) =>
      starred.value.any((saved) => saved.sameAs(loc));

  /// A place was just opened: it becomes the current one and moves to the top
  /// of the history — unless it is starred, where it lives only in the starred
  /// list.
  Future<void> record(GeoLocation loc) async {
    await load();
    current.value = loc;
    if (!isStarred(loc)) {
      history.value = _prepend(loc, history.value);
    }
    await _save();
  }

  /// Stars a place, or un-stars it and sends it back to the history.
  Future<void> toggleStar(GeoLocation loc) async {
    await load();
    if (isStarred(loc)) {
      starred.value =
          starred.value.where((saved) => !saved.sameAs(loc)).toList();
      history.value = _prepend(loc, history.value);
    } else {
      starred.value = _prepend(loc, starred.value);
      history.value =
          history.value.where((saved) => !saved.sameAs(loc)).toList();
    }
    await _save();
  }

  /// [loc] first, without it anywhere else, capped at [limit].
  static List<GeoLocation> _prepend(
    GeoLocation loc,
    List<GeoLocation> list, {
    int limit = maxHistory,
  }) => [loc, ...list.where((saved) => !saved.sameAs(loc))].take(limit).toList();

  static List<GeoLocation> _decode(dynamic raw) => [
        for (final item in raw as List<dynamic>? ?? const [])
          GeoLocation.fromJson(item as Map<String, dynamic>),
      ];

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStore,
      jsonEncode({
        'current': current.value?.toJson(),
        'starred': starred.value.map((loc) => loc.toJson()).toList(),
        'history': history.value.map((loc) => loc.toJson()).toList(),
      }),
    );
  }

  /// Empties everything and lets [load] read again — tests start clean.
  @visibleForTesting
  void reset() {
    current.value = null;
    starred.value = const [];
    history.value = const [];
    _loaded = false;
  }
}
