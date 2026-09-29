import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omniversify_widget/omniversify_widget.dart';

import '../models/rank.dart';
import '../services/daily_reset.dart';
import '../services/relationship_service.dart';
import '../services/xp_service.dart';

/// Which of the two tabs is showing: task progress or the XP rulebook.
enum _TasksTab { progress, guide }

/// One row on the progress tab — an action worth XP, how much of it the
/// player has done and how many points it pays.
class _Task {
  const _Task({
    required this.icon,
    required this.title,
    required this.detail,
    required this.xp,
    required this.done,
    required this.goal,
  });

  final IconData icon;
  final String title;
  final String detail;
  final int xp;
  final int done;
  final int goal;

  bool get complete => done >= goal;
  double get fraction => goal <= 0 ? 0 : (done / goal).clamp(0.0, 1.0);
}

/// The XP hub behind the Ranks page.
///
/// Tab one shows how far the daily/weekly tasks have got; tab two is the
/// guide that spells out exactly what pays XP and how the 69-rank curve
/// adds up to 69,420,767.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _TasksTab _tab = _TasksTab.progress;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: OmniversifyAppBar(
        title: 'Tasks',
        showBackButton: true,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          _tabBar(context, gold),
          Expanded(
            child: IndexedStack(
              index: _tab.index,
              children: const [
                _ProgressTab(),
                _GuideTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Plain bold labels with a gold underline on the active one — the same
  /// tab treatment the scrolls screen uses.
  Widget _tabBar(BuildContext context, Color gold) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (final tab in _TasksTab.values)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = tab),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Column(
                      children: [
                        Text(
                          tab == _TasksTab.progress ? 'Progress' : 'Guide',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: _tab == tab
                                ? gold
                                : cs.onSurface.withAlpha(140),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: _tab == tab ? gold : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: gold.withAlpha(60)),
      ],
    );
  }
}

// ─── Tab 1 · task progress ────────────────────────────────────

class _ProgressTab extends StatelessWidget {
  const _ProgressTab();

  static final NumberFormat _fmt = NumberFormat.decimalPattern('en_US');

