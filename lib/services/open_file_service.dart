import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/reader_screen.dart';
import '../widgets/action_sheet.dart';

/// A book another app opens with us — Downloads, a file manager, anything
/// that offers "Open with Omniversify".
///
/// Android hands the file over as a `content://` URI, which Dart can't read
/// by itself, so the platform copies it into this app's own storage first
/// (`MainActivity.materialize`) and hands back a plain path.
///
/// The reader takes it from there: if one is already on screen the book is
/// opened in place rather than under a second reader, otherwise a reader is
/// pushed for it.
class OpenFileService {
  OpenFileService._();
  static final OpenFileService instance = OpenFileService._();

  static const _channel = MethodChannel('omniversify/open_file');

  /// Shared with [DeepLinkService]: one view of every link the app is
  /// opened with, whichever of the two cares about it.
  final _appLinks = AppLinks();

  /// The reader while one is mounted.
  Future<void> Function(String path, {String? title})? _reading;

  /// A book waiting for a reader — set the moment it arrives, cleared when
  /// the reader takes it.
  ({String path, String? title})? _pending;

  /// Set while a reader is being pushed for [_pending], so a second file in
  /// that same frame doesn't push a second reader.
  bool _pushing = false;

  GlobalKey<NavigatorState>? _navigator;

  /// The last file taken: a cold-start link reaches us twice — once pulled
  /// from [AppLinks.getInitialLink], once pushed on the stream.
  Uri? _lastUri;
  var _lastAt = 0;

  /// Start listening. Call once after the first frame.
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigator = navigatorKey;
    // A browser can't hand us a book; its links are DeepLinkService's job.
    if (kIsWeb) return;

    final initial = await _appLinks.getInitialLink();
    if (initial != null) await handleUri(initial);
    _appLinks.uriLinkStream.listen(handleUri);
  }

  /// Takes one URI the app was opened with. Anything that isn't a local
  /// file — an https link, say — is left alone for [DeepLinkService].
  Future<void> handleUri(Uri uri) async {
    if (uri.scheme != 'content' && uri.scheme != 'file') return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (uri == _lastUri && now - _lastAt < 3000) return;
    _lastUri = uri;
    _lastAt = now;

    String? path;
    try {
      path = await _channel.invokeMethod<String>(
        'materialize',
        {'uri': uri.toString()},
      );
    } on PlatformException catch (error) {
      _say(error.message ?? 'That file couldn\'t be opened.');
      return;
    } on MissingPluginException {
      // Nothing on the other side (the web build, a test): nothing to open.
      return;
    }
    if (path != null) open(path);
  }

  /// Hands a book on this phone to the reader.
  void open(String path, {String? title}) {
    _pending = (path: path, title: title);
    _flushOrPush();
  }

  /// The reader registers itself on its way in and unregisters on the way
  /// out, so [open] always knows whether one is there to take the book.
  void attach(Future<void> Function(String path, {String? title}) reader) {
    _reading = reader;
    _pushing = false;
    _flushOrPush();
  }

  void detach(Future<void> Function(String path, {String? title}) reader) {
    if (_reading != reader) return;
    _reading = null;
    // A book that turned up as the reader closed still deserves one.
    if (_pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flushOrPush());
    }
  }

  void _flushOrPush() {
    final pending = _pending;
    if (pending == null) return;

    final reading = _reading;
    if (reading != null) {
      _pending = null;
      reading(pending.path, title: pending.title);
      return;
    }

    if (_pushing) return;
    final navigator = _navigator?.currentState;
    if (navigator == null) return;
    _pushing = true;
    navigator.push<void>(MaterialPageRoute(builder: (_) => const ReaderScreen()));
  }

  void _say(String message) {
    final context = _navigator?.currentContext;
    if (context != null) showActionNotice(context, message);
  }
}
