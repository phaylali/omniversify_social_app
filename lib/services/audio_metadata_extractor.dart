import 'dart:io';
import 'dart:typed_data';
import '../models/song_item.dart';
import 'audio_duration_parser.dart';
import 'audio_metadata_cache.dart';
import 'taglib_audio_service.dart';

/// Extracts metadata (duration, artwork, artist, album) from audio files.
/// Pure Dart: fast header reads only, no player needed.
/// Results are cached on disk so only new/changed files are re-parsed.
class AudioMetadataExtractor {
  /// Extract metadata for a list of songs, 8 at a time for speed.
  /// Reports progress via [onProgress] for a real counter UI.
  static Future<List<SongItem>> extractAll(
    List<SongItem> songs, {
    void Function(int done, int total)? onProgress,
    bool useCache = true,
  }) async {
    final cache = AudioMetadataCache();
    if (useCache) await cache.load();
    final results = List<SongItem?>.filled(songs.length, null);
    const batch = 8;
    var done = 0;
    onProgress?.call(0, songs.length);
    for (var i = 0; i < songs.length; i += batch) {
      final end = (i + batch < songs.length) ? i + batch : songs.length;
      final chunk = <Future<void>>[];
      for (var j = i; j < end; j++) {
        chunk.add(_extractOneCached(songs[j], cache, useCache).then((s) {
          results[j] = s;
          done++;
          onProgress?.call(done, songs.length);
        }));
      }
      await Future.wait(chunk);
    }
    if (useCache) {
      cache.prune(songs.map((s) => s.path).toSet());
      await cache.save();
    }
    return results.whereType<SongItem>().toList();
  }

  static Future<SongItem> _extractOneCached(
    SongItem song,
    AudioMetadataCache cache,
    bool useCache,
  ) async {
    if (useCache) {
      try {
        final st = await AudioMetadataCache.stat(song.path);
        if (st != null) {
          final hit = cache.get(song.path, st.$1, st.$2);
          if (hit != null) {
            // Cache hit: duration/tags known. Still grab artwork
            // (fast ID3 read, not cached because it is large).
            List<int>? artwork = song.artworkBytes;
            try {
              final tags = await _parseId3v2(song.path);
              artwork = tags['artwork'] ?? artwork;
            } catch (_) {}
            return SongItem(
              id: song.id,
              title: song.title,
              artist: (hit['artist'] as String?) ?? song.artist,
              album: (hit['album'] as String?) ?? song.album,
              duration: (hit['duration'] as int?) ?? song.duration,
              path: song.path,
              folder: song.folder,
              artworkBytes: artwork,
            );
          }
        }
      } catch (_) {}
    }
    final out = await extractOne(song);
    if (useCache) {
      try {
        final st = await AudioMetadataCache.stat(song.path);
        if (st != null) {
          cache.put(song.path,
              size: st.$1,
              mtimeMs: st.$2,
              duration: out.duration,
              artist: out.artist,
              album: out.album);
        }
      } catch (_) {}
    }
    return out;
  }

  /// Extract metadata for a single song.
  /// Primary: dart_taglib (exact TagLib duration/tags).
  /// Fallback: pure-Dart headers + ID3v2 (artwork always via ID3 for now).
  static Future<SongItem> extractOne(SongItem song) async {
    int? duration;
    List<int>? artwork;
    String? artist;
    String? album;
    String? title;

    try {
      final meta = await TaglibAudioService.getMetadata(song.path);
      duration = meta.durationMs;
      artist = meta.artist;
      album = meta.album;
      title = meta.title;
      if (meta.coverBytes != null && meta.coverBytes!.isNotEmpty) {
        artwork = meta.coverBytes!.toList();
      }
    } catch (_) {}

    try {
      final tags = await _parseId3v2(song.path);
      artist ??= tags['artist'];
      album ??= tags['album'];
      artwork ??= tags['artwork'];
      // Prefer embedded title only when filename looks like a numbered dump
      // (e.g. "001. Queen - Bohemian Rhapsody" already carries the title).
      if (title != null &&
          song.title.startsWith(RegExp(r'^\d+\.\s')) == false) {
        // Keep filename title to avoid TagLib/ID3 title fights; artist/album win.
      }
    } catch (_) {}

    duration ??= AudioDurationParser.sanitize(
      await AudioDurationParser.getDurationMs(song.path),
    );

    return SongItem(
      id: song.id,
      title: song.title,
      artist: artist ?? song.artist,
      album: album ?? song.album,
      duration: duration ?? song.duration,
      path: song.path,
      folder: song.folder,
      artworkBytes: artwork ?? song.artworkBytes,
    );
  }

  /// Parse ID3v2 tags from an MP3 file.
  static Future<Map<String, dynamic>> _parseId3v2(String path) async {
    final result = <String, dynamic>{};
    try {
      final file = File(path);
      final raf = await file.open(mode: FileMode.read);

      // Read first 10 bytes to check for ID3v2 header
      final header = await raf.read(10);
      if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x53) {
        await raf.close();
        return result; // No ID3v2 header
      }

      // Parse tag size (syncsafe integer)
      final size = (header[6] << 21) | (header[7] << 14) | (header[8] << 7) | header[9];
      if (size <= 0 || size > 10 * 1024 * 1024) {
        await raf.close();
        return result;
      }

      // Read all tags
      final tagData = await raf.read(size);
      await raf.close();

      var pos = 0;
      while (pos < tagData.length - 10) {
        final frameId = String.fromCharCodes(tagData.sublist(pos, pos + 4));
        if (frameId[0] == '\x00') break; // Padding

        final frameSize = (tagData[pos + 4] << 24) |
            (tagData[pos + 5] << 16) |
            (tagData[pos + 6] << 8) |
            tagData[pos + 7];

        if (frameSize <= 0 || pos + 10 + frameSize > tagData.length) break;

        final frameData = tagData.sublist(pos + 10, pos + 10 + frameSize);

        if (frameId == 'TIT2') {
          result['title'] = _parseTextFrame(frameData);
        } else if (frameId == 'TPE1') {
          result['artist'] = _parseTextFrame(frameData);
        } else if (frameId == 'TALB') {
          result['album'] = _parseTextFrame(frameData);
        } else if (frameId == 'APIC') {
          result['artwork'] = _parseApicFrame(frameData);
        }

        pos += 10 + frameSize;
      }
    } catch (_) {}
    return result;
  }

  static String? _parseTextFrame(Uint8List data) {
    if (data.isEmpty) return null;
    final encoding = data[0];
    if (encoding == 0x00 || encoding == 0x03) {
      // ISO-8859-1 or UTF-8
      return String.fromCharCodes(data.sublist(1)).trim();
    } else if (encoding == 0x01 || encoding == 0x02) {
      // UTF-16 or UTF-16BE
      try {
        return String.fromCharCodes(data.sublist(1)).trim();
      } catch (_) {
        return null;
      }
    }
    return String.fromCharCodes(data.sublist(1)).trim();
  }

  static List<int>? _parseApicFrame(Uint8List data) {
    try {
      var pos = 0;
      // Skip text encoding byte
      pos++;
      // Read MIME type (null-terminated)
      var end = data.indexOf(0x00, pos);
      if (end < 0) return null;
      final mime = String.fromCharCodes(data.sublist(pos, end));
      pos = end + 1;
      // Skip picture type
      pos++;
      // Skip description (null-terminated)
      end = data.indexOf(0x00, pos);
      if (end < 0) return null;
      pos = end + 1;
      // Rest is image data
      if (pos < data.length) {
        return data.sublist(pos).toList();
      }
    } catch (_) {}
    return null;
  }
}
