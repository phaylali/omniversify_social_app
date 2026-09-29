import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omniversify_widget/omniversify_widget.dart';
import '../core/config/api_config.dart';
import '../data/dummy_data.dart';
import '../data/post_state.dart';
import '../models/post.dart';
import '../services/interests_service.dart';
import '../services/mute_service.dart';
import '../services/relationship_service.dart';
import '../widgets/action_sheet.dart';
import '../widgets/video_player.dart';
import '../widgets/app_logo.dart';
import '../widgets/share_sheet.dart';
import '../widgets/post_interaction_panel.dart';

/// The four tabs above the scrolls: everything, new creators, topic-filtered,
/// and the people the user keeps up with.
enum _ScrollsTab { feed, discover, interests, keepUp }

class ScrollsScreen extends ConsumerStatefulWidget {
  const ScrollsScreen({super.key});

  @override
  ConsumerState<ScrollsScreen> createState() => _ScrollsScreenState();
}

class _ScrollsScreenState extends ConsumerState<ScrollsScreen> with TickerProviderStateMixin {
  late AnimationController _arrowController;
  late Animation<Offset> _arrowAnimation;
  bool _showArrow = true;
  int _currentIndex = 0;
  _ScrollsTab _tab = _ScrollsTab.feed;

  /// Keys for each tab label so the sliding underline can measure it.
  final Map<_ScrollsTab, GlobalKey> _tabKeys = {
    for (final tab in _ScrollsTab.values) tab: GlobalKey(),
  };
  final GlobalKey _tabsStackKey = GlobalKey();

  /// Underline geometry, in the tab-stack's coordinate space.
  double? _indicatorLeft;
  double? _indicatorWidth;

  /// Brief dark veil flashed over the content when the tab changes.
  late final AnimationController _tabVeil;

