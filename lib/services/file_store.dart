import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Copies a picked file into app-owned storage and returns the new path.
///
/// Pickers hand back paths in a cache directory the system is free to clear
/// — and `image_picker` on iOS hands back a path that is revoked outright as
/// soon as the picker closes. A post or a message has to outlive both, so the
/// bytes are copied into the documents directory once and from then on the
/// stored path is ours.
///
/// IO platforms only; the web build swaps in `file_store_stub.dart` through
/// the conditional import in the composer, because `dart:io` cannot compile
/// for the browser.
Future<String> persistMedia(String sourcePath, String fileName) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/shared');
  if (!await dir.exists()) await dir.create(recursive: true);

  // Strip anything the picker may have prefixed, then make the name unique so
  // two photos with the same camera-generated name never overwrite each other.
  final clean = fileName.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final target = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$clean');

  await File(sourcePath).copy(target.path);
  return target.path;
}

/// Removes a file that was never sent — a discarded voice note, or a pick the
/// person changed their mind about.
Future<void> deleteMedia(String path) async {
  if (path.isEmpty) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}
