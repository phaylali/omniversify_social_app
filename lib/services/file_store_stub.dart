/// Web stand-in for `file_store.dart` — there are no local files to copy.
///
/// The browser has nowhere durable to put the bytes, so the path the picker
/// gave us is passed straight through. The renderer already treats a path it
/// cannot open as an empty tile, so a post still reads correctly; only the
/// pixels are missing, which is the same trade the comment composer makes on
/// web by keeping bytes in memory instead.
Future<String> persistMedia(String sourcePath, String fileName) async => sourcePath;

/// Web stand-in for `deleteMedia` — there is no file to remove.
Future<void> deleteMedia(String path) async {}
