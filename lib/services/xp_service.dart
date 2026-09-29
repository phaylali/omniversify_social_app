import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rank.dart';

/// XP granted by each action.
abstract final class XpActions {
  /// Granted once per calendar day when the app is opened.
  static const int dailyLogin = 10;

  /// Publishing a post to the feed.
  static const int createPost = 4;

  /// Leaving a comment on a post or a scroll.
  static const int comment = 2;

  /// Liking someone else's post.
  static const int like = 1;

  /// Keeping up with a new account.
  static const int follow = 5;

  /// Sharing a post off-platform.
  static const int share = 3;
}

/// Owns the signed-in player's XP total and rank progression.
///
/// XP lives in [SharedPreferences] so it survives relaunches; the total is
/// mirrored in a [ValueNotifier] so the profile XP bar rebuilds the moment
/// [addXp] fires without touching the widget tree by hand.
class XpService {
  XpService._();
  static final XpService instance = XpService._();

  static const String _kXp = 'xp_total_v1';
  static const String _kLastLogin = 'xp_last_login_day_v1';

  /// Live XP total. Listen to this instead of polling [totalXp].
  final ValueNotifier<int> xp = ValueNotifier<int>(0);

  bool _initialized = false;

  /// Whether today's daily login bonus has already been stamped.
  bool _loggedInToday = false;

  /// True once [recordDailyLogin] has granted today's bonus.
  bool get loggedInToday => _loggedInToday;

  /// Loads the stored total and stamps today's login bonus if it's due.
  /// Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    xp.value = prefs.getInt(_kXp) ?? 0;
    _initialized = true;
    await recordDailyLogin();
  }

  /// Current XP total.
  int get totalXp => xp.value;

  /// Rank earned by the current XP total.
  Rank get rank => Rank.fromXp(xp.value);

  /// Adds [amount] XP and persists the new total.
  ///
  /// Non-positive amounts are ignored, so a bad action table entry can never
  /// drain a player.
  Future<void> addXp(int amount, {String reason = ''}) async {
    if (amount <= 0) return;
    xp.value += amount;
    await _persist();
    debugPrint('XP +$amount ($reason) → total ${xp.value}');
  }

  /// Grants [XpActions.dailyLogin] the first time the app opens on a given
  /// calendar day. Repeat opens the same day award nothing.
  Future<void> recordDailyLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final stamp =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (prefs.getString(_kLastLogin) == stamp) {
      _loggedInToday = true;
      return;
    }
    await prefs.setString(_kLastLogin, stamp);
    _loggedInToday = true;
    await addXp(XpActions.dailyLogin, reason: 'daily login');
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kXp, xp.value);
  }
}
