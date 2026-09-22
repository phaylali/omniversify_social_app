import 'dart:typed_data';
import 'package:flutter_taglib/flutter_taglib.dart';

/// Exact TagLib metadata via filesystem paths (prebuilt native libs).
/// Primary for duration/tags/artwork; pure-Dart parser stays as fallback.
class TaglibAudioService {
  /// Returns (durationMs, artist, album, title, coverBytes).
  /// Missing values are null.
  static Future<
      ({
        int? durationMs,
        String? artist,
        String? album,
        String? title,
        Uint8List? coverBytes
      })> getMetadata(String path) async {
    try {
      if (!TagLibFile.isSupported) {
        return (
          durationMs: null,
          artist: null,
          album: null,
          title: null,
          coverBytes: null
        );
      }
      final file = TagLibFile.open(path);
      if (file == null) {
        return (
          durationMs: null,
          artist: null,
          album: null,
          title: null,
          coverBytes: null
        );
      }
      try {
        int? durationMs;
        try {
          final d = file.duration;
          if (d > Duration.zero) durationMs = d.inMilliseconds;
        } catch (_) {}
        String? artist;
        String? album;
        String? title;
        try {
          artist = _clean(file.artist);
          album = _clean(file.album);
          title = _clean(file.title);
        } catch (_) {}
        Uint8List? cover;
        try {
          cover = file.coverData;
          if (cover != null && cover.isEmpty) cover = null;
        } catch (_) {}
        return (
          durationMs: durationMs,
          artist: artist,
          album: album,
          title: title,
          coverBytes: cover,
        );
      } finally {
        file.close();
      }
    } catch (_) {
      return (
        durationMs: null,
        artist: null,
        album: null,
        title: null,
        coverBytes: null
      );
    }
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