  /// Daily login and keep-up count read live; the remaining counts are
  /// placeholders until action tracking lands.
  List<_Task> get _tasks {
    final following = RelationshipService.instance.following.value;
    return [
      _Task(
        icon: Icons.login_rounded,
        title: 'Daily login',
        detail: 'Open the app once a day',
        xp: XpActions.dailyLogin,
        done: XpService.instance.loggedInToday ? 1 : 0,
        goal: 1,
      ),
      _Task(
        icon: Icons.edit_outlined,
        title: 'Create a post',
        detail: 'Publish to the feed',
        xp: XpActions.createPost,
        done: 1,
        goal: 3,
      ),
      _Task(
        icon: Icons.chat_bubble_outline,
        title: 'Comment',
        detail: 'On a post or a scroll',
        xp: XpActions.comment,
        done: 2,
        goal: 5,
      ),
      _Task(
        icon: Icons.favorite_border,
        title: 'Like',
        detail: 'Like someone else\'s post',
        xp: XpActions.like,
        done: 7,
        goal: 10,
      ),
      _Task(
        icon: Icons.person_add_alt_1_outlined,
        title: 'Keep up',
        detail: 'Keep up with 3 new accounts',
        xp: XpActions.follow,
        done: following.length,
        goal: 3,
      ),
      _Task(
        icon: Icons.share_outlined,
        title: 'Share',
        detail: 'Share a post off-platform',
        xp: XpActions.share,
        done: 1,
        goal: 2,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final tasks = _tasks;
    final doneCount = tasks.where((t) => t.complete).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _summary(context, gold),
        const SizedBox(height: 10),
        const _CountdownCard(),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'TODAY\'S TASKS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withAlpha(150),
              ),
            ),
            const Spacer(),
            Text(
              '$doneCount / ${tasks.length} done',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final task in tasks) ...[
          _taskCard(context, task, gold),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        Text(
          'Daily login and Keep up update live — the other counts are placeholders until activity tracking ships.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: cs.onSurface.withAlpha(130),
          ),
        ),
      ],
    );
  }

  /// Where the player stands: rank, tier and the road to the next rank.
  Widget _summary(BuildContext context, Color gold) {
    final cs = Theme.of(context).colorScheme;
    final xpService = XpService.instance;
    final rank = xpService.rank;
    final total = xpService.totalXp;
    final fraction = rank.progressFraction(total);
    final isMax = rank.level >= Rank.maxLevel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gold.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LEVEL ${rank.level} · ${rank.tier.label.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: gold,
                  ),
                ),
              ),
              Text(
                '${_fmt.format(total)} XP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withAlpha(200),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isMax ? 1 : fraction,
              minHeight: 8,
              backgroundColor: gold.withAlpha(35),
              color: gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMax
                ? 'MAX RANK — the whole ladder is behind you'
                : '${_fmt.format(rank.progressIn(total))} / ${_fmt.format(Rank.gapForLevel(rank.level))} XP to level ${rank.level + 1}',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, _Task task, Color gold) {
    final cs = Theme.of(context).colorScheme;
    final complete = task.complete;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(
          cs.brightness == Brightness.dark ? 40 : 25,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: complete ? gold.withAlpha(120) : cs.outline.withAlpha(60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: gold.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  task.icon,
                  size: 17,
                  color: complete ? gold : cs.onSurface.withAlpha(170),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withAlpha(220),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.detail,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: gold.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+${task.xp} XP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: task.fraction,
                    minHeight: 6,
                    backgroundColor: gold.withAlpha(30),
                    color: complete ? gold : gold.withAlpha(170),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                complete ? 'DONE' : '${task.done}/${task.goal}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: complete ? gold : cs.onSurface.withAlpha(150),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tab 2 · the XP rulebook ──────────────────────────────────

class _GuideTab extends StatelessWidget {
  const _GuideTab();

  static final NumberFormat _fmt = NumberFormat.decimalPattern('en_US');

  /// What each action pays, in the order the player meets them.
  static const List<(IconData, String, int)> _actions = [
    (Icons.login_rounded, 'Daily login', XpActions.dailyLogin),
    (Icons.edit_outlined, 'Create a post', XpActions.createPost),
    (Icons.chat_bubble_outline, 'Comment', XpActions.comment),
    (Icons.favorite_border, 'Like', XpActions.like),
    (Icons.person_add_alt_1_outlined, 'Keep up', XpActions.follow),
    (Icons.share_outlined, 'Share', XpActions.share),
  ];

  /// First and last level of every band, read off the ladder itself so the
  /// guide can never disagree with the Ranks page.
  static List<(RankTier, int, int)> get _bands {
    return [
      for (final tier in RankTier.values)
        (
          tier,
          Rank.all.firstWhere((r) => r.tier == tier).level,
          Rank.all.lastWhere((r) => r.tier == tier).level,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    const caption = TextStyle(
      fontSize: 10,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w800,
    );

    final rules = <String>[
      'Everyone starts on rank 1 with 0 XP — there is no rank 0.',
      'There are ${Rank.maxLevel} ranks. Rank ${Rank.maxLevel} is the last one and can never be finished.',
      'Each rank costs ${Rank.levelFactor}× the one before it: 57, 69, 83, 99, 119 XP and so on.',
      'Bands are cosmetic — a tier change never resets what a rank costs.',
      '${_fmt.format(Rank.finalTotal)} XP in total reaches the last rank.',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          'HOW XP IS EARNED',
          style: caption.copyWith(color: cs.onSurface.withAlpha(150)),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withAlpha(60)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _actions.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 46, color: cs.outline.withAlpha(45)),
                ListTile(
                  dense: true,
                  leading: Icon(_actions[i].$1, color: gold, size: 19),
                  title: Text(
                    _actions[i].$2,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  trailing: Text(
                    '+${_actions[i].$3} XP',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: gold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'RANK RULES',
          style: caption.copyWith(color: cs.onSurface.withAlpha(150)),
        ),
        const SizedBox(height: 8),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle, size: 5, color: gold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rule,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: cs.onSurface.withAlpha(190),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'BANDS',
          style: caption.copyWith(color: cs.onSurface.withAlpha(150)),
        ),
        const SizedBox(height: 10),
        for (final (tier, first, last) in _bands) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.military_tech_outlined, size: 16, color: gold),
                const SizedBox(width: 8),
                Text(
                  tier.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withAlpha(210),
                  ),
                ),
                const Spacer(),
                Text(
                  'Rank $first – $last',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'MILESTONES',
          style: caption.copyWith(color: cs.onSurface.withAlpha(150)),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withAlpha(60)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _milestones.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 46, color: cs.outline.withAlpha(45)),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.flag_outlined,
                    color: gold,
                    size: 19,
                  ),
                  title: Text(
                    'Rank ${_milestones[i]}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  trailing: Text(
                    '${_fmt.format(Rank.xpForLevel(_milestones[i]))} XP',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: gold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Milestone totals count every rank below them, so they always match the Ranks page.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: cs.onSurface.withAlpha(130),
          ),
        ),
      ],
    );
  }

  /// The four landmark ranks: each band's first level plus the last one.
  static const List<int> _milestones = [20, 40, 60, Rank.maxLevel];
}

/// The live countdown to the daily reset, pinned to midnight UTC.
///
/// Ticks once a second on its own so the rest of the Tasks page never
/// rebuilds with it, and stops ticking when the tab is disposed.
class _CountdownCard extends StatefulWidget {
  const _CountdownCard();

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  late String _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _left = DailyReset.format(DailyReset.remaining());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = DailyReset.format(DailyReset.remaining());
      if (next != _left && mounted) {
        setState(() => _left = next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(
          cs.brightness == Brightness.dark ? 40 : 25,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAILY RESET IN',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tasks and the daily login roll over at ${DailyReset.label}',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _left,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: gold,
            ),
          ),
        ],
      ),
    );
  }
}
