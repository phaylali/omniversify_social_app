import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reset.dart';

/// How much of each action a daily task asks for.
abstract final class DailyGoals {
  /// Posts published since the last reset.
  static const int posts = 3;

  /// Comments left on a post or a scroll.
  static const int comments = 5;

  /// Posts liked.
  static const int likes = 10;

  /// Posts shared off-platform.
  static const int shares = 2;
}

/// How far today's actionable tasks have got.
///
/// Counts are the player's own and live in [SharedPreferences] under the UTC
/// day they belong to, so they roll over at [DailyReset.label] exactly when
/// the countdown on the Tasks page reaches zero — and only they do: XP, rank
/// and the Keep-up total are never touched by a reset.
///
/// They are counts, never XP: liking and unliking the same post all afternoon
/// would otherwise print money.
class DailyTasks {
  DailyTasks._();
  static final DailyTasks instance = DailyTasks._();

  static const String _kDay = 'daily_tasks_day_v1';
  static const String _kComments = 'daily_tasks_comments_v1';
  static const String _kLikes = 'daily_tasks_likes_v1';
  static const String _kShares = 'daily_tasks_shares_v1';

  /// Bumped whenever a counter moves or the day turns over, so everything
  /// showing them rebuilds off one listener.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String _day = '';
  int _comments = 0;
  int _likes = 0;
  int _shares = 0;
  bool _initialized = false;

  /// Comments left since the reset — reads [revision] to stay live.
  int get comments {
    _ensureToday();
    return _comments;
  }

  /// Posts liked since the reset.
  int get likes {
    _ensureToday();
    return _likes;
  }

  /// Posts shared since the reset.
  int get shares {
    _ensureToday();
    return _shares;
  }

  /// Loads today's counts, dropping yesterday's the moment UTC turns over.
  /// Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _day = prefs.getString(_kDay) ?? '';
    if (_day != DailyReset.stamp()) {
      _day = DailyReset.stamp();
      _comments = _likes = _shares = 0;
      await _persist(prefs);
    } else {
      _comments = prefs.getInt(_kComments) ?? 0;
      _likes = prefs.getInt(_kLikes) ?? 0;
      _shares = prefs.getInt(_kShares) ?? 0;
    }
    _initialized = true;
  }

  /// One more comment toward today's task.
  void recordComment() {
    _ensureToday();
    _comments += 1;
    _changed();
  }

  /// One more like toward today's task.
  void recordLike() {
    _ensureToday();
    _likes += 1;
    _changed();
  }

  /// One more share toward today's task.
  void recordShare() {
    _ensureToday();
    _shares += 1;
    _changed();
  }

  /// Zeroes the counters the instant the phone's clock crosses midnight UTC
  /// while the app is open — no restart needed to see a fresh day.
  void _ensureToday() {
    if (!_initialized) return;
    final today = DailyReset.stamp();
    if (_day == today) return;
    _day = today;
    _comments = _likes = _shares = 0;
    _changed();
  }

  void _changed() {
    revision.value += 1;
    SharedPreferences.getInstance().then(_persist);
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(_kDay, _day);
    await prefs.setInt(_kComments, _comments);
    await prefs.setInt(_kLikes, _likes);
    await prefs.setInt(_kShares, _shares);
  }
}
