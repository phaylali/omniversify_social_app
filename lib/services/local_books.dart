import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_loader.dart';

/// A book file found on the phone.
class FoundBook {
  const FoundBook({
    required this.path,
    required this.title,
    required this.format,
    required this.sizeBytes,
  });

  final String path;

  /// File name without folders or extension.
  final String title;
  final BookFormat format;
  final int sizeBytes;

  /// `56 MB`, `4.3 MB`, `120 kB` — always digits, never spelled out.
  String get size {
    if (sizeBytes >= 1000000) {
      final mb = sizeBytes / 1000000;
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    }
    if (sizeBytes >= 1000) return '${(sizeBytes / 1000).toStringAsFixed(0)} kB';
    return '$sizeBytes B';
  }

  /// Where the file lives, as short as it can be while still readable —
  /// `~/Download/chapter.cbz`, or `~/…/downloads/chapter.cbz` when the
  /// folder chain is long. `~` stands for the phone's shared storage.
  String get displayPath {
    const home = '/storage/emulated/0';
    final atHome = path.startsWith('$home/');
    final display = atHome ? '~${path.substring(home.length)}' : path;
    // The row gives the path about fifty characters before the file name
    // would start getting cut off anyway.
    if (display.length <= 52) return display;
    final parts = display.split('/');
    if (parts.length <= 3) return display;
    // Keep the head (the "~" or the first folder) and the last two segments,
    // since the file name and its folder are what identify the book.
    final tail = parts.sublist(parts.length - 2).join('/');
    final collapsed = '${parts.first}/…/$tail';
    if (collapsed.length <= 52) return collapsed;
    // Nothing deeper survives: the file name is the part that must.
    return atHome ? '~/…/${parts.last}' : '…/${parts.last}';
  }

  static FoundBook? fromFile(File file) {
    final dot = file.path.lastIndexOf('.');
    if (dot < 0) return null;
    final format = BookLoader.formatOf(file.path);
    if (format == null) return null;
    int size;
    try {
      size = file.lengthSync();
    } catch (_) {
      size = 0;
    }
    return FoundBook(
      path: file.path,
      title: BookLoader.titleOf(file.path),
      format: format,
      sizeBytes: size,
    );
  }
}

/// The phone's books: folders the reader watches, and everything it can find.
///
/// Two ways in — add folders one at a time (the user picks exactly what the
/// reader may look at), or scan the whole phone, which needs the "All files
/// access" permission the manifest already declares.
class LocalBooksService {
  LocalBooksService._();

  static final LocalBooksService instance = LocalBooksService._();

  static const String _key = 'reader_folders_v1';

  /// Directories the reader watches, in the order they were added.
  final ValueNotifier<List<String>> folders = ValueNotifier([]);

  /// Books per watched folder, keyed by that folder's path.
  final ValueNotifier<Map<String, List<FoundBook>>> byFolder = ValueNotifier(
    {},
  );

  /// Everything a whole-phone scan turned up (session only).
  final ValueNotifier<List<FoundBook>> scanned = ValueNotifier([]);

  /// While a scan runs, so the button can show it.
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// A message worth showing — permission trouble, empty folders, counts.
  final ValueNotifier<String?> notice = ValueNotifier(null);

  static const Set<String> _skipDirs = {
    'Android',
    'data',
    'media',
    'obb',
    'LOST.DIR',
    '.thumbnails',
    'cache',
  };

