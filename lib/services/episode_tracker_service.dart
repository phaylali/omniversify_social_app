import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which episodes of a series have been ticked off, kept on this device.
///
/// There are no user accounts to hang progress off yet, so this mirrors the
/// app's other local stores (wishlist, library, weather places): one JSON
/// blob in [SharedPreferences], read once and exposed as a [ValueNotifier]
/// so the tracking page repaints the moment a box is ticked.
class EpisodeTrackerService {
  EpisodeTrackerService._();

  static final EpisodeTrackerService instance = EpisodeTrackerService._();

  static const _storeKey = 'episode_tracker_v1';

  /// `tv:68261` → the episode keys watched (`S01E05`).
  final ValueNotifier<Map<String, Set<String>>> watched =
      ValueNotifier(const {});

  bool _loaded = false;

  /// Series identity: the backend id namespaced by category, so the same
  /// number in two catalogues can never mean two different shows at once.
  static String seriesKey(String category, Object? id) => '$category:$id';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    final parsed = <String, Set<String>>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is List) {
              parsed[key] = value.whereType<String>().toSet();
            }
          });
        }
      } catch (_) {
        // A damaged store must never stop the tracker from opening.
      }
    }
    watched.value = parsed;
    _loaded = true;
  }

  /// True once [episode] (`S01E05`) of [series] has been ticked.
  bool isWatched(String series, String episode) =>
      watched.value[series]?.contains(episode) ?? false;

  int watchedCount(String series) => watched.value[series]?.length ?? 0;

  Future<void> setEpisode(String series, String episode, bool value) async {
    final next = await _copy();
    final eps = <String>{...next[series] ?? const <String>{}};
    if (value) {
      eps.add(episode);
    } else {
      eps.remove(episode);
    }
    await _commit(next, series, eps);
  }

  Future<void> toggle(String series, String episode) =>
      setEpisode(series, episode, !isWatched(series, episode));

  /// Ticks (or unticks) a whole season in one go — the "I binged seasons 1
  /// to 3 months ago" case, which would be dozens of taps box by box.
  Future<void> setSeason(
    String series,
    Iterable<String> episodes,
    bool value,
  ) async {
    final next = await _copy();
    final eps = <String>{...next[series] ?? const <String>{}};
    if (value) {
      eps.addAll(episodes);
    } else {
      eps.removeAll(episodes);
    }
    await _commit(next, series, eps);
  }

  Future<void> clear(String series) async {
    final next = await _copy();
    if (next.remove(series) == null) return;
    await _save(next);
    watched.value = next;
  }

  Future<Map<String, Set<String>>> _copy() async {
    await load();
    return Map<String, Set<String>>.from(watched.value);
  }

  Future<void> _commit(
    Map<String, Set<String>> next,
    String series,
    Set<String> eps,
  ) async {
    if (eps.isEmpty) {
      next.remove(series);
    } else {
      next[series] = eps;
    }
    await _save(next);
    watched.value = next;
  }

  Future<void> _save(Map<String, Set<String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storeKey,
      jsonEncode({
        for (final entry in data.entries)
          entry.key: entry.value.toList()..sort(),
      }),
    );
  }

  /// Back to a blank slate so every test starts clean.
  @visibleForTesting
  void reset() {
    watched.value = const {};
    _loaded = false;
  }
}
