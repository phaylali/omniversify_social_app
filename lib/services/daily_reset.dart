/// The clock every daily task runs on.
///
/// The reset is pinned to **midnight UTC**, not the phone's local midnight —
/// so a player in Casablanca and one in Tokyo watch the same countdown hit
/// zero at the same instant, and "today" means the same day for both.
abstract final class DailyReset {
  /// Midnight UTC of the day [now] falls on *in UTC*, i.e. the next reset.
  static DateTime nextUtcMidnight([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day + 1);
  }

  /// Time left until that reset — never negative, never 24h or more.
  static Duration remaining([DateTime? now]) {
    final moment = now ?? DateTime.now();
    return nextUtcMidnight(moment).difference(moment);
  }

  /// The UTC day key daily rewards are stamped with, as `2026-09-29`.
  static String stamp([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  /// `07:23:11` readout for the countdown card.
  static String format(Duration left) {
    final seconds = left.inSeconds.clamp(0, 86399);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(h)}:${pad(m)}:${pad(s)}';
  }

  /// The reset moment spelled out for captions: `00:00 UTC`.
  static String get label => '00:00 UTC';
}
