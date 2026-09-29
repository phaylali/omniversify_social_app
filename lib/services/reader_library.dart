import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One book in the reader's Library tab.
///
/// [page] is the 1-based position shown to the reader — "4 of 20" — so the
/// saved number and the label in the list are never off by one. Opening an
/// entry lands on exactly that page.
class LibraryEntry {
  const LibraryEntry({
    required this.path,
    required this.title,
    required this.format,
    required this.page,
    required this.pages,
    required this.openedAt,
    this.source = 'local',
  });

  /// Absolute path of the file — unique per book, and what we reopen.
  final String path;
  final String title;

  /// Book format extension: `pdf`, `epub`, `cbz`, `cbr`.
  final String format;
  final int page;
  final int pages;

  /// When it was last opened, as milliseconds since the epoch.
  final int openedAt;

  /// `local` for files off the phone, `discover` for downloaded ones.
  final String source;

  /// Fill of the progress bar: 0 before the first page, 1 when finished.
  double get progress =>
      pages <= 0 ? 0 : (page / pages).clamp(0.0, 1.0).toDouble();

  /// `4/20`, the label under the title.
  String get label => '$page/$pages';

  /// Page index to resume from — the page [page] shows as, zero-based.
  int get resumeIndex => page <= 1 ? 0 : page - 1;

  LibraryEntry copyWith({int? page, int? pages, int? openedAt}) => LibraryEntry(
    path: path,
    title: title,
    format: format,
    page: page ?? this.page,
    pages: pages ?? this.pages,
    openedAt: openedAt ?? this.openedAt,
    source: source,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'title': title,
    'format': format,
    'page': page,
    'pages': pages,
    'openedAt': openedAt,
    'source': source,
  };

  factory LibraryEntry.fromJson(Map<String, Object?> json) => LibraryEntry(
    path: json['path'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled',
    format: json['format'] as String? ?? 'pdf',
    page: (json['page'] as num?)?.toInt() ?? 1,
    pages: (json['pages'] as num?)?.toInt() ?? 0,
    openedAt: (json['openedAt'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? 'local',
  );
}

/// Recently opened books, newest first, each remembering where you stopped.
///
/// The Reader screen writes on every page turn; the Library tab reads the
/// same list, so a book closed on page 4 comes back with a 4/20 bar and
/// opens on page 4 again.
class ReaderLibrary {
  ReaderLibrary._();

  static final ReaderLibrary instance = ReaderLibrary._();

  static const String _key = 'reader_library_v1';

  /// Keeps the list honest: one shelf row per screen, roughly.
  static const int _maxEntries = 30;

  final ValueNotifier<List<LibraryEntry>> entries = ValueNotifier([]);

  bool _loaded = false;

  /// Reads the shelf once; later calls are no-ops.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      entries.value = [
        for (final item in decoded)
          if (item is Map)
            LibraryEntry.fromJson(Map<String, Object?>.from(item)),
      ];
    } catch (_) {
      // A corrupt shelf is worth clearing rather than crashing over.
      entries.value = const [];
      await prefs.remove(_key);
    }
  }

  /// Remembers a book at [page] (1-based), moving it to the top of the list.
  Future<void> record({
    required String path,
    required String title,
    required String format,
    required int page,
    required int pages,
    String source = 'local',
  }) async {
    if (path.isEmpty) return;
    final existing = entries.value.where((e) => e.path == path).toList();
    final previous = existing.isEmpty ? null : existing.first;
    final updated = LibraryEntry(
      path: path,
      title: title,
      format: format,
      page: page < 1 ? 1 : page,
      pages: pages,
      openedAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
    );
    entries.value = [
      updated,
      for (final entry in entries.value)
        if (entry.path != path) entry,
    ];
    if (entries.value.length > _maxEntries) {
      entries.value = entries.value.sublist(0, _maxEntries);
    }
    if (previous == null ||
        previous.page != updated.page ||
        previous.pages != updated.pages) {
      await _save();
    }
  }

  /// Drops one book (the ✕ on a Library row).
  Future<void> remove(String path) async {
    entries.value = [
      for (final e in entries.value)
        if (e.path != path) e,
    ];
    await _save();
  }

  Future<void> clear() async {
    entries.value = const [];
    await _save();
  }

  /// The entry for [path], if the shelf has it.
  LibraryEntry? find(String path) {
    for (final entry in entries.value) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in entries.value) e.toJson()]),
    );
  }
}
