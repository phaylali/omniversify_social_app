import 'dart:typed_data';

/// Web stand-in for `video_thumb.dart` — a browser cannot decode a frame out
/// of a local video file on demand.
///
/// Returning nothing is the state the tile was always built for: it keeps its
/// play button and the file's name, so a video on web reads as a video even
/// though no pixels of it are shown. Same trade `file_image_stub.dart` makes
/// for photos.
Future<Uint8List?> videoThumb(String path) async => null;
