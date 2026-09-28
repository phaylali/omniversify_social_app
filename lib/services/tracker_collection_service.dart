import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local wishlist / library storage for tracker items, keyed by API category.
class TrackerCollectionService {
  TrackerCollectionService._();

  static final TrackerCollectionService instance = TrackerCollectionService._();

  static const _wishlistKey = 'tracker_wishlist_v1';
  static const _libraryKey = 'tracker_library_v1';

  Map<String, List<Map<String, dynamic>>> _wishlist = {};
  Map<String, List<Map<String, dynamic>>> _library = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _wishlist = _readMap(prefs, _wishlistKey);
    _library = _readMap(prefs, _libraryKey);
    _loaded = true;
  }

  Map<String, List<Map<String, dynamic>>> _readMap(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(
            k,
            (v as List)
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList(),
          ));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(
    SharedPreferences prefs,
    String key,
    Map<String, List<Map<String, dynamic>>> data,
  ) async {
    await prefs.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> itemsFor(
    String category,
    bool wishlist,
  ) async {
    await _ensureLoaded();
    final source = wishlist ? _wishlist : _library;
    return List.unmodifiable(source[category] ?? const []);
  }

  Future<bool> contains(
    String category,
    dynamic id,
    bool wishlist,
  ) async {
    await _ensureLoaded();
    final source = wishlist ? _wishlist : _library;
    return (source[category] ?? const []).any((e) => e['id'] == id);
  }

  Future<bool> toggle(
    String category,
    Map<String, dynamic> item,
    bool wishlist,
  ) async {
    await _ensureLoaded();
    final source = wishlist ? _wishlist : _library;
    final list = source[category] ?? <Map<String, dynamic>>[];
    final id = item['id'];
    final existing = list.indexWhere((e) => e['id'] == id);
    if (existing >= 0) {
      list.removeAt(existing);
    } else {
      // Keep a compact snapshot for the collection tabs / dialog.
      list.insert(0, _snapshot(item));
    }
    source[category] = list;
    final prefs = await SharedPreferences.getInstance();
    await _writeMap(prefs, wishlist ? _wishlistKey : _libraryKey, source);
    return existing < 0;
  }

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
      'authors',
      'director',
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
}
