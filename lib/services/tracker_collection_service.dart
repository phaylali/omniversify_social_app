import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local collections for tracker items: one list per slot per category.
///
/// A slot is this app's word for a shelf — `reading`, `watched`, `owned` —
/// so every category can keep as many of them as its habits need (the tabs
/// each category gets are in `tracker_tabs.dart`). A slot is exclusive:
/// putting a game in `Owned` takes it out of `Wishlist`, because nobody
/// wants the same title on both shelves.
///
/// The two lists this screen used to keep, wishlist and library, are folded
/// into the first and last slot of each category the first time the store is
/// read, so nothing anybody saved disappears.
class TrackerCollectionService {
  TrackerCollectionService._();

  static final TrackerCollectionService instance = TrackerCollectionService._();

  static const _storeKey = 'tracker_collections_v1';
  static const _playlistsKey = 'tracker_playlists_v1';
  static const _legacyWishlistKey = 'tracker_wishlist_v1';
  static const _legacyLibraryKey = 'tracker_library_v1';

  /// Where the old wishlist / library lists land once slots exist: a
  /// wishlist is something still meant to be got to (the first slot), a
  /// library something already had (the last one — except games, where
  /// `Owned` says it better than the final slot does).
  static const Map<String, List<String>> _legacySlots = {
    'books': ['reading', 'read'],
    'movies': ['watchlist', 'watched'],
    'games': ['wishlist', 'owned'],
    'podcasts': ['listening', 'listened'],
    'tv': ['watching', 'watched'],
    'anime': ['watching', 'watched'],
  };

