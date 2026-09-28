import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/post_interaction_panel.dart';

/// Opens the Comments panel from an Omniversify link.
///
/// Supported link shapes (Android intent or web URL):
///   https://app.omniversify.com/post/USER_HANDLE/comment/1-c5
///   https://app.omniversify.com/scroll/3/comment/scroll_3-c0
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();

  /// Start listening. Call once after the first frame.
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    // Web cold start: the path lives in Uri.base (app_links doesn't cover web here).
    if (kIsWeb) {
      _open(navigatorKey, Uri.base);
      return;
    }

    // Android/iOS cold start.
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _open(navigatorKey, initial);

    // Android: links arriving while the app runs.
    _appLinks.uriLinkStream.listen((uri) => _open(navigatorKey, uri));
  }

  void _open(GlobalKey<NavigatorState> navigatorKey, Uri uri) {
    final parsed = parse(uri);
    if (parsed == null) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    // Give the app one frame to build before opening the sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PostInteractionPanel.show(
        navigatorKey.currentContext ?? ctx,
        parsed.postId,
        initialTab: 1,
        initialCommentId: parsed.commentId,
      );
    });
  }

  /// Pull `postId` + `commentId` out of a link. Returns null for anything else.
  static LinkTarget? parse(Uri uri) {
    var path = uri.path;
    // Web builds may carry the path in the fragment instead (hash fallback).
    if ((path.isEmpty || path == '/') && uri.fragment.startsWith('/')) {
      path = uri.fragment;
    }
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    final i = segs.indexOf('comment');
    if (i <= 0 || i + 1 >= segs.length) return null;
    if (i < 2) return null;
    if (segs[i - 2] != 'post' && segs[i - 2] != 'scroll') return null;

    final commentId = segs[i + 1];
    final dash = commentId.lastIndexOf('-');
    if (dash <= 0) return null;
    final postId = commentId.substring(0, dash);
    return LinkTarget(postId: postId, commentId: commentId);
  }
}

class LinkTarget {
  final String postId;
  final String commentId;
  const LinkTarget({required this.postId, required this.commentId});
}
