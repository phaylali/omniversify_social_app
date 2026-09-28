import 'dart:typed_data';

/// Web/unsupported-platform stand-in for `taglib_audio_service.dart`.
///
/// Keeps the same public API so this can be swapped in with a conditional
/// import; native tag reading/writing simply isn't available in the browser.
class TaglibAudioService {
  /// Returns (durationMs, artist, album, title, coverBytes).
  /// Missing values are null — always null on the web.
  static Future<
      ({
        int? durationMs,
        String? artist,
        String? album,
        String? title,
        Uint8List? coverBytes
      })> getMetadata(String path) async {
    return (
      durationMs: null,
      artist: null,
      album: null,
      title: null,
      coverBytes: null,
    );
  }

  /// Best-effort write of title/artist into the file's own tags.
  /// No-op on the web.
  static Future<void> writeTags(String path, {String? title, String? artist}) async {}
}
