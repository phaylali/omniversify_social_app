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

/// A complete, if tiny, EPUB: container, manifest, spine and two chapters.
Uint8List buildEpub() => buildZip({
      'META-INF/container.xml': '''
        <?xml version="1.0"?>
        <container>
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>'''.codeUnits,
      'OEBPS/content.opf': '''
        <package>
          <manifest>
            <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="text/chap2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
            <itemref idref="c2"/>
          </spine>
        </package>'''.codeUnits,
      'OEBPS/chap1.xhtml': '''
        <!DOCTYPE html>
        <html>
          <head><title>Ignored heading</title></head>
          <body>
            <h1>Setting Sail</h1>
            <p>Hello &amp; welcome aboard.</p>
            <script>ignoreMe();</script>
          </body>
        </html>'''.codeUnits,
      'OEBPS/text/chap2.xhtml': '''
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

    test('a real rar cbr explains itself instead of crashing', () async {
      // "Rar!" — the magic number of an archive we can't unpack.
      final rar = Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]);

      await expectLater(
        BookLoader.open(rar, 'comic.cbr'),
        throwsA(
          isA<BookOpenException>().having(
            (error) => error.message,
            'message',
            allOf(contains('CBR'), contains('.cbz')),
          ),
        ),
      );
    });

    test('an archive with no images says so', () async {
      final bytes = buildZip({'readme.txt': [1, 2]});

      await expectLater(
        BookLoader.open(bytes, 'empty.cbz'),
        throwsA(
          isA<BookOpenException>()
              .having((error) => error.message, 'message', contains('images')),
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
      expect(text.split('\n').where((line) => line.trim().isNotEmpty),
          hasLength(greaterThan(1)));
    });
  });
}
