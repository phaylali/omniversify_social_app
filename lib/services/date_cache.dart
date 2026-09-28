import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'date_service.dart';

/// SharedPreferences cache for the notifications-drawer dates column.
/// Paints immediately from disk, then the drawer refreshes from [DateService].
class DateCache {
  DateCache._();

  static const _key = 'notification_dates_cache_v1';

  /// Load the last saved triple date, or null on first run / corrupt data.
  static Future<TripleDate?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      return TripleDate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(TripleDate date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(date.toJson()));
    } catch (_) {}
  }

  /// True when both dates fall on the same calendar day (any calendar).
  static bool isSameDay(TripleDate a, TripleDate b) =>
      a.gregorian.year == b.gregorian.year &&
      a.gregorian.day == b.gregorian.day &&
      a.gregorian.month.order == b.gregorian.month.order;
}
