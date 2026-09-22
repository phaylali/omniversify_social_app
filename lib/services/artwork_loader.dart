import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/config/api_config.dart';
import '../models/song_item.dart';
import 'audio_metadata_extractor.dart';

/// Lazy, cache-first artwork loader.
///
/// Priority:
/// 1. Memory cache
/// 2. Disk cache (file under app support dir)
/// 3. Omniversify DB artwork when [SongItem.dbId] is set
/// 4. Embedded file metadata (TagLib cover, then ID3 APIC)
///
/// Artwork is never extracted during the bulk metadata scan; UI widgets
/// call [load] for visible rows only. Results are written to disk so the
/// next session is cache-first.
class ArtworkLoader {
  ArtworkLoader._();
  static final ArtworkLoader instance = ArtworkLoader._();

  static const int _maxMemoryEntries = 200;
  static const int _maxDiskEntries = 500;

  final Map<String, List<int>> _memory = <String, List<int>>{};
  final Map<String, Future<List<int>?>> _inFlight = <String, Future<List<int>?>>{};
  final Map<String, StreamController<List<int>?>> _controllers =
      <String, StreamController<List<int>?>>{};
  Directory? _cacheDir;
  bool _pruned = false;

  String cacheKey(SongItem song) {
    final id = song.dbId;
    if (id != null) return 'db_$id';
    return 'path_${song.path}|${song.duration ?? 0}';
  }

  /// Non-blocking memory lookup for already-loaded artwork.
  List<int>? peek(SongItem song) => _memory[cacheKey(song)];

  /// Load artwork: memory → disk → DB (if dbId) → file extract.
  /// Concurrent callers for the same song share one future.
  Future<List<int>?> load(SongItem song) {
    final key = cacheKey(song);
    final mem = _memory[key];
    if (mem != null) return Future.value(mem);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _load(song, key).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  /// Broadcast stream of artwork for a song — emits once loaded.
  Stream<List<int>?> watch(SongItem song) {
    final key = cacheKey(song);
    final cached = _memory[key];
    if (cached != null) {
      return Stream.value(cached);
    }
    var controller = _controllers[key];
    if (controller == null || controller.isClosed) {
      controller = StreamController<List<int>?>.broadcast();
      _controllers[key] = controller;
      load(song).then((bytes) {
        final c = _controllers[key];
        if (c != null && !c.isClosed) c.add(bytes);
      });
    }
    return controller.stream;
  }

  Future<List<int>?> _load(SongItem song, String key) async {
    // 2. Disk cache
    final disk = await _readDisk(key);
    if (disk != null) {
      _remember(key, disk);
      return disk;
    }

    // Already on the song (legacy / preloaded)
    final embedded = song.artworkBytes;
    if (embedded != null && embedded.isNotEmpty) {
      await _writeDisk(key, embedded);
      _remember(key, embedded);
      return embedded;
    }

    // 3. DB artwork first when we have a backend id
    final dbId = song.dbId;
    if (dbId != null) {
      final fromDb = await _fetchDbArtwork(dbId);
      if (fromDb != null && fromDb.isNotEmpty) {
        await _writeDisk(key, fromDb);
        _remember(key, fromDb);
        return fromDb;
      }
    }

    // 4. Embedded file metadata (TagLib → ID3 APIC)
    try {
      final fromFile = await AudioMetadataExtractor.extractArtwork(song.path);
      if (fromFile != null && fromFile.isNotEmpty) {
        await _writeDisk(key, fromFile);
        _remember(key, fromFile);
        return fromFile;
      }
    } catch (_) {}

    return null;
  }

  Future<List<int>?> _fetchDbArtwork(int dbId) async {
    try {
      final base = ApiConfig.omniversifyApiUrl;
      if (base.isEmpty) return null;
      final uri = Uri.parse('$base/api/v1/music/$dbId/artwork');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final contentType = resp.headers['content-type'] ?? '';
      if (contentType.startsWith('application/json')) {
        // Endpoint returned JSON (likely not found) — no image bytes.
        return null;
      }
      if (resp.bodyBytes.isEmpty) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Persist artwork for the media notification / share and return the file.
  Future<File?> writeForNotification(SongItem song, List<int> bytes) async {
    try {
      final dir = await _ensureDir();
      final file = File('${dir.path}/now_playing.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  void _remember(String key, List<int> bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
    final c = _controllers[key];
    if (c != null && !c.isClosed) c.add(bytes);
  }

  Future<Directory> _ensureDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/artwork_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    if (!_pruned) {
      _pruned = true;
      unawaited(_pruneDisk(dir));
    }
    return dir;
  }

  static String _fileName(String key) {
    // Stable, filesystem-safe name (FNV-1a 64-bit hex + length).
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(key)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${hash.toRadixString(16)}_${key.length}.img';
  }

  Future<List<int>?> _readDisk(String key) async {
    try {
      final dir = await _ensureDir();
      final file = File('${dir.path}/${_fileName(key)}');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String key, List<int> bytes) async {
    try {
      final dir = await _ensureDir();
      final file = File('${dir.path}/${_fileName(key)}');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<void> _pruneDisk(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      if (files.length <= _maxDiskEntries) return;
      files.sort((a, b) {
        final am = a.statSync().modified;
        final bm = b.statSync().modified;
        return am.compareTo(bm);
      });
      final excess = files.length - _maxDiskEntries;
      for (var i = 0; i < excess; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void dispose() {
    for (final c in _controllers.values) {
      if (!c.isClosed) c.close();
    }
    _controllers.clear();
    _memory.clear();
    _inFlight.clear();
  }
}
