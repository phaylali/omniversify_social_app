import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniversify_social_app/screens/folder_picker_screen.dart';
import 'package:omniversify_social_app/screens/reader_screen.dart';
import 'package:omniversify_social_app/services/book_loader.dart';
import 'package:omniversify_social_app/services/discover_source.dart';
import 'package:omniversify_social_app/services/local_books.dart';
import 'package:omniversify_social_app/services/reader_library.dart';
import 'package:omniversify_social_app/widgets/sliding_tabs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_test.dart' show buildZip;

/// The reader's three tabs — Local, Discover, Library — the sliding underline
/// they share with the rest of the app, and the Library's promise: a bar for
/// how far you got, and a tap that lands on exactly that page.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReaderLibrary.instance.clear();
    final local = LocalBooksService.instance;
    local.folders.value = [];
    local.byFolder.value = {};
    local.scanned.value = [];
    local.notice.value = null;
    local.busy.value = false;
  });

  /// Lets an "Opened" notice come and go: it floats over the viewer's bottom
  /// bar, so nothing down there can be tapped until it has left.
  Future<void> clearNotice(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  group('sliding tabs', () {
    testWidgets('labels report taps and only the active one turns gold', (
      tester,
    ) async {
      var selected = -1;
      var active = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SlidingTabs(
                labels: const ['Local', 'Discover', 'Library'],
                index: active,
                onSelect: (index) {
                  setState(() => active = index);
                  selected = index;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);

      final lit = tester.widget<Text>(find.text('Local'));
      final dim = tester.widget<Text>(find.text('Library'));
      expect(lit.style!.color!.a, greaterThan(dim.style!.color!.a));

      await tester.tap(find.text('Library'));
      await tester.pump();
      expect(selected, 2);
      final nowLit = tester.widget<Text>(find.text('Library'));
      expect(nowLit.style!.color!.a, greaterThan(dim.style!.color!.a));

      // The one already active does nothing rather than re-selecting itself.
      selected = -1;
      await tester.tap(find.text('Library'));
      await tester.pump();
      expect(selected, -1);
    });

    testWidgets('the underline glides to the new label over 300ms', (
      tester,
    ) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SlidingTabs(
                labels: const ['Local', 'Discover', 'Library'],
                index: selected,
                onSelect: (index) => setState(() => selected = index),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final underline = find.byKey(const ValueKey('sliding-tabs-underline'));
      final startX = tester.getTopLeft(underline).dx;
      expect(startX, 0);

      await tester.tap(find.text('Discover'));
      await tester.pump(); // the frame that starts the glide
      await tester.pump(const Duration(milliseconds: 100)); // mid-glide
      final movingX = tester.getTopLeft(underline).dx;
      expect(movingX, greaterThan(0));
      expect(
        movingX,
        lessThan(tester.getSize(find.byType(SlidingTabs)).width / 3),
      );

      await tester.pump(const Duration(milliseconds: 400));
      final endX = tester.getTopLeft(underline).dx;
      expect(
        endX,
        closeTo(tester.getSize(find.byType(SlidingTabs)).width / 3, 1),
      );
    });
  });

  group('reader tabs', () {
    testWidgets(
      'opens on Local with a book button and the two folder ways in',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
        await tester.pump();

        expect(find.text('Local'), findsOneWidget);
        expect(find.text('Discover'), findsOneWidget);
        expect(find.text('Library'), findsOneWidget);
        expect(find.text('Open a book'), findsOneWidget);
        expect(find.text('Add a folder'), findsOneWidget);
        expect(find.text('Scan this phone'), findsOneWidget);

        // Nothing is open yet, so the viewer isn't on screen.
        expect(find.textContaining('of 0'), findsNothing);
      },
    );

    testWidgets(
      'Discover searches the Archive without a network call until asked',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
        await tester.pump();

        await tester.tap(find.text('Discover'));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Internet Archive'), findsOneWidget);
        expect(find.textContaining('ADD SOURCE'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.textContaining('free, open, no sign-in'), findsOneWidget);
      },
    );

    testWidgets('Library starts empty and explains where books come from', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.textContaining('with a bar for how far you got'),
        findsOneWidget,
      );
    });

    testWidgets('the Local search narrows the books already found', (
      tester,
    ) async {
      final local = LocalBooksService.instance;
      local.folders.value = ['/storage/emulated/0/Comics'];
      local.byFolder.value = {
        '/storage/emulated/0/Comics': const [
          FoundBook(
            path: '/storage/emulated/0/Comics/batman.cbz',
            title: 'batman',
            format: BookFormat.cbz,
            sizeBytes: 5600000,
          ),
          FoundBook(
            path: '/storage/emulated/0/Comics/spiderman.cbr',
            title: 'spiderman',
            format: BookFormat.cbr,
            sizeBytes: 1200000,
          ),
        ],
      };

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      // The shelf shows both, each with where it lives.
      expect(find.text('batman'), findsOneWidget);
      expect(find.text('spiderman'), findsOneWidget);
      expect(find.text('~/Comics/batman.cbz'), findsOneWidget);
      expect(find.text('~/Comics/spiderman.cbr'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('local-book-search')),
        'spider',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // One flat list of matches, and the folder grouping steps aside.
      expect(find.text('spiderman'), findsOneWidget);
      expect(find.text('batman'), findsNothing);
      expect(find.text('1 MATCH'), findsOneWidget);
      expect(find.text('2 IN COMICS'), findsNothing);

      // A query nothing answers says so instead of showing an empty shelf.
      await tester.enterText(
        find.byKey(const ValueKey('local-book-search')),
        'zorro',
      );
      await tester.pump();
      expect(
        find.text('No local books match "zorro".'),
        findsOneWidget,
      );

      // Clearing it puts the shelf back exactly as it was.
      await tester.tap(find.byKey(const ValueKey('local-book-search-clear')));
      await tester.pump();
      expect(find.text('batman'), findsOneWidget);
      expect(find.text('2 IN COMICS'), findsOneWidget);
    });

    testWidgets('the shelf filters by format and sorts by size', (
      tester,
    ) async {
      final local = LocalBooksService.instance;
      local.folders.value = [
        '/storage/emulated/0/Comics',
        '/storage/emulated/0/Novels',
      ];
      local.byFolder.value = {
        '/storage/emulated/0/Comics': const [
          FoundBook(
            path: '/storage/emulated/0/Comics/small.cbz',
            title: 'small',
            format: BookFormat.cbz,
            sizeBytes: 9000000,
          ),
          FoundBook(
            path: '/storage/emulated/0/Comics/big.epub',
            title: 'big',
            format: BookFormat.epub,
            sizeBytes: 5000,
          ),
          FoundBook(
            path: '/storage/emulated/0/Comics/notes.pdf',
            title: 'notes',
            format: BookFormat.pdf,
            sizeBytes: 90000,
          ),
        ],
        '/storage/emulated/0/Novels': const [
          FoundBook(
            path: '/storage/emulated/0/Novels/story.pdf',
            title: 'story',
            format: BookFormat.pdf,
            sizeBytes: 700000,
          ),
        ],
      };

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      double yOf(String text) => tester.getTopLeft(find.text(text)).dy;

      // A→Z unless told otherwise.
      expect(yOf('big'), lessThan(yOf('notes')));
      expect(yOf('notes'), lessThan(yOf('small')));

      // Biggest file first once SIZE is picked — the order flips.
      await tester.tap(find.byKey(const ValueKey('local-sort-size')));
      await tester.pump();
      expect(yOf('small'), lessThan(yOf('notes')));
      expect(yOf('notes'), lessThan(yOf('big')));

      // The chips keep one kind of book and count them in the header.
      await tester.tap(find.byKey(const ValueKey('local-filter-epub')));
      await tester.pump();
      expect(find.text('big'), findsOneWidget);
      expect(find.text('small'), findsNothing);
      expect(find.text('notes'), findsNothing);
      expect(find.text('1 IN COMICS'), findsOneWidget);
      // A folder without that kind says so rather than sitting blank.
      expect(find.text('0 IN NOVELS'), findsOneWidget);
      expect(find.text('No EPUB books in Novels.'), findsOneWidget);

      // …and so does the scan-style count when comics are asked for.
      await tester.tap(find.byKey(const ValueKey('local-filter-comics')));
      await tester.pump();
      expect(find.text('big'), findsNothing);
      expect(find.text('small'), findsOneWidget);
      expect(find.text('No COMICS books in Novels.'), findsOneWidget);

      // PDF is in both folders, so both count it.
      await tester.tap(find.byKey(const ValueKey('local-filter-pdf')));
      await tester.pump();
      expect(find.text('notes'), findsOneWidget);
      expect(find.text('story'), findsOneWidget);
      expect(find.text('1 IN COMICS'), findsOneWidget);
      expect(find.text('1 IN NOVELS'), findsOneWidget);

      // ALL puts everything back.
      await tester.tap(find.byKey(const ValueKey('local-filter-all')));
      await tester.pump();
      expect(find.text('big'), findsOneWidget);
      expect(find.text('notes'), findsOneWidget);
      expect(find.text('small'), findsOneWidget);
      expect(find.text('3 IN COMICS'), findsOneWidget);
    });

    testWidgets('the share button lives in the viewer, by the privacy chip', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('reader_share');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/notes.cbz');
      file.writeAsBytesSync(buildZip({'page1.png': [1]}));
      final local = LocalBooksService.instance;
      local.folders.value = [dir.path];
      local.byFolder.value = {
        dir.path: [
          FoundBook(
            path: file.path,
            title: 'notes',
            format: BookFormat.cbz,
            sizeBytes: 8,
          ),
        ],
      };

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      // The shelf row only opens the book — sharing belongs to the viewer.
      expect(find.byKey(ValueKey('local-share-${file.path}')), findsNothing);

      // Opening reads a real file, which the fake clock can't complete —
      // run the tap in a real-async window, then let the viewer render.
      await tester.runAsync(() async {
        await tester.tap(find.text('notes'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Page 1 of 1'), findsOneWidget);
      // Let the "Opened" notice clear — it floats over the bottom bar.
      await clearNotice(tester);

      final share = find.byKey(const ValueKey('viewer-share'));
      expect(share, findsOneWidget);
      // Right beside the chip that says who may see it.
      expect(
        tester.getCenter(share).dy,
        closeTo(tester.getCenter(find.byKey(const ValueKey('viewer-privacy'))).dy, 6),
      );

      await tester.tap(share);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The app's own sheet, with "Other apps" leading to the system one.
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Other apps'), findsOneWidget);

      await tester.tapAt(const Offset(6, 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Other apps'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a file that has since vanished says so instead of sharing', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('reader_gone');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/gone.cbz');
      file.writeAsBytesSync(buildZip({'page1.png': [1]}));
      final local = LocalBooksService.instance;
      local.folders.value = [dir.path];
      local.byFolder.value = {
        dir.path: [
          FoundBook(
            path: file.path,
            title: 'gone',
            format: BookFormat.cbz,
            sizeBytes: 8,
          ),
        ],
      };

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('gone'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Page 1 of 1'), findsOneWidget);
      await clearNotice(tester);

      // The comic is open, but the bytes have left the phone since.
      file.deleteSync();

      await tester.tap(find.byKey(const ValueKey('viewer-share')));
      await tester.pump();

      expect(
        find.text('That file is no longer on this phone.'),
        findsOneWidget,
      );
      expect(find.text('Other apps'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('library progress', () {
    test('remembers the page, the shelf order and where it resumes', () async {
      final lib = ReaderLibrary.instance;

      await lib.record(
        path: '/books/absolute_batman.cbr',
        title: 'Absolute Batman',
        format: 'cbr',
        page: 4,
        pages: 20,
      );
      await lib.record(
        path: '/books/moby_dick.epub',
        title: 'Moby Dick',
        format: 'epub',
        page: 1,
        pages: 222,
      );

      final entry = lib.find('/books/absolute_batman.cbr')!;
      expect(entry.label, '4/20');
      expect(entry.progress, closeTo(0.2, 0.0001));
      expect(entry.resumeIndex, 3);
      expect(entry.source, 'local');
      expect(lib.entries.value.first.title, 'Moby Dick'); // newest first

      // Turning back to the same book moves it up and keeps the counts.
      await lib.record(
        path: '/books/absolute_batman.cbr',
        title: 'Absolute Batman',
        format: 'cbr',
        page: 5,
        pages: 20,
      );
      expect(lib.entries.value.first.path, '/books/absolute_batman.cbr');
      expect(lib.find('/books/absolute_batman.cbr')!.label, '5/20');
      expect(lib.entries.value, hasLength(2));

      await lib.remove('/books/absolute_batman.cbr');
      expect(lib.find('/books/absolute_batman.cbr'), isNull);
      expect(lib.entries.value, hasLength(1));
    });

    test(
      'round-trips through preferences so a restart keeps the shelf',
      () async {
        final lib = ReaderLibrary.instance;
        await lib.record(
          path: '/books/kraven.cbz',
          title: 'Kraven',
          format: 'cbz',
          page: 7,
          pages: 30,
          source: 'discover',
        );

        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString('reader_library_v1');
        expect(stored, isNotNull);

        final decoded = LibraryEntry.fromJson(
          (jsonDecode(stored!) as List).first as Map<String, Object?>,
        );
        expect(decoded.path, '/books/kraven.cbz');
        expect(decoded.label, '7/30');
        expect(decoded.resumeIndex, 6);
        expect(decoded.source, 'discover');
        expect(decoded.toJson(), decoded.toJson());
      },
    );

    test('keeps the shelf to one screenful of rows', () async {
      final lib = ReaderLibrary.instance;
      for (var i = 0; i < 40; i++) {
        await lib.record(
          path: '/books/book$i.cbz',
          title: 'Book $i',
          format: 'cbz',
          page: i + 1,
          pages: 100,
        );
      }
      expect(lib.entries.value, hasLength(30));
      expect(lib.entries.value.first.path, '/books/book39.cbz');
    });
  });

  group('discover source', () {
    test('turns an Archive search response into cover cards', () {
      const body = '''
{"response":{"numFound":3,"docs":[
  {"identifier":"batman150","title":"Batman 1940 (1-50)","year":1940,"downloads":107345},
  {"identifier":"killing-joke","title":["Batman: The Killing Joke Graphic Novel"]},
  {"title":"no identifier here"}
]}}''';
      final items = InternetArchiveSource.parseSearch(body);
      expect(items, hasLength(2));
      expect(items.first.title, 'Batman 1940 (1-50)');
      expect(
        items.first.coverUrl,
        'https://archive.org/services/img/batman150',
      );
      expect(items.first.meta, '1940');
      expect(items[1].title, 'Batman: The Killing Joke Graphic Novel');
      expect(items[1].meta, isEmpty);
    });

    test(
      'asks for titles that are documents, so loose photo dumps stay out',
      () {
        final query = InternetArchiveSource.searchQuery('absolute batman');
        expect(query, contains('title:(absolute batman)'));
        expect(query, contains('mediatype:(texts)'));
      },
    );

    test('prefers the comic archive over the PDF and the OCR text', () {
      const body = '''
{"server":"ia801900.us.archive.org","dir":"/35/items/batman150","files":[
  {"name":"Batman 001_djvu.txt","format":"DjVuTXT","size":"819"},
  {"name":"Batman 001.epub","format":"EPUB","size":"4300000"},
  {"name":"Batman 001.pdf","format":"Text PDF","size":"1500000"},
  {"name":"Batman 001.cbr","format":"Comic Book RAR","size":"8100000"}
]}''';
      final file = InternetArchiveSource.pickFile(body, 'batman150')!;
      expect(file.extension, 'cbr');
      expect(file.sizeBytes, 8100000);
      expect(
        file.url,
        'https://ia801900.us.archive.org/35/items/batman150/Batman%20001.cbr',
      );
    });

    test('keeps the folders a book ships in when building its URL', () {
      const body = '''
{"server":"ia903103.us.archive.org","dir":"/27/items/dk3","files":[
  {"name":"Batman The Dark Knight Returns/Batman 03.cbr","format":"Comic Book RAR","size":"60100000"}
]}''';
      final file = InternetArchiveSource.pickFile(body, 'dk3')!;
      expect(
        file.url,
        'https://ia903103.us.archive.org/27/items/dk3/'
        'Batman%20The%20Dark%20Knight%20Returns/Batman%2003.cbr',
      );
      expect(file.name, 'Batman 03.cbr');
    });

    test('says nothing when an item holds no format we can read', () {
      const body = '''
{"server":"ia1","dir":"/1/items/x","files":[
  {"name":"x_djvu.txt","format":"DjVuTXT","size":"10"},
  {"name":"x_meta.xml","format":"Metadata","size":"1237"}
]}''';
      expect(InternetArchiveSource.pickFile(body, 'x'), isNull);
      expect(InternetArchiveSource.pickFile('[]', 'x'), isNull);
    });

    test('falls back to the plain download URL without a node', () {
      const body = '''
{"files":[{"name":"kraven2.cbz","format":"Zip","size":"500000"}]}''';
      final file = InternetArchiveSource.pickFile(body, 'kraven-2')!;
      expect(file.url, 'https://archive.org/download/kraven-2/kraven2.cbz');
      expect(file.extension, 'cbz');
    });
  });

  group('local folders', () {
    test('a scan starts from a single root, never two for one disk', () async {
      final roots = await LocalBooksService.phoneRoots();
      expect(roots.length, lessThanOrEqualTo(1));
    });

    test('a scan walks into sub-folders instead of stopping at the top', () {
      final root = Directory.systemTemp.createTempSync('reader_folders');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/Comics/DC').createSync(recursive: true);
      Directory('${root.path}/Novels').createSync(recursive: true);
      File('${root.path}/Comics/DC/batman.cbz').writeAsBytesSync([1, 2, 3]);
      File('${root.path}/Novels/moby_dick.epub').writeAsBytesSync([1, 2, 3]);
      File('${root.path}/readme.txt').writeAsBytesSync([1, 2, 3]);

      final books = LocalBooksService.findBooks(root.path);

      expect(
        books.map((book) => book.title),
        containsAll(['batman', 'moby_dick']),
      );
      expect(books.map((book) => book.title), isNot(contains('readme')));
      expect(books.first.size, isNotEmpty);
    });

    test('a path reads as ~ wherever the phone keeps the file', () {
      FoundBook book(String path) => FoundBook(
        path: path,
        title: 'x',
        format: BookFormat.cbz,
        sizeBytes: 1000,
      );

      expect(
        book('/storage/emulated/0/Download/file.pdf').displayPath,
        '~/Download/file.pdf',
      );
      expect(
        book('/storage/emulated/0/Comics/autobackup/chapter1.cbz').displayPath,
        '~/Comics/autobackup/chapter1.cbz',
      );

      // Long folder chains keep the name and the folder it sits in.
      expect(
        book(
          '/storage/emulated/0/Documents/backup/older/comics/collection/'
          'batman.cbz',
        ).displayPath,
        '~/…/collection/batman.cbz',
      );

      // When even that is too long, the file name is what survives.
      expect(
        book(
          '/storage/emulated/0/Documents/library/backup/series/2026/omnibus/'
          'the absolute batman omnibus volume one.cbz',
        ).displayPath,
        '~/…/the absolute batman omnibus volume one.cbz',
      );

      // A path outside shared storage isn't pretended to be home.
      expect(book('/data/local/tmp/x.pdf').displayPath, '/data/local/tmp/x.pdf');
    });

    testWidgets('the folder browser lists the folders it can see', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('reader_picker');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/Comics').createSync(recursive: true);
      Directory('${root.path}/Novels').createSync(recursive: true);
      File('${root.path}/cover.png').createSync();

      await tester.pumpWidget(
        MaterialApp(home: FolderPickerScreen(startPath: root.path)),
      );
      await tester.pump();
      await tester.pump();

      // Folders only — loose files aren't things you can add.
      expect(find.text('Comics'), findsOneWidget);
      expect(find.text('Novels'), findsOneWidget);
      expect(find.text('cover.png'), findsNothing);
      expect(find.text('Add this folder'), findsOneWidget);

      await tester.tap(find.text('Comics'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Comics'), findsOneWidget); // now the title bar
      expect(find.text('No folders inside.'), findsOneWidget);
    });
  });

  group('library row', () {
    testWidgets('shows 4/20 style progress and resumes on exactly that page', (
      tester,
    ) async {
      // A real six-page comic on disk, left at page 4.
      final dir = Directory.systemTemp.createTempSync('reader_tabs');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/six_pages.cbz');
      file.writeAsBytesSync(
        buildZip({
          for (var i = 1; i <= 6; i++) 'page$i.png': [i],
        }),
      );

      await ReaderLibrary.instance.record(
        path: file.path,
        title: 'Six Pages',
        format: 'cbz',
        page: 4,
        pages: 6,
      );

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();

      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Six Pages'), findsOneWidget);
      expect(find.text('4/6'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(4 / 6, 0.0001));

      // Opening reads a real file, which the fake clock can't complete —
      // run the tap in a real-async window, then let the viewer render.
      await tester.runAsync(() async {
        await tester.tap(find.text('Six Pages'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Page 4 of 6'), findsOneWidget);
      expect(find.text('Six Pages'), findsOneWidget);

      // Let the page counter's save land, then close everything cleanly.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('viewer zoom', () {
    /// Puts a real six-page comic on the shelf and opens it in the viewer.
    Future<void> openSixPages(WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync('reader_zoom');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/six_pages.cbz');
      file.writeAsBytesSync(
        buildZip({for (var i = 1; i <= 6; i++) 'page$i.png': [i]}),
      );
      final local = LocalBooksService.instance;
      local.folders.value = [dir.path];
      local.byFolder.value = {
        dir.path: [
          FoundBook(
            path: file.path,
            title: 'Six Pages',
            format: BookFormat.cbz,
            sizeBytes: 24,
          ),
        ],
      };

      await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Six Pages'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Page 1 of 6'), findsOneWidget);
      // Let the "Opened" notice clear — it floats over the bottom bar.
      await clearNotice(tester);
    }

    testWidgets('one flick turns the page even though pages can zoom', (
      tester,
    ) async {
      await openSixPages(tester);

      // Every page is wrapped for pinching, but at 1:1 it claims nothing.
      expect(find.byKey(const ValueKey('page-zoom-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-zoom-reset')), findsNothing);

      // One fast thumb — moved further than a pinch's first step in a single
      // event — must still belong to the page view.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Page 2 of 6'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('pinch zooms, then the page pans instead of turning', (
      tester,
    ) async {
      await openSixPages(tester);

      final center = tester.getCenter(find.byKey(const ValueKey('page-zoom-0-0')));
      final left = await tester.startGesture(center - const Offset(60, 0), pointer: 11);
      final right = await tester.startGesture(center + const Offset(60, 0), pointer: 12);
      // Two thumbs spreading, one small step at a time.
      for (var i = 0; i < 3; i++) {
        await left.moveBy(const Offset(-30, 0));
        await right.moveBy(const Offset(30, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Zoomed in, the page view hands its swipes over.
      expect(find.byKey(const ValueKey('viewer-zoom-reset')), findsOneWidget);
      expect(find.text('Page 1 of 6'), findsOneWidget);

      // One finger now drags the zoomed page about instead of turning it.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Page 1 of 6'), findsOneWidget);

      // Snapping back to 1:1 gives swipes to the page view again.
      await tester.tap(find.byKey(const ValueKey('viewer-zoom-reset')));
      await tester.pump();
      expect(find.byKey(const ValueKey('viewer-zoom-reset')), findsNothing);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Page 2 of 6'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
