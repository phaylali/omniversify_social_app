import '../models/song_item.dart';

/// Web/unsupported-platform stand-in for `audio_metadata_extractor.dart`.
///
/// Without a filesystem there are no local files to parse; songs are passed
/// through untouched.
class AudioMetadataExtractor {
  static Future<List<SongItem>> extractAll(
    List<SongItem> songs, {
    void Function(int done, int total)? onProgress,
    bool useCache = true,
    bool includeArtwork = false,
  }) async {
    onProgress?.call(songs.length, songs.length);
    return songs;
  }

  static Future<List<int>?> extractArtwork(String path) async => null;
}
