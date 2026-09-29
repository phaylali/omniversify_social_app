import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfx/pdfx.dart';

/// The four file types the reader opens.
enum BookFormat { pdf, epub, cbz, cbr }

extension BookFormatInfo on BookFormat {
  String get label => switch (this) {
    BookFormat.pdf => 'PDF',
    BookFormat.epub => 'EPUB',
    BookFormat.cbz => 'CBZ',
    BookFormat.cbr => 'CBR',
  };

  /// What each format is for, shown on the empty state.
  String get blurb => switch (this) {
    BookFormat.pdf => 'Documents & scans',
    BookFormat.epub => 'Novels',
    BookFormat.cbz => 'Comics',
    BookFormat.cbr => 'Comics (RAR)',
  };

  bool get isComic => this == BookFormat.cbz || this == BookFormat.cbr;
  bool get isText => this == BookFormat.epub;
}

/// A failure meant to be read by a human, not logged.
class BookOpenException implements Exception {
  const BookOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One chapter of an EPUB: a heading and its body text.
class BookChapter {
  const BookChapter({required this.title, required this.body});

  final String title;
  final String body;
}

/// Everything the viewer needs about an opened book.
///
/// A PDF keeps its [PdfDocument] (pages render lazily from it), comics keep
/// their decoded images, and EPUBs keep plain-text chapters — the parsing all
/// happened once, up front, in [BookLoader].
class BookDocument {
  BookDocument({
    required this.title,
    required this.format,
    this.pdf,
    this.images = const [],
    this.chapters = const [],
  });

  final String title;
  final BookFormat format;
  final PdfDocument? pdf;
  final List<Uint8List> images;
  final List<BookChapter> chapters;

  /// Pages for PDFs and comics, chapters for EPUBs.
  int get pageCount =>
      pdf?.pagesCount ?? (images.isNotEmpty ? images.length : chapters.length);

  /// `Page` or `Chapter` — whichever the position readout needs.
  String get unit => format.isText ? 'Chapter' : 'Page';

  /// Frees the native PDF document, if there is one.
  Future<void> close() async {
    final doc = pdf;
    if (doc != null) {
      try {
        await doc.close();
      } catch (_) {
        // Already closed — nothing to free.
      }
    }
  }
}

/// Opens local books and comics from bytes.
///
/// Everything in here is side-effect free apart from the PDF handle, so the
/// format detection and the EPUB/CBZ parsing can be unit tested with archives
/// built in memory.
abstract final class BookLoader {
  static const Set<String> supported = {'pdf', 'epub', 'cbz', 'cbr'};
  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
  };

