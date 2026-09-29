import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Topics the user picked for the scrolls "Interests" tab.
///
/// The full setup wizard lands later — until then the tab filters on this
/// stored set, and an empty set falls back to the "choose interests" prompt.
class InterestsService {
  InterestsService._();

  static final InterestsService instance = InterestsService._();

  static const String _key = 'interest_topics_v1';

  /// Lowercase topic names (hashtags without the `#`).
  final ValueNotifier<Set<String>> topics = ValueNotifier(<String>{});

  bool _loaded = false;

  /// Loads persisted topics — call once before the first frame.
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    topics.value = (prefs.getStringList(_key) ?? const []).toSet();
    _loaded = true;
  }

  /// Replaces the picked topics and persists them.
  Future<void> setTopics(Set<String> next) async {
    topics.value = {...next};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next.toList());
  }
}
