import '../models/song_item.dart';

/// Web/unsupported-platform stand-in for `artwork_loader.dart`.
///
/// No filesystem on the web, so there is no disk cache and no notification
/// artwork file; only a small in-memory map is kept so the widget API
/// behaves consistently.
class ArtworkLoader {
  ArtworkLoader._();
  static final ArtworkLoader instance = ArtworkLoader._();

  final Map<String, List<int>> _memory = <String, List<int>>{};

  String cacheKey(SongItem song) {
    final id = song.dbId;
    if (id != null) return 'db_$id';
    return 'path_${song.path}|${song.duration ?? 0}';
  }

  List<int>? peek(SongItem song) => _memory[cacheKey(song)] ?? song.artworkBytes;

  Future<List<int>?> load(SongItem song) async => peek(song);

  Future<WebArtFile?> writeForNotification(SongItem song, List<int>? bytes) async =>
      null;

  Future<List<int>?> loadLogoBytes() async => null;

  void dispose() => _memory.clear();
}

/// Type-only stand-in so callers can null-check then read `.path`.
class WebArtFile {
  final String path;
  WebArtFile(this.path);
}