  /// `BookFormat.cbz` for `story.CBZ`, null when the extension is unknown.
  static BookFormat? formatOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'pdf' => BookFormat.pdf,
      'epub' => BookFormat.epub,
      'cbz' => BookFormat.cbz,
      'cbr' => BookFormat.cbr,
      _ => null,
    };
  }

  /// File name without folders or extension: `OEBPS/moby-dick.epub` →
  /// `moby-dick`.
  static String titleOf(String path) {
    var name = path;
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) name = name.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.isEmpty ? 'Untitled' : name;
  }

  /// Reads [bytes] as the book [path] claims to be.
  static Future<BookDocument> open(Uint8List bytes, String path) async {
    final format = formatOf(path);
    if (format == null) {
      throw const BookOpenException(
        'That file type isn\'t supported — try a PDF, EPUB, CBZ or CBR.',
      );
    }
    final title = titleOf(path);

    switch (format) {
      case BookFormat.pdf:
        try {
          final pdf = await PdfDocument.openData(bytes);
          return BookDocument(title: title, format: format, pdf: pdf);
        } catch (_) {
          throw BookOpenException('"$title" couldn\'t be opened as a PDF.');
        }
      case BookFormat.cbz:
      case BookFormat.cbr:
        return _openComic(bytes, format, title);
      case BookFormat.epub:
        return _openEpub(bytes, title);
    }
  }

  // ── Comics ────────────────────────────────────────────────────────────

  static BookDocument _openComic(
    Uint8List bytes,
    BookFormat format,
    String title,
  ) {
    final Archive archive = _decodeZip(bytes, format, title);

    final files =
        archive
            .where(
              (file) =>
                  file.isFile &&
                  _imageExtensions.contains(_extensionOf(file.name)),
            )
            .toList()
          ..sort((a, b) => _naturalCompare(a.name, b.name));

    final images = <Uint8List>[];
    for (final file in files) {
      final data = file.readBytes();
      if (data != null && data.isNotEmpty) images.add(data);
    }
    if (images.isEmpty) {
      throw BookOpenException('"$title" has no images inside it.');
    }
    return BookDocument(title: title, format: format, images: images);
  }

  // ── EPUB ──────────────────────────────────────────────────────────────

  static BookDocument _openEpub(Uint8List bytes, String title) {
    final Archive archive = _decodeZip(bytes, BookFormat.epub, title);

    final entries = <String, ArchiveFile>{
      for (final file in archive)
        if (file.isFile) _normalizeName(file.name): file,
    };

    String readText(String name) {
      final file = entries[_normalizeName(name)];
      if (file == null) return '';
      final data = file.readBytes();
      if (data == null || data.isEmpty) return '';
      return utf8.decode(data, allowMalformed: true);
    }

    final container = readText('META-INF/container.xml');
    final opfPath = RegExp(r'full-path="([^"]+)"')
        .firstMatch(container)
        ?.group(1);
    if (opfPath == null) {
      throw BookOpenException('"$title" has no readable table of contents.');
    }
    final opf = readText(opfPath);
    if (opf.isEmpty) {
      throw BookOpenException('"$title" is missing its book file.');
    }
    final baseDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/'))
        : '';

    // Manifest: id → file (only the text-ish documents matter to a reader).
    final manifest = <String, String>{};
    for (final tag in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final attrs = tag.group(0)!;
      final id = _attr(attrs, 'id');
      final href = _attr(attrs, 'href');
      if (id == null || href == null) continue;
      final mediaType = _attr(attrs, 'media-type') ?? '';
      if (mediaType.contains('html') ||
          mediaType.contains('xml') ||
          mediaType.isEmpty) {
        manifest[id] = href;
      }
    }

    // Spine: the reading order.
    final chapters = <BookChapter>[];
    for (final tag in RegExp(r'<itemref\b[^>]*>').allMatches(opf)) {
      if (chapters.length >= 300) break;
      final idref = _attr(tag.group(0)!, 'idref');
      if (idref == null) continue;
      final href = manifest[idref];
      if (href == null) continue;
      final html = readText(_resolve(baseDir, href));
      if (html.trim().isEmpty) continue;
      final body = htmlToText(html);
      if (body.isEmpty) continue;
      chapters.add(BookChapter(title: _chapterTitle(html, href), body: body));
    }
    if (chapters.isEmpty) {
      throw BookOpenException('"$title" has no readable chapters.');
    }
    return BookDocument(
      title: title,
      format: BookFormat.epub,
      chapters: chapters,
    );
  }

  /// First heading-ish text in the chapter, falling back to the file name.
  static String _chapterTitle(String html, String href) {
    final patterns = [
      RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true),
      RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false, dotAll: true),
      RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final text = htmlToText(match.group(1)!);
        if (text.isNotEmpty) return text;
      }
    }
    return titleOf(href);
  }

  /// Flattens an XHTML chapter into readable prose.
  static String htmlToText(String html) {
    var text = html;
    text = text.replaceAll(
      RegExp(
        r'<(script|style|head)\b[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(
        r'</(p|div|h[1-6]|li|tr|blockquote|section)>',
        caseSensitive: false,
      ),
      '\n\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _decodeEntities(text);
    text = text.replaceAll(RegExp(r'[ \t\f\v]+'), ' ');
    text = text.replaceAll(RegExp(r' ?\n ?'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static String _decodeEntities(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&hellip;', '…')
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      );

  // ── Shared helpers ────────────────────────────────────────────────────

  static String? _attr(String tag, String name) =>
      RegExp('\\b$name="([^"]*)"').firstMatch(tag)?.group(1);

  /// `PK`, the magic every zip — and so every EPUB, CBZ and "CBR that is
  /// really a zip" — starts with.
  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  /// Decodes [bytes] as a zip, or throws the explanation it deserves.
  ///
  /// The signature is checked first: a RAR decodes to an empty archive
  /// instead of failing, which would read as "your comic is empty" rather
  /// than "this is the one format we can't unpack".
  static Archive _decodeZip(Uint8List bytes, BookFormat format, String title) {
    if (_looksLikeZip(bytes)) {
      try {
        return ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        // Corrupt zip — fall through to the explanation below.
      }
    }
    if (format == BookFormat.cbr) {
      throw const BookOpenException(
        'CBR files are RAR archives, which can\'t be unpacked yet — '
        'save the comic as .cbz instead.',
      );
    }
    throw BookOpenException(
      '"$title" isn\'t a readable '
      '${format.isComic ? 'comic archive' : 'EPUB'}.',
    );
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  static String _normalizeName(String name) {
    var clean = name.replaceAll('\\', '/');
    while (clean.startsWith('./')) {
      clean = clean.substring(2);
    }
    return clean;
  }

  /// Joins an EPUB-relative href onto the folder its OPF lives in.
  static String _resolve(String baseDir, String href) {
    final clean = href.split('#').first.split('?').first;
    if (clean.startsWith('/')) return _normalizeName(clean);
    final parts = <String>[];
    for (final segment in baseDir.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      parts.add(segment);
    }
    for (final segment in clean.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  /// `page2` before `page10`: numeric runs compare as numbers.
  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+)|(\D+)');
    final left = pattern.allMatches(a.toLowerCase()).toList();
    final right = pattern.allMatches(b.toLowerCase()).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = left[i];
      final r = right[i];
      final lIsNumber = l.group(1) != null;
      final rIsNumber = r.group(1) != null;
      if (lIsNumber && rIsNumber) {
        final cmp = int.parse(l.group(1)!).compareTo(int.parse(r.group(1)!));
        if (cmp != 0) return cmp;
      } else {
        final cmp = l.group(0)!.compareTo(r.group(0)!);
        if (cmp != 0) return cmp;
      }
    }
    return left.length.compareTo(right.length);
  }
}