  Map<String, Map<String, List<Map<String, dynamic>>>> _store = {};
  Map<String, List<Map<String, dynamic>>> _playlists = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _store = _readSlots(prefs, _storeKey);
    _playlists = _readLists(prefs.getString(_playlistsKey));
    if (_store.isEmpty) {
      _store = _migrateLegacy(prefs);
      if (_store.isNotEmpty) {
        // Keep the move once, and stop the old keys from merging again.
        await prefs.setString(_storeKey, jsonEncode(_store));
        await prefs.remove(_legacyWishlistKey);
        await prefs.remove(_legacyLibraryKey);
      }
    }
    _loaded = true;
  }

  // ─── Reading ──────────────────────────────────────────────

  Map<String, Map<String, List<Map<String, dynamic>>>> _readSlots(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((category, slots) => MapEntry(
            category,
            _readListsFrom(slots),
          ));
    } catch (_) {
      return {};
    }
  }

  Map<String, List<Map<String, dynamic>>> _readLists(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return _readListsFrom(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Map<String, List<Map<String, dynamic>>> _readListsFrom(dynamic decoded) {
    if (decoded is! Map) return {};
    return decoded.map((slot, items) => MapEntry(
          slot.toString(),
          (items is List ? items : const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(),
        ));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeKey, jsonEncode(_store));
  }

  Future<void> _persistPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, jsonEncode(_playlists));
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _migrateLegacy(
    SharedPreferences prefs,
  ) {
    final wishlist = _readLists(prefs.getString(_legacyWishlistKey));
    final library = _readLists(prefs.getString(_legacyLibraryKey));
    if (wishlist.isEmpty && library.isEmpty) return {};

    final store = <String, Map<String, List<Map<String, dynamic>>>>{};
    void land(String category, List<String>? slots, List<Map<String, dynamic>> items) {
      if (slots == null || slots.isEmpty || items.isEmpty) return;
      (store[category] ??= {})[slots.first] = items;
    }

    wishlist.forEach((category, items) {
      land(category, _legacySlots[category] ?? const ['wishlist'], items);
    });
    library.forEach((category, items) {
      final slots = _legacySlots[category];
      land(category, slots == null ? const ['library'] : [slots.last], items);
    });
    return store;
  }

  // ─── Collections ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> itemsFor(
    String category,
    String slot,
  ) async {
    await _ensureLoaded();
    return List.unmodifiable(_store[category]?[slot] ?? const []);
  }

  /// Every item the category holds, across its slots — used to work out
  /// where a series currently sits.
  Future<Map<String, dynamic>?> itemIn(
    String category,
    dynamic id,
  ) async {
    await _ensureLoaded();
    for (final items in (_store[category] ?? const {}).values) {
      for (final item in items) {
        if (item['id'] == id) return item;
      }
    }
    return null;
  }

  Future<bool> contains(
    String category,
    dynamic id,
    String slot,
  ) async {
    await _ensureLoaded();
    return (_store[category]?[slot] ?? const [])
        .any((e) => e['id'] == id);
  }

  /// True when [item] now sits in [slot].
  ///
  /// Adds it — dropping it from the category's other slots, so a title is
  /// ever only on one shelf — or takes it back off when it is already there.
  Future<bool> toggle(
    String category,
    Map<String, dynamic> item,
    String slot,
  ) async {
    final inside = await contains(category, item['id'], slot);
    if (inside) {
      await remove(category, item['id'], slot);
      return false;
    }
    await add(category, item, slot);
    return true;
  }

  /// Puts [item] in [slot] without asking whether it is already there —
  /// the checkmarks on a series page call this to walk a show from
  /// Watching to Watched. Returns true when something changed.
  Future<bool> add(
    String category,
    Map<String, dynamic> item,
    String slot,
  ) async {
    await _ensureLoaded();
    final slots = _store[category] ??= {};
    final id = item['id'];

    var changed = false;
    for (final entry in slots.entries) {
      if (entry.key == slot) continue;
      final before = entry.value.length;
      entry.value.removeWhere((e) => e['id'] == id);
      if (entry.value.length != before) changed = true;
    }

    final list = slots[slot] ??= <Map<String, dynamic>>[];
    if (!list.any((e) => e['id'] == id)) {
      list.insert(0, _snapshot(item));
      changed = true;
    }
    if (changed) await _persist();
    return changed;
  }

  /// Takes the item out of [slot]; true when it was there.
  Future<bool> remove(
    String category,
    dynamic id,
    String slot,
  ) async {
    await _ensureLoaded();
    final list = _store[category]?[slot];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((e) => e['id'] == id);
    if (list.length == before) return false;
    await _persist();
    return true;
  }

  // ─── Playlists (music) ────────────────────────────────────

  Future<List<String>> playlists() async {
    await _ensureLoaded();
    return List.unmodifiable(_playlists.keys);
  }

  Future<int> playlistCount(String name) async {
    await _ensureLoaded();
    return _playlists[name]?.length ?? 0;
  }

  Future<List<Map<String, dynamic>>> playlistItems(String name) async {
    await _ensureLoaded();
    return List.unmodifiable(_playlists[name] ?? const []);
  }

  Future<bool> inPlaylist(String name, dynamic id) async {
    await _ensureLoaded();
    return (_playlists[name] ?? const []).any((e) => e['id'] == id);
  }

  /// A new, empty playlist. Names that are blank or already taken are
  /// ignored — returns false then.
  Future<bool> createPlaylist(String name) async {
    await _ensureLoaded();
    final clean = name.trim();
    if (clean.isEmpty || _playlists.containsKey(clean)) return false;
    _playlists[clean] = <Map<String, dynamic>>[];
    await _persistPlaylists();
    return true;
  }

  Future<bool> deletePlaylist(String name) async {
    await _ensureLoaded();
    if (_playlists.remove(name) == null) return false;
    await _persistPlaylists();
    return true;
  }

  /// True when the track was newly added (a track sits in a playlist once).
  Future<bool> addToPlaylist(String name, Map<String, dynamic> item) async {
    await _ensureLoaded();
    final list = _playlists[name] ??= <Map<String, dynamic>>[];
    if (list.any((e) => e['id'] == item['id'])) return false;
    list.insert(0, _snapshot(item));
    await _persistPlaylists();
    return true;
  }

  Future<bool> removeFromPlaylist(String name, dynamic id) async {
    await _ensureLoaded();
    final list = _playlists[name];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((e) => e['id'] == id);
    if (list.length == before) return false;
    await _persistPlaylists();
    return true;
  }

  // ─── Snapshots ────────────────────────────────────────────

  Map<String, dynamic> _snapshot(Map<String, dynamic> item) {
    const keep = {
      'id',
      'uuid',
      'omniversify_id',
      'title',
      'name',
      'year',
      'released',
      'premiered',
      'aired_from',
      'first_publish_year',
      'poster',
      'image_url',
      'cover_url',
      'background_image',
      'artwork_url',
      'artist',
      'artists',
      'authors',
      'director',
      'developers',
      'genres',
      'rating',
      'score',
      'status',
      'runtime',
      'duration_ms',
      'episode_count',
      'plot',
      'summary',
      'synopsis',
      'description',
    };
    final out = <String, dynamic>{};
    for (final k in keep) {
      final v = item[k];
      if (v != null) out[k] = v;
    }
    if (out.isEmpty) out.addAll(item);
    return out;
  }

  /// Back to a blank slate so every test starts clean.
  @visibleForTesting
  void reset() {
    _store = {};
    _playlists = {};
    _loaded = false;
  }
}