  /// Bounds on a phone-wide walk: a scan should take seconds, not minutes,
  /// and a book shelf doesn't need every PDF in existence.
  static const int _maxDepth = 8;
  static const int _maxResults = 500;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == null || stored.isEmpty) return;
    try {
      final decoded = foldersFromStored(stored);
      folders.value = decoded;
      for (final folder in decoded) {
        scanFolder(folder); // fire and forget: the shelf fills in as it goes
      }
    } catch (_) {
      await prefs.remove(_key);
    }
  }

  /// Parses the stored folder list — one path per line, empties dropped.
  static List<String> foldersFromStored(String raw) => [
    for (final line in raw.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, folders.value.join('\n'));
  }

  /// Adds [path] if it isn't watched yet, then scans it.
  Future<void> addFolder(String path) async {
    final clean = path.replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return;
    if (!folders.value.contains(clean)) {
      folders.value = [...folders.value, clean];
      await _save();
    }
    await scanFolder(clean);
  }

  Future<void> removeFolder(String path) async {
    folders.value = [
      for (final f in folders.value)
        if (f != path) f,
    ];
    final next = Map<String, List<FoundBook>>.from(byFolder.value);
    next.remove(path);
    byFolder.value = next;
    await _save();
  }

  /// Whether the reader may read outside its own sandbox.
  ///
  /// The "All files access" screen is a system toggle, so a denial here is
  /// the user saying not yet — worth a plain explanation, not an error.
  Future<bool> ensureAccess() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    notice.value =
        'Turn on "All files access" for Omniversify to scan for books.';
    return false;
  }

  /// Books inside one watched folder.
  Future<void> scanFolder(String folder) async {
    final books = findBooks(folder, skipSystemDirs: false);
    final next = Map<String, List<FoundBook>>.from(byFolder.value);
    next[folder] = books;
    byFolder.value = next;
    if (books.isEmpty) {
      notice.value = 'No books in ${folder.split('/').last}.';
    }
  }

  /// Every book on the phone, bounded by [_maxDepth] and [_maxResults].
  Future<void> scanPhone() async {
    if (busy.value) return;
    if (!await ensureAccess()) return;
    busy.value = true;
    notice.value = 'Scanning…';
    try {
      final roots = await phoneRoots();
      final found = <String, FoundBook>{};
      for (final root in roots) {
        for (final book in findBooks(root)) {
          found.putIfAbsent(book.path, () => book);
        }
      }
      final books = found.values.toList().._sortByTitle();
      scanned.value = books;
      notice.value = books.isEmpty
          ? 'No books found on this phone.'
          : 'Found ${books.length} books.';
    } finally {
      busy.value = false;
    }
  }

  /// Last path segment: `/storage/emulated/0/Download` → `Download`.
  ///
  /// Taken from the path rather than the URI — a directory URI ends in "/",
  /// so its last segment is always empty.
  static String _nameOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Where a phone-wide scan starts: shared storage, if it is mounted.
  ///
  /// Only one root — `/sdcard` and `/storage/emulated/0` are the same disk,
  /// and scanning both would list every book twice.
  static Future<List<String>> phoneRoots() async {
    const candidates = ['/storage/emulated/0', '/sdcard'];
    for (final candidate in candidates) {
      try {
        if (Directory(candidate).existsSync()) return [candidate];
      } catch (_) {
        // Not mounted — try the next one.
      }
    }
    return [''];
  }

  /// Walks [root] collecting supported books, catching every denial along
  /// the way — one unreadable folder must not end the scan.
  static List<FoundBook> findBooks(String root, {bool skipSystemDirs = true}) {
    if (root.isEmpty) return const [];
    final results = <String, FoundBook>{};
    final pending = <MapEntry<String, int>>[MapEntry(root, 0)];

    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      List<FileSystemEntity> children;
      try {
        children = Directory(current.key).listSync(followLinks: false);
      } catch (_) {
        continue; // Permission denied, or the folder vanished.
      }
      final depth = current.value + 1;
      for (final child in children) {
        if (child is Directory) {
          // The path, not the URI: a directory URI ends in "/", so its last
          // path segment is always empty and the name would vanish.
          final name = _nameOf(child.path);
          if (name.isEmpty || name.startsWith('.')) continue;
          if (skipSystemDirs && _skipDirs.contains(name)) continue;
          if (depth <= _maxDepth) {
            pending.add(MapEntry(child.path, depth));
          }
          continue;
        }
        if (child is! File) continue;
        final book = FoundBook.fromFile(child);
        if (book == null) continue;
        results[book.path] = book;
        if (results.length >= _maxResults) break;
      }
      if (results.length >= _maxResults) break;
    }

    final books = results.values.toList().._sortByTitle();
    return books;
  }

  /// Every book the Local tab can offer, wherever it came from.
  List<FoundBook> get allBooks {
    final seen = <String, FoundBook>{};
    for (final list in byFolder.value.values) {
      for (final book in list) {
        seen.putIfAbsent(book.path, () => book);
      }
    }
    for (final book in scanned.value) {
      seen.putIfAbsent(book.path, () => book);
    }
    final books = seen.values.toList().._sortByTitle();
    return books;
  }
}

extension on List<FoundBook> {
  void _sortByTitle() {
    sort((a, b) {
      final left = a.title.toLowerCase();
      final right = b.title.toLowerCase();
      final compare = left.compareTo(right);
      return compare != 0 ? compare : a.path.compareTo(b.path);
    });
  }
}
