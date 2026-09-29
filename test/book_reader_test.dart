import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniversify_social_app/services/book_loader.dart';

/// A zip built in memory, the way a comic archive or an EPUB really is.
Uint8List buildZip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach(
    (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A RAR4 archive built by hand — the format classic `.cbr` comics are in,
/// which no Dart library can *write*, so the container is assembled here.
///
/// Adapted from `koni_rar`'s `test/src/rar4_builder.dart` (MIT): every header
/// carries the low 16 bits of its CRC-32, every file the CRC-32 of its data,
/// and the method byte stays at 0x30 (store) since the reader must decode the
/// bytes exactly as given.
Uint8List buildRar4(Map<String, List<int>> files) {
  final out = BytesBuilder(copy: false)
    ..add([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]); // signature

  final main = BytesBuilder(copy: false)
    ..add([0x73]) // MAIN_HEAD
    ..add([0x00, 0x00]) // flags
    ..add([0x0D, 0x00]) // size = 13
    ..add([0x00, 0x00]) // highposav
    ..add([0x00, 0x00, 0x00, 0x00]); // posav
  out.add(_withHeaderCrc(main.takeBytes()));

  for (final MapEntry(key: name, value: content) in files.entries) {
    final nameBytes = utf8.encode(name);
    final data = Uint8List.fromList(content);
    final headerSize = 7 + 25 + nameBytes.length;
    final body = BytesBuilder(copy: false)
      ..add([0x74]) // FILE_HEAD
      ..add([0x00, 0x00]) // flags
      ..add(_le16(headerSize))
      ..add(_le32(data.length)) // pack size
      ..add(_le32(data.length)) // unpacked size
      ..add([0x00]) // host os = MS-DOS
      ..add(_le32(getCrc32(data)))
      ..add(_le32(0)) // file time
      ..add([20]) // unpack version
      ..add([0x30]) // method = store
      ..add(_le16(nameBytes.length))
      ..add(_le32(0)) // attributes
      ..add(nameBytes);
    out.add(_withHeaderCrc(body.takeBytes()));
    out.add(data);
  }

  final end = BytesBuilder(copy: false)
    ..add([0x7B]) // ENDARC_HEAD
    ..add([0x00, 0x00])
    ..add([0x07, 0x00]);
  out.add(_withHeaderCrc(end.takeBytes()));
  return out.takeBytes();
}

/// CRC-32 of [header], low 16 bits first, prepended as the header checksum.
Uint8List _withHeaderCrc(Uint8List header) {
  final crc = getCrc32(header);
  return Uint8List.fromList([crc & 0xFF, (crc >> 8) & 0xFF, ...header]);
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

/// A real archive from `test/resources/`, both from the `koni_rar`
/// fixtures (MIT) — see the README beside them.
Uint8List fixture(String name) =>
    Uint8List.fromList(File('test/resources/$name').readAsBytesSync());

/// A complete, if tiny, EPUB: container, manifest, spine and two chapters.
Uint8List buildEpub() => buildZip({
  'META-INF/container.xml':
      '''
        <?xml version="1.0"?>
        <container>
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>'''
          .codeUnits,
  'OEBPS/content.opf':
      '''
        <package>
          <manifest>
            <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="text/chap2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
            <itemref idref="c2"/>
          </spine>
        </package>'''
          .codeUnits,
  'OEBPS/chap1.xhtml':
      '''
        <!DOCTYPE html>
        <html>
          <head><title>Ignored heading</title></head>
          <body>
            <h1>Setting Sail</h1>
            <p>Hello &amp; welcome aboard.</p>
            <script>ignoreMe();</script>
          </body>
        </html>'''
          .codeUnits,
  'OEBPS/text/chap2.xhtml':
      '''
        <html><body><h2>Deep Water</h2><p>The second chapter.</p></body></html>'''
          .codeUnits,
});

void main() {
  group('format detection', () {
    test('reads the extension whatever its case', () {
      expect(BookLoader.formatOf('novel.epub'), BookFormat.epub);
      expect(BookLoader.formatOf('NOVEL.EPUB'), BookFormat.epub);
      expect(BookLoader.formatOf('issue 12.cbz'), BookFormat.cbz);
      expect(BookLoader.formatOf('issue 12.cbr'), BookFormat.cbr);
      expect(BookLoader.formatOf('/sdcard/Books/a.pdf'), BookFormat.pdf);
      expect(BookLoader.formatOf('notes.txt'), isNull);
      expect(BookLoader.formatOf('noextension'), isNull);
      expect(BookLoader.formatOf('trailing.'), isNull);
    });

    test('titles come from the file name alone', () {
      expect(BookLoader.titleOf('/sdcard/Books/moby-dick.epub'), 'moby-dick');
      expect(BookLoader.titleOf('issue 12.cbz'), 'issue 12');
      expect(BookLoader.titleOf('plain'), 'plain');
    });
  });

  group('comics', () {
    test('a cbz opens page by page in natural order', () async {
      final bytes = buildZip({
        'page1.jpg': [1, 2, 3],
        'page10.jpg': [7, 8, 9],
        'page2.jpg': [4, 5, 6],
        'notes.txt': [0],
      });

      final doc = await BookLoader.open(bytes, 'my comic.cbz');

      expect(doc.format, BookFormat.cbz);
      expect(doc.title, 'my comic');
      expect(doc.pageCount, 3);
      // Natural order: 1, 2, 10 — lexicographic would put 10 second.
      expect(doc.images[0], orderedEquals([1, 2, 3]));
      expect(doc.images[1], orderedEquals([4, 5, 6]));
      expect(doc.images[2], orderedEquals([7, 8, 9]));
      expect(doc.unit, 'Page');
    });

    test('a cbr that is really a zip still opens', () async {
      final bytes = buildZip({
        'p1.png': [1],
        'p2.png': [2],
      });

      final doc = await BookLoader.open(bytes, 'mislabelled.cbr');

      expect(doc.format, BookFormat.cbr);
      expect(doc.pageCount, 2);
    });

    test('a real rar cbr opens its pages', () async {
      final doc = await BookLoader.open(
        fixture('synthetic_comic.cbr'),
        'issue 1.cbr',
      );

      expect(doc.format, BookFormat.cbr);
      expect(doc.title, 'issue 1');
      // Three PNGs; ComicInfo.xml is not a page.
      expect(doc.pageCount, 3);
      expect(doc.images.first, isNotEmpty);
      expect(doc.unit, 'Page');
    });

    test('a rar4 cbr — the old kind — opens too', () async {
      final rar = buildRar4({
        'pages/001.png': [1, 2, 3],
        'pages/002.png': [4, 5],
        'cover.txt': [9],
      });

      final doc = await BookLoader.open(rar, 'classic.cbr');

      expect(doc.pageCount, 2);
      expect(doc.images[0], orderedEquals([1, 2, 3]));
      expect(doc.images[1], orderedEquals([4, 5]));
    });

    test('a password-protected cbr says what is wrong', () async {
      await expectLater(
        BookLoader.open(fixture('encrypted_headers.rar'), 'locked.cbr'),
        throwsA(
          isA<BookOpenException>().having(
            (error) => error.message,
            'message',
            contains('password'),
          ),
        ),
      );
    });

    test('a file that is no archive at all says so', () async {
      await expectLater(
        BookLoader.open(
          Uint8List.fromList([0x52, 0x61, 0x72, 0x21]),
          'truncated.cbr',
        ),
        throwsA(
          isA<BookOpenException>().having(
            (error) => error.message,
            'message',
            contains('comic archive'),
          ),
        ),
      );
    });

    test('an archive with no images says so', () async {
      final bytes = buildZip({
        'readme.txt': [1, 2],
      });

      await expectLater(
        BookLoader.open(bytes, 'empty.cbz'),
        throwsA(
          isA<BookOpenException>().having(
            (error) => error.message,
            'message',
            contains('images'),
          ),
        ),
      );
    });
  });

  group('epub', () {
    test('follows the spine into plain chapters', () async {
      final doc = await BookLoader.open(buildEpub(), 'odyssey.epub');

      expect(doc.format, BookFormat.epub);
      expect(doc.title, 'odyssey');
      expect(doc.unit, 'Chapter');
      expect(doc.chapters, hasLength(2));

      // Spine order, heading picked up from the chapter itself.
      expect(doc.chapters[0].title, 'Setting Sail');
      expect(doc.chapters[1].title, 'Deep Water');
      expect(doc.chapters[1].body, contains('The second chapter.'));

      // Tags and scripts are gone; entities are decoded.
      expect(doc.chapters[0].body, contains('Hello & welcome aboard.'));
      expect(doc.chapters[0].body, isNot(contains('<p>')));
      expect(doc.chapters[0].body, isNot(contains('ignoreMe')));
    });

    test('resolves chapters living in sub-folders', () async {
      final doc = await BookLoader.open(buildEpub(), 'odyssey.epub');

      expect(doc.chapters[1].body, contains('The second chapter.'));
    });

    test('a file that is not an epub says so', () async {
      await expectLater(
        BookLoader.open(Uint8List.fromList([1, 2, 3]), 'broken.epub'),
        throwsA(isA<BookOpenException>()),
      );
    });
  });

  group('unsupported files', () {
    test('refuses anything outside the four formats', () async {
      await expectLater(
        BookLoader.open(Uint8List.fromList([1]), 'spreadsheet.xlsx'),
        throwsA(
          isA<BookOpenException>().having(
            (error) => error.message,
            'message',
            contains('PDF, EPUB, CBZ or CBR'),
          ),
        ),
      );
    });
  });

  group('html to text', () {
    test('keeps paragraphs apart and drops the markup', () {
      final text = BookLoader.htmlToText(
        '<h2>A Head</h2><p>First</p><br/>Second<p>Third &ldquo;quoted&rdquo;</p>',
      );

      expect(text, contains('A Head'));
      expect(text, contains('First'));
      expect(text, contains('Second'));
      expect(text, contains('Third'));
      expect(text, isNot(contains('<')));
      expect(
        text.split('\n').where((line) => line.trim().isNotEmpty),
        hasLength(greaterThan(1)),
      );
    });
  });
}
