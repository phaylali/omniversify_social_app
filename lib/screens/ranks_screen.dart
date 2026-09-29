import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omniversify_widget/omniversify_widget.dart';

import '../models/rank.dart';
import '../services/xp_service.dart';
import '../widgets/xp_bar.dart';
import 'tasks_screen.dart';

/// The whole ladder of ranks: all 69 of them, what each one costs and the
/// running total it takes to get there.
///
/// Tapping the XP bar on any profile opens this page with that profile's
/// rank framed in gold, scrolled into view and tagged with their handle.
class RanksScreen extends StatefulWidget {
  const RanksScreen({
    super.key,
    required this.highlightLevel,
    this.highlightHandle,
  });

  /// Level of the profile the page was opened from.
  final int highlightLevel;

  /// Handle of that same profile, shown as an `@mention` on the row.
  /// `null` when the page was opened from the player's own profile.
  final String? highlightHandle;

  @override
  State<RanksScreen> createState() => _RanksScreenState();
}

class _RanksScreenState extends State<RanksScreen> {
  /// Fixed row height so the list can compute the offset of any rank.
  static const double _rowHeight = 74;

  /// Top padding of the list — added to every row offset when scrolling.
  static const double _topGap = 4;

  static final NumberFormat _fmt = NumberFormat.decimalPattern('en_US');

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open the list sitting on the profile's rank instead of at rank 1.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptScroll());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// How many frames we're willing to wait for the list to report a real
  /// scrollable extent — a restored activity lays the route out late.
  int _attempts = 0;

  /// Row index of the highlighted rank (the list starts at [Rank.minLevel]).
  int get _highlightIndex =>
      widget.highlightLevel.clamp(Rank.minLevel, Rank.maxLevel) -
      Rank.minLevel;

  void _attemptScroll() {
    if (!mounted) return;
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) {
      if (_attempts++ < 10) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _attemptScroll());
      }
      return;
    }
    final position = _scroll.position;
    final rowTop = _topGap + _highlightIndex * _rowHeight;
    final target = rowTop - (position.viewportDimension - _rowHeight) / 2;
    final clamped =
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((clamped - position.pixels).abs() < 1) return;
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final highlight = widget.highlightLevel.clamp(Rank.minLevel, Rank.maxLevel);
    final mine = Rank.fromXp(XpService.instance.totalXp).level;

    return Scaffold(
      appBar: OmniversifyAppBar(
        title: 'Ranks',
        showBackButton: true,
        onBackPressed: () => Navigator.of(context).pop(),
        actions: [
          // The ladder explains the rules — Tasks shows the other half:
          // what the player still has to do, and how XP gets earned.
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
            ),
            icon: Icon(Icons.checklist_rounded, size: 18, color: gold),
            label: Text(
              'Tasks',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, _topGap, 16, 24),
              itemExtent: _rowHeight,
              itemCount: Rank.all.length,
              itemBuilder: (context, index) {
                final rank = Rank.all[index];
                return _row(
                  context,
                  rank,
                  highlighted: rank.level == highlight,
                  mine: rank.level == mine,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Column captions sitting above the list: what the two right-hand
  /// numbers on every row mean.
  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    const caption = TextStyle(
      fontSize: 9,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${Rank.all.length} RANKS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: gold,
                ),
              ),
              const Spacer(),
              Text(
                '${_fmt.format(Rank.finalTotal)} XP TO THE LAST',
                style: caption.copyWith(color: cs.onSurface.withAlpha(160)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 50),
              Text(
                'RANK',
                style: caption.copyWith(color: cs.onSurface.withAlpha(140)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL TO REACH',
                    style: caption.copyWith(color: cs.onSurface.withAlpha(140)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'WHAT IT COSTS',
                    style: caption.copyWith(color: cs.onSurface.withAlpha(140)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: gold.withAlpha(60)),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Rank rank, {
    required bool highlighted,
    required bool mine,
  }) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final total = Rank.xpForLevel(rank.level);
    final gap = Rank.gapForLevel(rank.level);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: highlighted
          ? BoxDecoration(
              color: gold.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gold.withAlpha(170), width: 1.2),
            )
          : null,
      child: Row(
        children: [
          RankBadge(rank: rank, size: 38),
          const SizedBox(width: 12),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: highlighted ? gold : cs.onSurface,
                      ),
                    ),
                    if (highlighted || mine) ...[
                      const SizedBox(width: 8),
                      _tag(
                        context,
                        label: highlighted
                            ? (mine
                                ? 'YOU'
                                : widget.highlightHandle ?? 'THAT PERSON')
                            : 'YOU',
                        dim: !highlighted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rank.tier.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: cs.onSurface.withAlpha(140),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_fmt.format(total)} XP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? gold : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                // The last rank has no next step — it's the end of the ladder.
                rank.level == Rank.maxLevel
                    ? 'MAX'
                    : '+${_fmt.format(gap)}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withAlpha(140),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, {required String label, required bool dim}) {
    final gold = Theme.of(context).colorScheme.primary;
    final color = gold.withAlpha(dim ? 110 : 200);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}
