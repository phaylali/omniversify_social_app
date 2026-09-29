/// Prestige band a rank belongs to. Each band owns one folder of insignias
/// under `assets/achievements/`.
enum RankTier {
  bronze('Bronze', 'Bronze'),
  silver('Silver', 'Silver'),
  gold('Gold', 'Gold'),
  black('Black', 'Black');

  const RankTier(this.label, this.folder);

  /// Human readable name shown next to the level.
  final String label;

  /// Asset folder name, matching the directory on disk exactly.
  final String folder;
}

/// Player rank: a level from 1 to 69 mapped onto a [RankTier] and an
/// insignia asset.
///
/// There is no rank 0 — everyone starts at [minLevel]. The level curve is
/// geometric — each rank costs 1.2x the previous one (57, 69, 83, 99, 119
/// ...) — but the table itself is hardcoded in [gaps] so the last rank
/// lands on exactly 69,420,767 XP. Nothing resets at a tier border:
/// [RankTier] is only a cosmetic band, the cost keeps compounding straight
/// through Bronze → Silver → Gold → Black.
class Rank {
  Rank._(this.level, this.tier);

  /// First rank — what a brand new player holds with 0 XP.
  static const int minLevel = 1;

  /// Highest attainable level — the last insignia of the black band.
  /// There are exactly `maxLevel` ranks in the game.
  static const int maxLevel = 69;

  /// Multiplier the hardcoded [gaps] table follows, from one rank to the
  /// next. Kept as a named constant so the shape of the curve is visible
  /// even though the numbers themselves are frozen.
  static const double levelFactor = 1.2;

  /// First level of the silver band. Bands are 20 levels wide until black.
  static const int _silverAt = 20;
  static const int _goldAt = 40;
  static const int _blackAt = 60;

  /// XP needed to advance out of each rank, indexed from [minLevel]:
  /// [gaps][0] is the cost of leaving rank 1, [gaps][67] the cost of
  /// leaving rank 68.
  ///
  /// Generated as `57.3055 * 1.2^n` rounded to whole XP, which puts the
  /// running total for [maxLevel] on exactly 69,420,767. The last entry
  /// belongs to the final rank and can never be completed.
  static const List<int> gaps = <int>[
    57, 69, 83, 99, 119, 143, 171, 205, 246, 296, //
    355, 426, 511, 613, 736, 883, 1059, 1271, 1526, 1831, //
    2197, 2636, 3164, 3796, 4556, 5467, 6560, 7872, 9447, 11336, //
    13603, 16324, 19588, 23506, 28207, 33849, 40618, 48742, 58490,
    70188, //
    84226, 101071, 121285, 145543, 174651, 209581, 251498, 301797,
    362156, //
    434588, 521505, 625806, 750968, 901161, 1081393, 1297672, 1557207,
    1868648, 2242378, //
    2690853, 3229024, 3874828, 4649794, 5579753, 6695703, 8034844,
    9641813, //
    11570176, 13884211,
  ];

  /// Cumulative XP required to reach each rank: [totals] for [minLevel] is
  /// 0 (you start there), and the last one is the whole game.
  static final List<int> totals = List<int>.generate(maxLevel + 1, (level) {
    var sum = 0;
    for (var i = minLevel; i < level; i++) {
      sum += gapForLevel(i);
    }
    return sum;
  });

  /// Every rank in the game, lowest first — what the Ranks page lists.
  static final List<Rank> all = List<Rank>.generate(
    maxLevel - minLevel + 1,
    (index) => Rank.fromLevel(minLevel + index),
  );

  /// Total XP needed to finish the game: reach [maxLevel].
  static int get finalTotal => totals[maxLevel];

  /// Zero-based level, clamped to [minLevel]..[maxLevel].
  final int level;

  /// Prestige band derived from [level].
  final RankTier tier;

  /// Builds the rank for an explicit level (out-of-range values clamp).
  factory Rank.fromLevel(int level) {
    final clamped = level.clamp(minLevel, maxLevel);
    return Rank._(clamped, _tierForLevel(clamped));
  }

  /// Builds the rank earned by a total XP amount.
  factory Rank.fromXp(int xp) => Rank.fromLevel(levelForXp(xp));

  static RankTier _tierForLevel(int level) {
    if (level >= _blackAt) return RankTier.black;
    if (level >= _goldAt) return RankTier.gold;
    if (level >= _silverAt) return RankTier.silver;
    return RankTier.bronze;
  }

  /// XP needed to advance out of [level] — 57, 69, 83, 99 ... taken from
  /// [gaps] so the bar never shows a value that disagrees with the table.
  static int gapForLevel(int level) =>
      gaps[level.clamp(minLevel, maxLevel) - 1];

  /// Total XP required to *reach* [level] from zero.
  static int xpForLevel(int level) => totals[level.clamp(minLevel, maxLevel)];

  /// Highest rank whose threshold is still at or below [xp].
  static int levelForXp(int xp) {
    if (xp <= 0) return minLevel;
    var level = minLevel;
    while (level < maxLevel) {
      if (totals[level + 1] > xp) break;
      level++;
    }
    return level;
  }

  /// Zero-based XP earned inside the current level.
  int progressIn(int xp) =>
      (xp - xpForLevel(level)).clamp(0, gapForLevel(level));

  /// Fraction of the current level completed, from 0 to 1.
  double progressFraction(int xp) {
    final gap = gapForLevel(level);
    if (gap <= 0) return 0;
    return progressIn(xp) / gap;
  }

  /// Path of the insignia for this rank, e.g.
  /// `assets/achievements/Silver/rank023.png`.
  String get assetPath =>
      'assets/achievements/${tier.folder}/rank${level.toString().padLeft(3, '0')}.png';

  /// Placeholder for someone whose real XP we don't have yet.
  ///
  /// Hashes the handle so the same person always shows the same rank,
  /// spread across every tier instead of reshuffling on each launch.
  static int placeholderXpFor(String handle) {
    var hash = 0;
    for (final code in handle.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    final level =
        minLevel + hash % (maxLevel - minLevel + 1);
    final gap = gapForLevel(level);
    return xpForLevel(level) + (hash ~/ 7) % gap;
  }
}