  /// Every hashtag across the feed — candidate list for the interests picker.
  static final Set<String> _candidateTopics = {
    for (final scroll in dummyScrolls) ..._hashtags(scroll.caption),
  };

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _arrowAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _arrowController, curve: Curves.easeOut));

    _arrowController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _showArrow) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _showArrow) _arrowController.reverse(from: 0.0);
        });
      }
      if (status == AnimationStatus.dismissed && _showArrow) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _showArrow) _arrowController.forward();
        });
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _arrowController.forward();
    });

    _tabVeil = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    // Refilter when follows or chosen interests change.
    RelationshipService.instance.following.addListener(_onFeedChanged);
    InterestsService.instance.topics.addListener(_onFeedChanged);
    // Mutes can happen from a post's menu too — keep every tab in sync.
    MuteService.instance.muted.addListener(_onFeedChanged);
  }

  @override
  void dispose() {
    RelationshipService.instance.following.removeListener(_onFeedChanged);
    InterestsService.instance.topics.removeListener(_onFeedChanged);
    MuteService.instance.muted.removeListener(_onFeedChanged);
    _arrowController.dispose();
    _tabVeil.dispose();
    super.dispose();
  }

  /// Runs the transition veil: the content swap lands behind an opaque frame
  /// that then fades away, so tab switches read as a deliberate cut.
  void _runTabSwitch() {
    _tabVeil.value = 1;
    _tabVeil.animateTo(0, curve: Curves.easeOutCubic);
  }

  /// Measures the selected label and parks the underline beneath it — the
  /// [AnimatedPositioned] in [_tabsBar] does the actual gliding.
  void _syncIndicator() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final labelContext = _tabKeys[_tab]?.currentContext;
      final stackContext = _tabsStackKey.currentContext;
      if (labelContext == null || stackContext == null) return;
      final label = labelContext.findRenderObject();
      final stack = stackContext.findRenderObject();
      if (label is! RenderBox || stack is! RenderBox) return;
      if (!label.attached || !stack.attached) return;
      final topLeft = label.localToGlobal(Offset.zero, ancestor: stack);
      if (_indicatorLeft != null &&
          _indicatorWidth != null &&
          (_indicatorLeft! - topLeft.dx).abs() < 0.5 &&
          (_indicatorWidth! - label.size.width).abs() < 0.5) {
        return; // Already in place — don't spin another frame.
      }
      setState(() {
        _indicatorLeft = topLeft.dx;
        _indicatorWidth = label.size.width;
      });
    });
  }

  void _onFeedChanged() {
    if (!mounted) return;
    setState(() {
      // Only the filtered tabs can shrink; never jump the feed's playback.
      if (_tab != _ScrollsTab.feed) _currentIndex = 0;
    });
  }

  void _onPageChanged(int index) {
    if (_showArrow) {
      setState(() => _showArrow = false);
      _arrowController.stop();
    }
    setState(() => _currentIndex = index);
  }

  /// Lowercase hashtags in a caption, without the `#`.
  static Set<String> _hashtags(String caption) {
    return {
      for (final m in RegExp(r'#(\w+)').allMatches(caption)) m.group(1)!.toLowerCase(),
    };
  }

  /// Authors muted this session — their scrolls disappear from every tab.
  /// Shared with the feed, so muting from a post's menu hides them here too.
  Set<String> get _muted => MuteService.instance.muted.value;

  /// The scrolls for the active tab — full feed, new creators, topic match,
  /// or follows, minus anyone muted this session.
  List<ScrollItem> get _items {
    final visible = _tabItems;
    if (_muted.isEmpty) return visible;
    return [
      for (final scroll in visible)
        if (!_muted.contains(scroll.username)) scroll,
    ];
  }

  /// The active tab's own filter, before anything is muted.
  List<ScrollItem> get _tabItems {
    switch (_tab) {
      case _ScrollsTab.discover:
        final following = RelationshipService.instance.following.value;
        // Nobody kept up with yet = everything is new to them.
        if (following.isEmpty) return dummyScrolls;
        return [
          for (final scroll in dummyScrolls)
            if (!following.contains(scroll.username)) scroll,
        ];
      case _ScrollsTab.interests:
        final topics = InterestsService.instance.topics.value;
        if (topics.isEmpty) return const [];
        return [
          for (final scroll in dummyScrolls)
            if (_hashtags(scroll.caption).any(topics.contains)) scroll,
        ];
      case _ScrollsTab.keepUp:
        final following = RelationshipService.instance.following.value;
        if (following.isEmpty) return const [];
        return [
          for (final scroll in dummyScrolls)
            if (following.contains(scroll.username)) scroll,
        ];
      case _ScrollsTab.feed:
        return dummyScrolls;
    }
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final postStates = ref.watch(postStateProvider);
    final items = _items;
    var current = _currentIndex;
    if (current >= items.length) current = items.isEmpty ? 0 : items.length - 1;

    _syncIndicator();

    return Stack(
      children: [
        if (items.isEmpty)
          _emptyState(context)
        else
          PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: items.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final item = items[index];
              final isActive = index == current;
              final state = postStates[item.id];
              final canShare = item.visibility == PostVisibility.public;

              return Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video or image background
                    if (item.videoUrl != null)
                      ScrollVideoPlayer(url: item.videoUrl!, isActive: isActive)
                    else
                      Image.network(
                        item.imageUrl ?? '',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              color: gold.withAlpha(120),
                              strokeWidth: 2,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: AppLogo(size: 80, fit: BoxFit.contain),
                        ),
                      ),

                    // Gradient overlay for readability
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      height: 280,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withAlpha(180)],
                          ),
                        ),
                      ),
                    ),

                    // Right side action buttons
                    Positioned(
                      right: 12,
                      bottom: 120,
                      child: Column(
                        children: [
                          _actionButton(context, Icons.add_circle_outline, 'Create'),
                          const SizedBox(height: 20),
                          _actionButton(
                            context,
                            state?.liked == true ? Icons.favorite : Icons.favorite_border,
                            _formatCount(state?.likes ?? item.likes),
                            color: state?.liked == true ? gold : Colors.white,
                            onPressed: () => ref.read(postStateProvider.notifier).toggleLike(item.id),
                          ),
                          const SizedBox(height: 20),
                          _actionButton(context, Icons.chat_bubble_outline,
                              _formatCount(state?.comments ?? item.comments),
                              onPressed: () => PostInteractionPanel.show(context, item.id, initialTab: 1)),
                          const SizedBox(height: 20),
                          // Private scrolls never open the share sheet.
                          canShare
                              ? _actionButton(context, Icons.share_outlined, 'Share',
                                  onPressed: () => ShareSheet.show(
                                        context,
                                        shareText:
                                            '${item.caption}\n${ApiConfig.omniversifyAppUrl}/scroll/$index',
                                        onShared: () => ref.read(postStateProvider.notifier).share(item.id),
                                      ))
                              : _actionButton(context, Icons.lock_outline, 'Private',
                                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Sharing is off for private scrolls'),
                                          duration: Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      )),
                          const SizedBox(height: 20),
                          _actionButton(context, Icons.bookmark_border, 'Save'),
                          const SizedBox(height: 20),
                          _actionButton(context, Icons.more_horiz, 'Menu',
                              onPressed: () => _showScrollMenu(context, item)),
                        ],
                      ),
                    ),

                    // Bottom user info
                    Positioned(
                      left: 16,
                      bottom: 16,
                      right: 70,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: gold.withAlpha(40),
                                child: Text(
                                  item.username[1].toUpperCase(),
                                  style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.username,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              ValueListenableBuilder<Set<String>>(
                                valueListenable: RelationshipService.instance.following,
                                builder: (context, following, _) {
                                  final isFollowing = following.contains(item.username);
                                  return GestureDetector(
                                    onTap: () => RelationshipService.instance.toggleFollow(item.username),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isFollowing ? gold.withAlpha(45) : Colors.transparent,
                                        border: Border.all(
                                          color: isFollowing ? gold : Colors.white.withAlpha(100),
                                          width: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isFollowing ? 'Keeping up' : 'Keep up',
                                        style: TextStyle(
                                          color: isFollowing ? gold : Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Privacy indicator on the scroll itself.
                              if (item.visibility == PostVisibility.private) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(120),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline, color: Colors.white70, size: 12),
                                      SizedBox(width: 4),
                                      Text('Private',
                                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.caption,
                            style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Video indicator
                    if (item.videoUrl != null)
                      Positioned(
                        // Below the tab row now — same dark zone, no overlap.
                        top: MediaQuery.of(context).padding.top + 64,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(120),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam, color: Colors.white70, size: 14),
                              SizedBox(width: 4),
                              Text('VIDEO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

        // Tab-switch veil: the new content lands behind this and it fades
        // away, giving every tab change a clean transition.
        IgnorePointer(
          child: FadeTransition(
            opacity: _tabVeil,
            child: Container(color: Colors.black),
          ),
        ),

        // Dark scrim from the top — same treatment as the caption gradient,
        // mirrored, so the tab names always sit on a readable backdrop.
        Positioned(
          left: 0, right: 0, top: 0,
          height: MediaQuery.of(context).padding.top + 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withAlpha(180), Colors.transparent],
              ),
            ),
          ),
        ),

        // Feed / Discover / Interests / Keep up
        _tabsBar(gold),

        // Animated scroll indicator
        if (_showArrow && items.isNotEmpty)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _arrowAnimation,
              child: FadeTransition(
                opacity: _arrowController,
                child: const Center(
                  child: Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 28),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Tabs ────────────────────────────────────────────────────
  Widget _tabsBar(Color gold) {
    const tabs = [
      _ScrollsTab.feed,
      _ScrollsTab.discover,
      _ScrollsTab.interests,
      _ScrollsTab.keepUp,
    ];
    return Positioned(
      // Flush with the bottom of the cutout/status-bar inset — as close to the
      // top as the touch target can safely go.
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: Center(
        // Scales down instead of overflowing on narrow screens.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Stack(
            key: _tabsStackKey,
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _tabButton(context, tabs[i], gold),
                  ],
                ],
              ),
              // The active tab's underline — glides between the labels.
              if (_indicatorLeft != null && _indicatorWidth != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: _indicatorLeft!,
                  width: _indicatorWidth!,
                  bottom: 2,
                  height: 2.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(BuildContext context, _ScrollsTab tab, Color gold) {
    final selected = _tab == tab;
    final label = switch (tab) {
      _ScrollsTab.feed => 'Feed',
      _ScrollsTab.discover => 'Discover',
      _ScrollsTab.interests => 'Interests',
      _ScrollsTab.keepUp => 'Keep up',
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_tab == tab) return;
        setState(() {
          _tab = tab;
          _currentIndex = 0;
        });
        _runTabSwitch();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          key: _tabKeys[tab],
          style: TextStyle(
            color: selected ? gold : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            // Keeps plain text legible over bright video frames — wide blur
            // so it reads as a soft glow, never a hard outline.
            shadows: const [
              Shadow(color: Color(0x70000000), blurRadius: 12, offset: Offset(0, 1.5)),
              Shadow(color: Color(0x40000000), blurRadius: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty tabs ──────────────────────────────────────────────
  /// Placeholder for a filtered tab with nothing to show yet.
  Widget _emptyState(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    // The tab still has scrolls, but muting hid all of them — offer an undo.
    if (_muted.isNotEmpty && _tabItems.isNotEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_off_outlined, size: 44, color: gold),
            const SizedBox(height: 14),
            const Text(
              'Everyone here is muted',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'You muted every account that posted in this tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13),
            ),
            const SizedBox(height: 18),
            OmniFilledButton(
              label: 'Unmute everyone',
              icon: Icons.volume_up_outlined,
              fullWidth: false,
              onPressed: () => MuteService.instance.unmuteAll(),
            ),
          ],
        ),
      );
    }

    final keepUpTab = _tab == _ScrollsTab.keepUp;
    final hasTopics = InterestsService.instance.topics.value.isNotEmpty;

    final IconData icon;
    final String title;
    final String message;
    final String actionLabel;
    final VoidCallback onAction;

    if (keepUpTab) {
      final followingCount = RelationshipService.instance.following.value.length;
      if (followingCount == 0) {
        icon = Icons.person_add_outlined;
        title = 'Not keeping up with anyone yet';
        message = 'Keep up with people from their profile and their scrolls show up here.';
      } else {
        // They follow someone, but nobody they follow has posted a scroll.
        icon = Icons.person_search_outlined;
        title = 'No scrolls from them yet';
        message = followingCount == 1
            ? 'The account you keep up with hasn\'t posted a scroll yet.'
            : 'The accounts you keep up with haven\'t posted a scroll yet.';
      }
      actionLabel = 'Browse the feed';
      onAction = () {
        setState(() => _tab = _ScrollsTab.feed);
        _runTabSwitch();
      };
    } else if (_tab == _ScrollsTab.discover) {
      // Only reachable once they keep up with every scroll author.
      icon = Icons.explore_outlined;
      title = 'No new creators';
      message = 'You already keep up with everyone who posted a scroll.';
      actionLabel = 'Browse the feed';
      onAction = () {
        setState(() => _tab = _ScrollsTab.feed);
        _runTabSwitch();
      };
    } else if (hasTopics) {
      icon = Icons.interests;
      title = 'No scrolls match your interests';
      message = 'None of the scrolls right now match your topics.';
      actionLabel = 'Edit interests';
      onAction = _openInterestsPicker;
    } else {
      icon = Icons.interests;
      title = 'Choose what interests you';
      message = 'Pick the topics you care about and this tab shows only scrolls about them.';
      actionLabel = 'Choose interests';
      onAction = _openInterestsPicker;
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: gold),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13),
          ),
          const SizedBox(height: 18),
          OmniFilledButton(
            label: actionLabel,
            icon: keepUpTab ? Icons.explore_outlined : Icons.tune,
            fullWidth: false,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }

  /// Lightweight stand-in for the interests setup wizard (arrives later).
  Future<void> _openInterestsPicker() async {
    var selected = {...InterestsService.instance.topics.value};
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Your interests'),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in _candidateTopics.toList()..sort())
                  FilterChip(
                    label: Text('#$topic'),
                    selected: selected.contains(topic),
                    onSelected: (value) => setDialogState(() {
                      if (value) {
                        selected.add(topic);
                      } else {
                        selected.remove(topic);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await InterestsService.instance.setTopics(selected);
    }
  }

  /// The scroll menu: report the account, report the scroll, or mute them.
  ///
  /// It shares its sheet with the post menu, so both look and behave alike;
  /// the confirmation lands on the feed itself.
  void _showScrollMenu(BuildContext context, ScrollItem item) {
    showActionSheet(
      context,
      title: item.username,
      items: [
        ActionSheetItem(
          icon: Icons.flag_outlined,
          title: 'Report user',
          subtitle: 'Tell us about ${item.username}',
          onTap: () => _confirm(
            'Thanks — your report about ${item.username} is in review',
          ),
        ),
        ActionSheetItem(
          icon: Icons.report_outlined,
          title: 'Report content',
          subtitle: 'Tell us about this scroll',
          onTap: () =>
              _confirm('Thanks — your report about this scroll is in review'),
        ),
        ActionSheetItem(
          icon: Icons.volume_off_outlined,
          title: 'Mute',
          subtitle: 'Hide ${item.username}\'s scrolls for now',
          onTap: () => _mute(item.username),
        ),
      ],
    );
  }

  /// Mutes an author until the app restarts — undoable from the snackbar.
  /// The feed, the stories row and every tab refilter themselves off the
  /// shared [MuteService], so no manual setState is needed here.
  void _mute(String handle) {
    MuteService.instance.mute(handle);
    showActionNotice(
      context,
      '$handle muted',
      undoLabel: 'UNDO',
      onUndo: () => MuteService.instance.unmute(handle),
    );
  }

  void _confirm(String message) => showActionNotice(context, message);

  Widget _actionButton(BuildContext context, IconData icon, String label,
      {VoidCallback? onPressed, Color color = Colors.white}) {
    final child = Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11)),
      ],
    );
    if (onPressed == null) return child;
    return GestureDetector(onTap: onPressed, child: child);
  }
}
