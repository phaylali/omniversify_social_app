import 'package:flutter/material.dart';
import '../models/rank.dart';
import '../screens/ranks_screen.dart';
import '../services/xp_service.dart';

/// Insignia image for a [Rank].
///
/// Falls back to a shield icon if the asset is missing, so a renamed asset
/// folder degrades to a placeholder instead of a red error box.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank, this.size = 32});

  final Rank rank;

  /// Edge length of the square insignia (source art is 64×64).
  final double size;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Image.asset(
      rank.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          Icon(Icons.military_tech_outlined, size: size, color: gold),
    );
  }
}

/// Level, tier and progress bar shown under a profile avatar.
///
/// Pass [xp] to render someone else's (currently placeholder) progression.
/// Leave it out to follow [XpService] live, which is how the signed-in
/// player's own bar stays in sync the instant XP changes.
///
/// Pass [handle] too and a tap on the bar opens the Ranks page with that
/// account's rank tagged by its `@handle`.
class XpBar extends StatelessWidget {
  const XpBar({super.key, this.xp, this.handle});

  /// Total XP to display. `null` means "listen to the signed-in player".
  final int? xp;

  /// Handle of the profile this bar belongs to, for the Ranks page tag.
  final String? handle;

  @override
  Widget build(BuildContext context) {
    if (xp != null) return _bar(context, xp!);
    return ValueListenableBuilder<int>(
      valueListenable: XpService.instance.xp,
      builder: (context, total, _) => _bar(context, total),
    );
  }

  Widget _bar(BuildContext context, int totalXp) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final rank = Rank.fromXp(totalXp);
    final needed = Rank.gapForLevel(rank.level);
    final earned = rank.progressIn(totalXp);
    final fraction = rank.progressFraction(totalXp);
    final atMax = rank.level == Rank.maxLevel;

    // Tapping the bar opens the full ladder with this profile's rank
    // framed in the list.
    return Material(
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: gold.withAlpha(60), width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RanksScreen(
              highlightLevel: rank.level,
              highlightHandle: handle,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              RankBadge(rank: rank, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'LEVEL ${rank.level}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          rank.tier.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: cs.onSurface.withAlpha(140),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          atMax ? 'MAX RANK' : '$earned / $needed XP',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        // Top rank is the end of the road: always full.
                        value: atMax ? 1.0 : fraction.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: cs.onSurface.withAlpha(25),
                        color: gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: gold.withAlpha(140)),
            ],
          ),
        ),
      ),
    );
  }
}
