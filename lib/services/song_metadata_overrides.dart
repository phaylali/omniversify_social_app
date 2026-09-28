import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';

/// User metadata edits (song title / singer) applied on top of scan results.
///
/// The scanner derives titles from filenames and tags, so without this layer
/// an edit would vanish on the next rescan. Stored as a flat
/// `path -> {title, artist}` JSON map in SharedPreferences.
class SongMetadataOverrides {
  SongMetadataOverrides._();

  static const String _key = 'music_metadata_overrides';
  static Map<String, Map<String, String>>? _cache;

  static Future<Map<String, Map<String, String>>> _load() async {
    if (_cache != null) return _cache!;
    final out = <String, Map<String, String>>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((path, value) {
          if (value is Map<String, dynamic>) {
            out[path] = {
              if (value['title'] is String) 'title': value['title'] as String,
              if (value['artist'] is String) 'artist': value['artist'] as String,
            };
          }
        });
      }
    } catch (_) {}
    _cache = out;
    return out;
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_cache ?? {}));
    } catch (_) {}
  }

  /// Returns a copy of [songs] with every known edit applied.
  /// An empty artist override clears the artist (shows as unknown).
  static Future<List<SongItem>> apply(List<SongItem> songs) async {
    final map = await _load();
    if (map.isEmpty) return songs;
    return songs.map((s) {
      final o = map[s.path];
      if (o == null) return s;
      final title = o['title'];
      final artist = o['artist'];
      if (title == null && artist == null) return s;
      return SongItem(
        id: s.id,
        title: (title != null && title.isNotEmpty) ? title : s.title,
        artist: artist == null || artist.isEmpty ? null : artist,
        album: s.album,
        duration: s.duration,
        path: s.path,
        folder: s.folder,
        artworkBytes: s.artworkBytes,
        dbId: s.dbId,
      );
    }).toList();
  }

  /// Records an edit so it survives rescans. An empty [artist] clears it.
  static Future<void> set(String path,
      {required String title, String artist = ''}) async {
    final map = await _load();
    map[path] = {'title': title, 'artist': artist};
    await _save();
  }

  /// Forgets any edit for [path] (used when the file is deleted).
  static Future<void> remove(String path) async {
    final map = await _load();
    if (map.remove(path) != null) await _save();
  }
}
