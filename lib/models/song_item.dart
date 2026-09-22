/// Platform-agnostic song model used by the music player.
class SongItem {
  final int id;
  final String title;
  final String? artist;
  final String? album;
  final int? duration; // milliseconds
  final String path;
  final String folder;
  final List<int>? artworkBytes; // embedded album art (JPEG/PNG)
  /// Omniversify backend music id, when this song exists in the DB.
  /// Used as the primary artwork source when present.
  final int? dbId;

  const SongItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    required this.path,
    this.folder = '',
    this.artworkBytes,
    this.dbId,
  });

  String get fileName => path.split('/').last;

  SongItem copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    int? duration,
    String? path,
    String? folder,
    List<int>? artworkBytes,
    int? dbId,
  }) {
    return SongItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      path: path ?? this.path,
      folder: folder ?? this.folder,
      artworkBytes: artworkBytes ?? this.artworkBytes,
      dbId: dbId ?? this.dbId,
    );
  }
}
