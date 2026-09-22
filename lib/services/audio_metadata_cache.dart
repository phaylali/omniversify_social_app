import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent index: path -> {size, mtime, duration, artist, album}.
/// Means rescans only parse new or changed files.
class AudioMetadataCache {
  static const _key = 'audio_metadata_index_v2';
  Map<String, Map<String, dynamic>> _index = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _index = decoded.map((k, v) => MapEntry(
            k, Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {
      _index = {};
    }
    _loaded = true;
  }

  Map<String, dynamic>? get(String path, int size, int mtimeMs) {
    final e = _index[path];
    if (e == null) return null;
    if (e['size'] != size || e['mtime'] != mtimeMs) return null;
    return e;
  }

  void put(String path,
      {required int size,
      required int mtimeMs,
      int? duration,
      String? artist,
      String? album}) {
    _index[path] = {
      'size': size,
      'mtime': mtimeMs,
      'duration': duration,
      'artist': artist,
      'album': album,
    };
  }

  Future<void> save() async {
    try {
      // Cap index so it never grows unbounded.
      if (_index.length > 5000) {
        final keys = _index.keys.toList();
        for (var i = 0; i < _index.length - 5000; i++) {
          _index.remove(keys[i]);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_index));
    } catch (_) {}
  }

  void prune(Set<String> existingPaths) {
    _index.removeWhere((k, _) => !existingPaths.contains(k));
  }

  static Future<(int size, int mtimeMs)?> stat(String path) async {
    try {
      final st = await FileStat.stat(path);
      return (st.size, st.modified.millisecondsSinceEpoch);
    } catch (_) {
      return null;
    }
  }
}
