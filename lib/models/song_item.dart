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

  const SongItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    required this.path,
    this.folder = '',
    this.artworkBytes,
  });

  String get fileName => path.split('/').last;
}
