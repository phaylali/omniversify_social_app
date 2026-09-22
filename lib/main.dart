import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omniversify_widget/omniversify_widget.dart';
import 'core/config/api_config.dart';
import 'models/post.dart';
import 'data/dummy_data.dart';
import 'services/audio_player_service.dart';
import 'widgets/widgets.dart';
import 'widgets/date_header_widget.dart';
import 'screens/scrolls_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ApiConfig.load();
  // Start media session + load persisted player settings before first frame
  // so the Android notification is ready as soon as playback begins.
  final audio = AudioPlayerService.instance;
  await audio.init();
  await audio.connectAudioService();
  runApp(const ProviderScope(child: OmniversifySocialApp()));
}

class OmniversifySocialApp extends ConsumerWidget {
  const OmniversifySocialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(catppuccinThemeProvider);
    final provider = ref.read(catppuccinThemeProvider.notifier);

    return MaterialApp(
      title: 'Omniversify Social',
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

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final isScrolls = _selectedIndex == 2;
    final showFab = _selectedIndex == 0;

    return Scaffold(
      appBar: isScrolls
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
              title: Text(OmniversifyConstants.appName, style: TextStyle(fontWeight: FontWeight.w700)),
              actions: [
                if (_selectedIndex == 0)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {},
                  ),
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
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
      floatingActionButton: showFab
          ? FloatingActionButton(
              backgroundColor: gold,
              onPressed: () {},
              child: Icon(Icons.add, color: Theme.of(context).colorScheme.surface),
            )
          : null,
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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: dummyPosts.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return const DateHeader();
        return _buildPost(dummyPosts[index - 1]);
      },
    );
  }
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
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildPost(dummyPosts[index % dummyPosts.length]),
            childCount: 5,
          ),
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
    final userPosts = dummyPosts.where((p) => p.user.handle == '@youssef_ma').toList();

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
                      child: Text('Y', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: gold)),
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
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Youssef', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(Icons.verified, size: 20, color: gold),
                  ],
                ),
                const SizedBox(height: 2),
                Text('@youssef_ma', style: Theme.of(context).textTheme.bodySmall),
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
class NotificationsDrawer extends StatelessWidget {
  const NotificationsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    final notifications = [
      ('Ahmed liked your post', '2m ago', Icons.favorite, Colors.red),
      ('Sara commented on your post', '15m ago', Icons.chat_bubble, gold),
      ('Youssef started following you', '1h ago', Icons.person_add, Colors.blue),
      ('New post from Movie Club', '3h ago', Icons.movie, gold),
      ('Your workout was shared!', '5h ago', Icons.share, Colors.green),
      ('Book recommendation for you', '1d ago', Icons.book, gold),
      ('Ahmed liked your photo', '2d ago', Icons.favorite, Colors.red),
    ];

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
                ],
              ),
            ),
            const Divider(height: 1),
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
                    subtitle: Text(time, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color)),
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

// ─── DMs Drawer (right) ──────────────────────────────────────
class DmsDrawer extends StatelessWidget {
  const DmsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    final conversations = [
      ('Ahmed', '@ahmed_m', 'Sure, let\'s watch it together!', '2m', false),
      ('Sara', '@sara_dev', 'I just finished the book!', '15m', true),
      ('Omar', '@omar_92', 'Check this game out', '1h', false),
      ('Fatima', '@fatima_art', 'The workout was intense 💪', '3h', false),
      ('Youssef', '@youssef_ma', 'See you tomorrow!', '1d', true),
      ('Karim', '@karim_w', 'Thanks for the recommendation', '2d', false),
    ];

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.chat_outlined, color: gold, size: 22),
                  const SizedBox(width: 8),
                  Text('Messages', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: OmniversifyTextField(
                hint: 'Search messages...',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final (name, handle, lastMsg, time, unread) = conversations[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: gold.withAlpha(30),
                      child: Text(name[0], style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(name, style: TextStyle(fontSize: 14, fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                        ),
                        Text(time, style: TextStyle(fontSize: 11, color: unread ? gold : Theme.of(context).textTheme.bodySmall?.color)),
                      ],
                    ),
                    subtitle: Text(lastMsg, style: TextStyle(fontSize: 12, color: unread ? Theme.of(context).textTheme.bodyMedium?.color : Theme.of(context).textTheme.bodySmall?.color), maxLines: 1, overflow: TextOverflow.ellipsis),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
