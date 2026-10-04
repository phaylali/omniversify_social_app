import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniversify_social_app/screens/reader_screen.dart';
import 'package:omniversify_social_app/services/local_books.dart';
import 'package:omniversify_social_app/services/open_file_service.dart';
import 'package:omniversify_social_app/services/reader_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_reader_test.dart' show buildZip;

/// "Open with Omniversify": a book another app opens with us, from the URI
/// Android hands down to the reader it ends up in.
void main() {
  /// The platform's half of the hand-over — it turns the URI into a path.
  /// The copy is skipped here: each test's own fixture path comes back.
  void mockBooks(WidgetTester tester, String Function(String uri) pathFor) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('omniversify/open_file'),
      (call) async => call.method == 'materialize'
          ? pathFor((call.arguments as Map)['uri'] as String)
          : null,
    );
  }

  /// What the app listens to for intents: a link to start with, plus a
  /// stream that stays quiet — the tests hand their files over directly.
  void mockIntents(WidgetTester tester, {String? initial}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => call.method == 'getInitialLink' ? initial : null,
    );
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  }

  /// The app as it starts: a home screen with the navigator the reader is
  /// pushed on, and the links read once the first frame is up — exactly as
  /// main() wires it.
  Future<void> pumpHome(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('Home'))),
      ),
    );
    await tester.pump();
    await OpenFileService.instance.init(navigatorKey);
  }

  /// The book reads itself off disk, which the fake clock can't do — so the
  /// frame that starts it runs in a real-async window, and the viewer gets
  /// a frame or two after that.
  Future<void> letBookOpen(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// A file arriving while the app runs, real-async window and all.
  Future<void> handOver(WidgetTester tester, String uri) async {
    await tester.runAsync(() async {
      await OpenFileService.instance.handleUri(Uri.parse(uri));
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Lets a notice finish its time on screen — it floats over the bottom
  /// bar, and a second one stacking on it races the first one's exit.
  Future<void> settleNotice(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  /// A notice is settled, the screen goes, and nothing is left ticking.
  Future<void> closeScreen(WidgetTester tester) async {
    await settleNotice(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

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

  testWidgets('a book another app opens with us lands in the reader', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('open_with');
    addTearDown(() => dir.deleteSync(recursive: true));
    final book = File('${dir.path}/notes.cbz')
      ..writeAsBytesSync(buildZip({'page1.png': [1]}));

    mockBooks(tester, (_) => book.path);
    mockIntents(tester, initial: 'content://downloads/notes.cbz');
    await pumpHome(tester);

    // The URI the platform was handed became a path, and the reader was
    // pushed to show it — a book named after the file, not the URI.
    await letBookOpen(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Opened "notes"'), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('a second book opens over the one showing, not over it', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('open_with_twice');
    addTearDown(() => dir.deleteSync(recursive: true));
    final one = File('${dir.path}/one.cbz')
      ..writeAsBytesSync(buildZip({'page1.png': [1]}));
    final two = File('${dir.path}/two.cbz')
      ..writeAsBytesSync(buildZip({'page1.png': [1], 'page2.png': [2]}));

    mockBooks(tester, (uri) => uri.contains('two') ? two.path : one.path);
    mockIntents(tester, initial: 'content://downloads/one.cbz');
    await pumpHome(tester);
    await letBookOpen(tester);
    expect(find.text('Page 1 of 1'), findsOneWidget);

    // The first book's notice gets its full time on screen first, so the
    // two aren't both asking for the bottom bar at once.
    await settleNotice(tester);

    // Someone taps another comic while this one is open: the book changes,
    // the screen doesn't.
    await handOver(tester, 'content://downloads/two.cbz');

    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('a comment link is left to the deep links', (tester) async {
    final dir = Directory.systemTemp.createTempSync('open_with_link');
    addTearDown(() => dir.deleteSync(recursive: true));
    final book = File('${dir.path}/notes.cbz')
      ..writeAsBytesSync(buildZip({'page1.png': [1]}));

    // Had the link been read as a file, this book would have opened.
    mockBooks(tester, (_) => book.path);
    mockIntents(
      tester,
      initial: 'https://app.omniversify.com/post/abc/comment/1-c1',
    );
    await pumpHome(tester);
    await tester.pump();

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);

    await closeScreen(tester);
  });

  testWidgets('a file that has left the phone says so', (tester) async {
    mockBooks(tester, (_) {
      throw PlatformException(
        code: 'open',
        message: 'That file is no longer on this phone.',
      );
    });
    mockIntents(tester, initial: 'content://downloads/gone.cbz');
    await pumpHome(tester);

    await tester.pump();
    expect(find.text('That file is no longer on this phone.'), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);

    await closeScreen(tester);
  });
}
