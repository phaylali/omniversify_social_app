import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omniversify_widget/omniversify_widget.dart';
import 'core/config/api_config.dart';
import 'models/post.dart';
import 'data/dummy_data.dart';
import 'services/audio_player_service.dart';
import 'services/daily_tasks.dart';
import 'services/date_cache.dart';
import 'services/date_service.dart';
import 'services/deep_link_service.dart';
import 'services/interests_service.dart';
import 'services/mute_service.dart';
import 'services/open_file_service.dart';
import 'services/messages_service.dart';
import 'services/privacy_service.dart';
import 'services/relationship_service.dart';
import 'services/share_in_service.dart';
import 'services/weather_locations.dart';
import 'services/xp_service.dart';
import 'widgets/widgets.dart';
import 'screens/chat_screen.dart';
import 'screens/scrolls_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/settings_screen.dart';

/// Root navigator — deep links open the Comments panel through it.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (no # in shared comment links).
  usePathUrlStrategy();
  MediaKit.ensureInitialized();
  await ApiConfig.load();
  // XP total + today's login bonus, before the profile bar first paints.
  await XpService.instance.init();
  // Follows / friend requests + interest topics, before their tabs first paint.
  await RelationshipService.instance.init();
  await InterestsService.instance.init();
  // Who may see what you're reading or playing — before its tabs first paint.
  await PrivacyService.instance.load();
  // Starred places + the last ten weather visits, before that screen opens.
  await WeatherLocations.instance.load();
  // Today's task counters, so the Tasks page opens on the right day's counts.
  await DailyTasks.instance.init();
  // Start media session + load persisted player settings before first frame
  // so the Android notification is ready as soon as playback begins.
  final audio = AudioPlayerService.instance;
  await audio.init();
  await audio.connectAudioService();
  runApp(const ProviderScope(child: OmniversifySocialApp()));
  // Handle app/web links once the first frame is up.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    DeepLinkService.instance.init(rootNavigatorKey);
    // Books other apps open with us — "Open with Omniversify".
    OpenFileService.instance.init(rootNavigatorKey);
    // Captions and links other apps send us — "Share to Omniversify".
    ShareInService.instance.init();
  });
}

class OmniversifySocialApp extends ConsumerWidget {
  const OmniversifySocialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(catppuccinThemeProvider);
    final provider = ref.read(catppuccinThemeProvider.notifier);

    return MaterialApp(
      title: 'Omniversify Social',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: OmniversifyTheme.buildCatppuccin(
        palette: provider.flavor,
        accentColor: provider.accentColor,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _shareSheetOpen = false;

  @override
  void initState() {
    super.initState();
    // A caption or link another app sent us — the picker opens over
    // whatever tab is on screen at the time.
    ShareInService.instance.incoming.addListener(_showIncomingShare);
  }

  @override
  void dispose() {
    ShareInService.instance.incoming.removeListener(_showIncomingShare);
    super.dispose();
  }

  void _showIncomingShare() {
    final share = ShareInService.instance.incoming.value;
    if (share == null || !mounted || _shareSheetOpen) return;
    ShareInService.instance.consume();

    // A file with no words to go with it: say so instead of opening a sheet
    // with an empty preview.
    if (share.fileOnly) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'That was a file — send a link or a caption instead.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    _shareSheetOpen = true;
    ShareSheet.show(context, shareText: share.preview).whenComplete(() {
      _shareSheetOpen = false;
      // A second share while the first was still open waits here.
      if (mounted && ShareInService.instance.incoming.value != null) {
        _showIncomingShare();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isScrolls = _selectedIndex == 2;

    return Scaffold(
      appBar: isScrolls
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(OmniversifyConstants.appName, style: TextStyle(fontWeight: FontWeight.w700)),
              actions: [
                if (_selectedIndex == 0)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _showCreatePostDialog,
                  ),
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
              ],
            ),
      drawer: isScrolls
          ? null
          : const NotificationsDrawer(),
      endDrawer: isScrolls
          ? null
          : const DmsDrawer(),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.movie_filter_outlined), selectedIcon: Icon(Icons.movie_filter), label: 'Scrolls'),
          NavigationDestination(icon: Icon(Icons.widgets_outlined), selectedIcon: Icon(Icons.widgets), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  void _showCreatePostDialog() {
    final gold = Theme.of(context).colorScheme.primary;
    final types = <(String, IconData)>[
      ('Thought', Icons.chat_bubble_outline),
      ('Story', Icons.auto_awesome_outlined),
      ('Movie', Icons.movie_outlined),
      ('Series', Icons.tv_outlined),
      ('Song', Icons.music_note_outlined),
      ('Podcast', Icons.podcasts_outlined),
      ('Link', Icons.link_outlined),
      ('Activity', Icons.fitness_center_outlined),
      ('Location', Icons.location_on_outlined),
      ('Anime', Icons.animation_outlined),
      ('Book', Icons.menu_book_outlined),
      ('Game', Icons.sports_esports_outlined),
      ('Photo/Video', Icons.photo_library_outlined),
      ('File', Icons.attach_file_outlined),
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create post'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              for (final (label, icon) in types)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Creating a $label post'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gold.withAlpha(40), width: 0.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: gold, size: 26),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  List<Widget> get _pages => [
    const FeedScreen(),
    const ExploreScreen(),
    const ScrollsScreen(),
    const ToolsScreen(),
    const ProfileScreen(),
  ];
}

// ─── Feed Screen ──────────────────────────────────────────────
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Muted or blocked accounts drop out of the feed until they're restored.
    return ValueListenableBuilder<Set<String>>(
      valueListenable: MuteService.instance.muted,
      builder: (context, muted, _) {
        final posts = [
          for (final post in dummyPosts)
            if (!muted.contains(post.user.handle)) post,
        ];
        if (posts.isEmpty) return _everythingHidden(context);

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: posts.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return const StoriesRow();
            return _buildPost(posts[index - 1]);
          },
        );
      },
    );
  }
}

/// Feed empty state once every author got muted — the way back out.
Widget _everythingHidden(BuildContext context) {
  final gold = Theme.of(context).colorScheme.primary;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volume_off_outlined, size: 44, color: gold),
          const SizedBox(height: 14),
          const Text(
            'Everyone is hidden',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'You muted or blocked every account that posted.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
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
    ),
  );
}

