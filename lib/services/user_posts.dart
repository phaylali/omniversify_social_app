import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dummy_data.dart';
import '../models/post.dart';

/// Posts you have written yourself.
///
/// Kept apart from `dummyPosts` so the seeded feed never mutates: yours go in
/// front of it, and everything that already renders a `Post` — the feed,
/// Explore, your profile, likes and comments — keeps working unchanged.
///
/// One store, one `ValueNotifier`, mirrored into [SharedPreferences], the
/// same shape [MessagesService] uses for threads.
class UserPosts {
  UserPosts._();

  static final UserPosts instance = UserPosts._();

  static const String _kStore = 'user_posts_v1';

  /// Newest first, so the composer can prepend and the feed just reads.
  final ValueNotifier<List<Post>> posts = ValueNotifier(const []);

  bool _loaded = false;

  /// Reads the stored posts once. Safe to call repeatedly.
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStore);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as List<dynamic>;
        posts.value = [
          for (final item in data) _fromJson(item as Map<String, dynamic>),
        ];
      } catch (_) {
        // A store we cannot read is a store we start over from.
        posts.value = const [];
      }
    }
    _loaded = true;
  }

  /// Publishes [post] at the top of your history.
  Future<void> add(Post post) async {
    await init();
    posts.value = [post, ...posts.value];
    await _save();
  }

  /// Withdraws one — the `⋮` menu's delete, without touching the seeded feed.
  Future<void> remove(String id) async {
    await init();
    posts.value = [for (final p in posts.value) if (p.id != id) p];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStore,
      jsonEncode([for (final p in posts.value) _toJson(p)]),
    );
  }

  /// Empts everything and lets [init] read again — tests start clean.
  @visibleForTesting
  void reset() {
    posts.value = const [];
    _loaded = false;
  }

  // Only what the composer can actually produce travels through JSON; the
  // seeded metadata fields are not part of this store.
  static Map<String, dynamic> _toJson(Post p) => {
        'id': p.id,
        'type': p.type.name,
        'text': p.text,
        if (p.imageUrl != null) 'imageUrl': p.imageUrl,
        if (p.videoUrl != null) 'videoUrl': p.videoUrl,
        'timestamp': p.timestamp.toIso8601String(),
        'visibility': p.visibility.name,
      };

  static Post _fromJson(Map<String, dynamic> j) {
    final type = PostType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => PostType.text,
    );
    final visibility = PostVisibility.values.firstWhere(
      (v) => v.name == j['visibility'],
      orElse: () => PostVisibility.public,
    );
    return Post(
      id: j['id'] as String,
      user: currentUser,
      type: type,
      text: j['text'] as String? ?? '',
      imageUrl: j['imageUrl'] as String?,
      videoUrl: j['videoUrl'] as String?,
      timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
          DateTime.now(),
      visibility: visibility,
    );
  }
}
