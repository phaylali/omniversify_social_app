import '../models/song_item.dart';

/// In-memory library cache that survives screen navigation.
/// First visit scans from disk; return visits show instantly and
/// only refresh silently in the background for new/changed files.
class MusicLibraryService {
  MusicLibraryService._();
  static final MusicLibraryService instance = MusicLibraryService._();

  List<SongItem>? _songs;
  DateTime? _lastScan;

  bool get hasData => _songs != null && _songs!.isNotEmpty;
  List<SongItem> get songs =>
      _songs == null ? const [] : List<SongItem>.from(_songs!);
  DateTime? get lastScan => _lastScan;

  void store(List<SongItem> songs) {
    _songs = List<SongItem>.from(songs);
    _lastScan = DateTime.now();
  }

  void clear() {
    _songs = null;
    _lastScan = null;
  }
}