// ─── Explore Screen ────────────────────────────────────────────
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final categories = [
      ('Movies', Icons.movie, 3),
      ('TV Shows', Icons.tv, 1),
      ('Games', Icons.sports_esports, 1),
      ('Books', Icons.book, 1),
      ('Anime', Icons.animation, 1),
      ('Workouts', Icons.fitness_center, 1),
      ('Locations', Icons.location_on, 1),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OmniversifyTextField(
              hint: 'Search posts, people, topics...',
              prefixIcon: const Icon(Icons.search, size: 20),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final (label, icon, count) = categories[index];
                return Container(
                  width: 90,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: gold.withAlpha(40), width: 0.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: gold, size: 28),
                      const SizedBox(height: 6),
                      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
                      Text('$count posts', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('TRENDING', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 12)),
          ),
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: MuteService.instance.muted,
          builder: (context, muted, _) {
            final visible = [
              for (final post in dummyPosts)
                if (!muted.contains(post.user.handle)) post,
            ];
            if (visible.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildPost(visible[index % visible.length]),
                childCount: 5,
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

// ─── Profile Screen ────────────────────────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final userPosts = dummyPosts.where((p) => p.user.handle == currentUser.handle).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: gold.withAlpha(40),
                      child: Text(currentUser.name[0].toUpperCase(), style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: gold)),
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.settings, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const XpBar(),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(currentUser.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(Icons.verified, size: 20, color: gold),
                  ],
                ),
                const SizedBox(height: 2),
                Text(currentUser.handle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                  'Casablanca, Morocco\nTracking every movie, game, book, and anime.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _profileStat(context, 'Posts', '${userPosts.length}'),
                    _profileStat(context, 'Following', '156'),
                    _profileStat(context, 'Followers', '1.2K'),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('MY POSTS', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 12)),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildPost(userPosts[index]),
            childCount: userPosts.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _profileStat(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ─── Post builder helper ────────────────────────────────────────
Widget _buildPost(Post post) {
  switch (post.type) {
    case PostType.text:
      return TextPostWidget(post: post);
    case PostType.image:
      return ImagePostWidget(post: post);
    case PostType.movie:
      return MoviePostWidget(post: post);
    case PostType.tvShow:
      return TvShowPostWidget(post: post);
    case PostType.game:
      return GamePostWidget(post: post);
    case PostType.book:
      return BookPostWidget(post: post);
    case PostType.anime:
      return AnimePostWidget(post: post);
    case PostType.location:
      return LocationPostWidget(post: post);
    case PostType.workout:
      return WorkoutPostWidget(post: post);
    case PostType.video:
      return VideoPostWidget(post: post);
  }
}

// ─── Notifications Drawer (left) ─────────────────────────────
class NotificationsDrawer extends StatefulWidget {
  const NotificationsDrawer({super.key});

  @override
  State<NotificationsDrawer> createState() => _NotificationsDrawerState();
}

class _NotificationsDrawerState extends State<NotificationsDrawer> {
  TripleDate? _dates;
  bool _refreshing = false;

  /// 0 = notifications from people, 1 = what the system sent.
  int _notifTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Show the cached dates first, then fetch the live date.
  /// Keep the cache when they match; replace it when they don't.
  Future<void> _load() async {
    final cached = await DateCache.load();
    if (cached != null && mounted) {
      setState(() => _dates = cached);
    }

    setState(() => _refreshing = true);
    try {
      final fresh = await DateService.fetchToday();
      if (!mounted) return;
      final same = cached != null && DateCache.isSameDay(cached, fresh);
      if (!same || _dates == null) {
        await DateCache.save(fresh);
        if (mounted) setState(() => _dates = fresh);
      }
    } catch (_) {
      // Offline / API down — keep whatever is already on screen.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final cs = Theme.of(context).colorScheme;

    // Timestamps are the ones they shipped with — splitting them into two
    // tabs moves nothing around.
    final social = [
      ('Ahmed liked your post', '2m ago', Icons.favorite, Colors.red),
      ('Sara commented on your post', '15m ago', Icons.chat_bubble, gold),
      ('Youssef started following you', '1h ago', Icons.person_add, Colors.blue),
      ('Your workout was shared!', '5h ago', Icons.share, Colors.green),
      ('Ahmed liked your photo', '2d ago', Icons.favorite, Colors.red),
    ];

    final system = [
      ('New post from Movie Club', '3h ago', Icons.movie, gold),
      ('Book recommendation for you', '1d ago', Icons.book, gold),
      ('Your weekly XP summary is ready', '4d ago', Icons.emoji_events, gold),
      ('Welcome to Omniversify', '5d ago', Icons.auto_awesome, gold),
    ];

    final notifications = _notifTab == 0 ? social : system;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined, color: gold, size: 22),
                  const SizedBox(width: 8),
                  Text('Notifications', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_refreshing)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: gold),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DatesColumn(dates: _dates, gold: gold),
            const Divider(height: 1),
            // The dates block stays exactly where it was — the tabs slot in
            // below it, between it and the list.
            _DrawerTabs(
              labels: const ['Social', 'System'],
              index: _notifTab,
              onSelect: (index) => setState(() => _notifTab = index),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final (text, time, icon, color) = notifications[index];
                  return ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    title: Text(text, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(time, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(150))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two plain bold labels with a gold underline on the active one — the same
/// tab treatment the scrolls screen uses, reused by both drawers.
class _DrawerTabs extends StatelessWidget {
  const _DrawerTabs({
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Column(
                      children: [
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: i == index ? gold : cs.onSurface.withAlpha(140),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: i == index ? gold : Colors.transparent,
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

/// Vertical column of today's calendar dates (year included).
/// Falls back to a local Gregorian date until the cache / API lands.
class _DatesColumn extends StatelessWidget {
  const _DatesColumn({required this.dates, required this.gold});

  final TripleDate? dates;
  final Color gold;

  static const _enDays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _enMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  // DateTime.weekday: 1 = Monday … 7 = Sunday
  static const _arDays = [
    'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];
  static const _tfDays = [
    'ⴰⵢⵏⴰⵙ', 'ⴰⵙⵉⵏⴰⵙ', 'ⴰⴽⵕⴰⵙ', 'ⴰⴽⵡⴰⵙ',
    'ⴰⵙⵉⵎⵡⴰⵙ', 'ⴰⵙⵉⴹⵢⴰⵙ', 'ⴰⵙⴰⵎⴰⵙ',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final weekdayIdx = now.weekday - 1;

    final rows = <(String, String, IconData)>[
      if (dates != null) ...[
        (
          '${_enDays[weekdayIdx]}, ${dates!.gregorian.year} · ${dates!.gregorian.day} ${dates!.gregorian.month.latin}',
          'Gregorian',
          Icons.calendar_today_outlined,
        ),
        (
          '${_arDays[weekdayIdx]} ${dates!.islamic.day} ${dates!.islamic.month.arabic} ${dates!.islamic.year}',
          'Islamic',
          Icons.mosque_outlined,
        ),
        (
          '${_tfDays[weekdayIdx]} ${dates!.amazigh.day} ${dates!.amazigh.month.tifinagh} ${dates!.amazigh.year}',
          'Amazigh',
          Icons.public,
        ),
      ] else (
        '${_enDays[weekdayIdx]}, ${now.day} ${_enMonths[now.month - 1]} ${now.year}',
        'Gregorian',
        Icons.calendar_today_outlined,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DATES',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: gold,
                ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (value, label, icon) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: cs.onSurface.withAlpha(140),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── DMs Drawer (right) ──────────────────────────────────────
class DmsDrawer extends StatefulWidget {
  const DmsDrawer({super.key});

  @override
  State<DmsDrawer> createState() => _DmsDrawerState();
}

class _DmsDrawerState extends State<DmsDrawer> {
  /// 0 = message threads, 1 = the people you're acquainted with.
  int _tab = 0;

  /// Placeholder acquaintances — real ones take over once get-acquainted
  /// requests can be accepted.
  static const _acquaintances = [
    ('Amina', '@amina_stream', 'Acquainted · 12 mutuals'),
    ('Omar', '@omar_gamer', 'Acquainted · 5 mutuals'),
    ('Fatima', '@fatima_art', 'Acquainted · 3 mutuals'),
    ('Karim', '@karim_w', 'Acquainted · 2 mutuals'),
  ];

  /// First letter of a handle, without the `@`.
  static String _initial(String handle) {
    final clean = handle.replaceFirst('@', '');
    return clean.isEmpty ? '?' : clean.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final cs = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    _tab == 0 ? Icons.chat_outlined : Icons.people_outline,
                    color: gold,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _tab == 0 ? 'Messages' : 'Acquaintances',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DrawerTabs(
              labels: const ['Messages', 'Acquaintances'],
              index: _tab,
              onSelect: (index) => setState(() => _tab = index),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: OmniversifyTextField(
                hint: _tab == 0 ? 'Search messages...' : 'Search acquaintances...',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
            Expanded(
              child: _tab == 0
                  ? _messagesList(context, gold, cs)
                  : _acquaintancesList(context, gold, cs),
            ),
          ],
        ),
      ),
    );
  }

  /// Every conversation that has something in it, with the last line and
  /// whoever is still waiting for an answer.
  Widget _messagesList(BuildContext context, Color gold, ColorScheme cs) {
    return ValueListenableBuilder<Map<String, List<ChatMessage>>>(
      valueListenable: MessagesService.instance.threads,
      builder: (context, threads, _) {
        final live = MessagesService.people
            .where((person) =>
                (threads[person.handle] ?? const <ChatMessage>[])
                    .isNotEmpty)
            .toList(growable: false);

        return ValueListenableBuilder<Set<String>>(
          valueListenable: MessagesService.instance.unread,
          builder: (context, unread, _) {
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: live.length,
              itemBuilder: (context, index) {
                final person = live[index];
                final last = threads[person.handle]!.last;
                final hasUnread = unread.contains(person.handle);
                return ListTile(
                  key: ValueKey('dm-${person.handle}'),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: gold.withAlpha(30),
                    child: Text(
                      person.initial,
                      style: TextStyle(
                          color: gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(person.name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                      ),
                      Text(last.when,
                          style: TextStyle(
                              fontSize: 11,
                              color: hasUnread
                                  ? gold
                                  : Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color)),
                    ],
                  ),
                  subtitle: Text(last.text,
                      style: TextStyle(
                          fontSize: 12,
                          color: hasUnread
                              ? Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                              : Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onTap: () => _openChat(context, person.handle, person.name),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Closes the drawer and opens that conversation over it.
  void _openChat(BuildContext context, String handle, String name) {
    final navigator = Navigator.of(context);
    Scaffold.of(context).closeEndDrawer();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(handle: handle, name: name),
      ),
    );
  }

  /// Requests still in flight, then the people already acquainted.
  Widget _acquaintancesList(BuildContext context, Color gold, ColorScheme cs) {
    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withAlpha(150),
            ),
          ),
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ValueListenableBuilder<Set<String>>(
          valueListenable: RelationshipService.instance.requests,
          builder: (context, requests, _) {
            if (requests.isEmpty) return const SizedBox.shrink();
            final pending = requests.toList()..sort();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionLabel('REQUESTS'),
                for (final handle in pending)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: gold.withAlpha(30),
                      child: Text(
                        _initial(handle),
                        style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    title: Text(handle, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      'Request sent',
                      style: TextStyle(fontSize: 12, color: gold),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 18, color: cs.onSurface.withAlpha(150)),
                      tooltip: 'Withdraw request',
                      onPressed: () {
                        RelationshipService.instance.toggleRequest(handle);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Request to $handle withdrawn'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
              ],
            );
          },
        ),
        const AcquaintanceActivity(),
        sectionLabel('ACQUAINTED'),
        for (final (name, handle, note) in _acquaintances)
          ListTile(
            key: ValueKey('acq-$handle'),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: gold.withAlpha(30),
              child: Text(name[0], style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            title: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                Text(handle, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(150))),
              ],
            ),
            subtitle: Text(note, style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => _openChat(context, handle, name),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
