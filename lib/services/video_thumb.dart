import 'dart:typed_data';

import 'package:flutter_video_thumbnail/flutter_video_thumbnail.dart';

/// The first frame of a local video, as JPEG bytes.
///
/// A video message with no frame behind it is a play button on a black tile,
/// which says nothing about what is actually inside. The platform decoders —
/// `MediaMetadataRetriever` on Android, `AVAssetImageGenerator` on iOS — cut
/// one frame in a few milliseconds, and the bytes are held per path so
/// scrolling a thread never decodes the same video twice.
///
/// IO platforms only; the web build swaps in `video_thumb_stub.dart` through
/// the conditional import in the chat screen, because a browser cannot pull a
/// frame out of a local file on demand.
Future<Uint8List?> videoThumb(String path) {
  if (path.isEmpty) return Future<Uint8List?>.value();
  // Cached as a future rather than a value: the first caller does the work,
  // anything rendering at the same moment waits on that one attempt, and a
  // file that turns out to be undecodable stays undecodable instead of being
  // retried on every rebuild.
  return _thumbs.putIfAbsent(path, () => _decode(path));
}

final Map<String, Future<Uint8List?>> _thumbs = {};

Future<Uint8List?> _decode(String path) async {
  try {
    // The plugin caches remote paths itself; a local file goes through this
    // map, which is the only place the bytes are kept.
    return await FlutterVideoThumbnail.getThumbnail(path, quality: 75);
  } catch (_) {
    // A missing or undecodable file keeps the placeholder. Losing the frame
    // is not worth a stack trace in the middle of a conversation.
    return null;
  }
}
