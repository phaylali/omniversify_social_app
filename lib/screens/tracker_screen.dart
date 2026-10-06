import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/services/media_api.dart';
import '../services/episode_tracker_service.dart';
import '../services/tracker_collection_service.dart';
import '../services/tracker_tabs.dart';
import '../widgets/action_sheet.dart';
import '../widgets/app_logo.dart';
import 'integrations_screen.dart';
import 'series_tracking_screen.dart';
import 'upcoming_tab.dart';

/// The tracker screen: Discovery first, then whichever tabs this category
/// actually keeps — series get Upcoming / Watching / Watched, games travel
/// Wishlist → Owned → Played, music swaps collections for playlists.
///
/// Which is which lives in `tracker_tabs.dart`; Discovery always fetches
/// live data from the omniversify-api backend as a grid.

class TrackerScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color? accentColor;

  /// API category key: games, movies, tv, anime, books, music, podcasts.
  final String? apiCategory;

  const TrackerScreen({
    super.key,
    required this.title,
    required this.icon,
    this.accentColor,
    this.apiCategory,
  });

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Color _accent;
  late final TrackerTabs _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = trackerTabsFor(widget.apiCategory);
    _tabController = TabController(length: _tabs.labels.length, vsync: this);
    _accent = widget.accentColor ?? const Color(0xFFC2B067);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodySmall;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 20, color: _accent),
            const SizedBox(width: 8),
            Text(widget.title,
                style: TextStyle(fontWeight: FontWeight.w700, color: _accent)),
          ],
        ),
        centerTitle: true,
        // Steam is the one service that hands over a library, and this is
        // the tracker it belongs to.
        actions: [
          if (widget.apiCategory == 'games')
            IconButton(
              key: const ValueKey('steam-import'),
              icon: const Icon(Icons.cloud_download_outlined, size: 20),
              tooltip: 'Import from Steam',
              onPressed: () => showSteamImportSheet(context, accent: _accent),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Four tabs do not fit side by side on a phone: the strip scrolls,
          // and starts flush at the left rather than indented 52px.
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          indicatorColor: _accent,
          indicatorWeight: 2,
          labelColor: _accent,
          unselectedLabelColor: body?.color,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: [for (final label in _tabs.labels) Tab(text: label)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabChildren(),
      ),
    );
  }

  /// One child per tab label, in the same order the TabBar was built.
  List<Widget> _tabChildren() {
    final category = widget.apiCategory;
    return [
      _DiscoverGrid(
        apiCategory: category,
        accent: _accent,
        title: widget.title,
      ),
      if (_tabs.upcoming && category != null)
        UpcomingTab(
          apiCategory: category,
          accent: _accent,
          title: widget.title,
        ),
      for (final slot in _tabs.slots)
        category == null
            ? _PlaceholderTab(
                accent: _accent,
                title: widget.title,
                icon: slot.icon,
                message: slot.empty,
              )
            : _CollectionTab(
                apiCategory: category,
                accent: _accent,
                title: widget.title,
                slot: slot,
              ),
      if (_tabs.playlists && category != null)
        PlaylistsTab(
          apiCategory: category,
          accent: _accent,
          title: widget.title,
        ),
    ];
  }
}

// ─── Discover grid — search, genre filter, pool + See more ──

class _DiscoverGrid extends StatefulWidget {
  final String? apiCategory;
  final Color accent;
  final String title;

  const _DiscoverGrid({
    required this.apiCategory,
    required this.accent,
    required this.title,
  });

  @override
  State<_DiscoverGrid> createState() => _DiscoverGridState();
}

class _DiscoverGridState extends State<_DiscoverGrid>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 9;
  static const int _fetchBatch = 100; // API max limit
  static final _rng = Random();

  /// Everything fetched so far, before the visible window.
  final List<Map<String, dynamic>> _pool = [];
  /// How many pool items are currently on screen.
  int _shown = 0;
  int _apiPage = 1;
  bool _apiHasMore = true;
  bool _loading = false;
  bool _discovering = false;
  String? _error;
  String _searchQuery = '';
  String? _genre;
  final _searchController = TextEditingController();
  int _requestId = 0;

  /// Genre options built from loaded items (TV shows primarily).
  final Set<String> _genreOptions = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resetAndLoad(randomize: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visible {
    if (_genre == null || _genre!.isEmpty) {
      return _pool.take(_shown).toList();
    }
    // When filtering, show up to _shown matches from the whole pool.
    final filtered = _pool
        .where((e) {
          final genres = e['genres'];
          if (genres is List) {
            return genres.any((g) => g.toString() == _genre);
          }
          return false;
        })
        .toList();
    return filtered.take(max(_shown, _pageSize)).toList();
  }

  List<Map<String, dynamic>> get _filteredPool {
    if (_genre == null || _genre!.isEmpty) return _pool;
    return _pool
        .where((e) {
          final genres = e['genres'];
          if (genres is List) {
            return genres.any((g) => g.toString() == _genre);
          }
          return false;
        })
        .toList();
  }

  String get _searchHint {
    switch (widget.apiCategory) {
      case 'music':
        return 'Search title or artist…';
      case 'books':
        return 'Search title or author…';
      case 'games':
        return 'Search title or developer…';
      case 'tv':
        return 'Search shows…';
      default:
        return 'Search ${widget.title.toLowerCase()}…';
    }
  }

  bool get _supportsGenreChips => widget.apiCategory == 'tv';

  void _ingestGenres(Iterable<Map<String, dynamic>> items) {
    if (!_supportsGenreChips) return;
    for (final e in items) {
      final genres = e['genres'];
      if (genres is List) {
        for (final g in genres) {
          final s = g.toString().trim();
          if (s.isNotEmpty) _genreOptions.add(s);
        }
      }
    }
  }

  void _resetAndLoad({bool randomize = false, String? query}) {
    _searchQuery = query ?? '';
    _apiPage = 1;
    _apiHasMore = true;
    _pool.clear();
    _shown = 0;
    _genre = null;
    _genreOptions.clear();
    _error = null;
    _load(randomize: randomize);
  }

  Future<void> _fetchCategoryPage({
    String? search,
    bool randomize = false,
  }) async {
    final category = widget.apiCategory!;
    final isMusicSearch = category == 'music' &&
        search != null &&
        search.isNotEmpty;

    MediaPage page;
    if (isMusicSearch) {
      page = await MediaApi.searchMusic(
        query: search,
        page: _apiPage,
        limit: _fetchBatch,
      );
    } else {
      page = await MediaApi.fetch(
        category: category,
        search: (search == null || search.isEmpty) ? null : search,
        page: _apiPage,
        limit: _fetchBatch,
        live: true,
      );
    }

    var results = page.results;
    if (randomize) {
      results = List.of(results)..shuffle(_rng);
    }
    _pool.addAll(results);
    _ingestGenres(results);
    _apiPage = page.page + 1;
    _apiHasMore = page.hasMore;
  }

  Future<void> _load({bool randomize = false}) async {
    if (_loading) return;
    if (widget.apiCategory == null) return;
    if (!mounted) return;

    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _fetchCategoryPage(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        randomize: randomize,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        // Initial / refresh: show first window; See more expands it.
        _shown = min(_pageSize, _filteredPool.length);
        if (_shown == 0 && _filteredPool.isEmpty && _apiHasMore) {
          // Keep going until something shows or API is exhausted.
        }
        _loading = false;
      });
      // Auto-fill empty first page while API still has more.
      if (_filteredPool.isEmpty && _apiHasMore && !_loading) {
        await _load(randomize: randomize);
      }
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _seeMore() async {
    if (_loading) return;
    final available = _filteredPool.length;
    if (_shown < available) {
      setState(() {
        _shown = min(_shown + _pageSize, available);
      });
      return;
    }
    if (_apiHasMore) {
      await _load();
      setState(() {
        _shown = min(_shown + _pageSize, _filteredPool.length);
      });
      return;
    }
    // Local catalog exhausted — pull more via live upstream search seeds.
    await _discoverMore();
  }

  Future<void> _discoverMore() async {
    if (_discovering || widget.apiCategory == null) return;
    setState(() => _discovering = true);
    try {
      final seeds = _seedQueries(widget.apiCategory!);
      final picked = <String>[];
      final pool = List<String>.from(seeds);
      while (pool.isNotEmpty && picked.length < 3) {
        picked.add(pool.removeAt(_rng.nextInt(pool.length)));
      }
      final before = _pool.length;
      for (final q in picked) {
        try {
          await _fetchCategoryPage(search: q, randomize: true);
        } catch (_) {}
      }
      // Drop duplicates after multi-seed ingest.
      final byId = <dynamic, Map<String, dynamic>>{};
      for (final r in _pool) {
        byId[r['id']] = r;
      }
      _pool
        ..clear()
        ..addAll(byId.values.toList()..shuffle(_rng));
      _ingestGenres(_pool);
      if (!mounted) return;
      setState(() {
        _shown = min(max(_shown, _pageSize), _filteredPool.length);
        _discovering = false;
      });
      if (_pool.length == before && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new titles found — try a search'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _discovering = false);
    }
  }

  List<String> _seedQueries(String category) {
    switch (category) {
      case 'tv':
        return const [
          'breaking bad',
          'the office',
          'friends',
          'stranger things',
          'succession',
          'severance',
          'the wire',
          'dark',
          'peaky blinders',
          'the last of us',
          'better call saul',
          'fleabag',
        ];
      case 'movies':
        return const [
          'inception',
          'interstellar',
          'the matrix',
          'parasite',
          'dune',
          'oppenheimer',
          'joker',
          'whiplash',
          'get out',
          'mad max',
        ];
      case 'games':
        return const [
          'portal',
          'half life',
          'dark souls',
          'final fantasy',
          'resident evil',
          'celeste',
          'hollow knight',
          'stardew valley',
          'doom',
          'minecraft',
        ];
      case 'books':
        return const [
          'hobbit',
          '1984',
          'pride and prejudice',
          'dune',
          'harry potter',
          'gatsby',
          'odyssey',
          'frankenstein',
        ];
      case 'anime':
        return const [
          'naruto',
          'one piece',
          'death note',
          'attack on titan',
          'cowboy bebop',
          'steins gate',
        ];
      case 'podcasts':
        return const [
          'radiolab',
          'syntax',
          'crime',
          'history',
          'science',
          'comedy',
        ];
      case 'music':
        return const [
          'jazz',
          'classical',
          'electronic',
          'rock',
          'hip hop',
          'ambient',
        ];
      default:
        return const ['popular', 'best', 'top'];
    }
  }

  Future<void> _refresh() async {
    _resetAndLoad(randomize: true, query: _searchQuery);
    while (_loading) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _submitSearch(String value) {
    _resetAndLoad(randomize: false, query: value.trim());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.apiCategory == null) {
      return _PlaceholderTab(
        accent: widget.accent,
        title: widget.title,
        icon: Icons.explore_outlined,
        message: 'No API configured for ${widget.title}',
      );
    }

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: _submitSearch,
            onChanged: (v) {
              if (v.isEmpty && _searchQuery.isNotEmpty) _submitSearch('');
            },
            decoration: InputDecoration(
              hintText: _searchHint,
              hintStyle: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withAlpha(140),
              ),
              prefixIcon: Icon(Icons.search, size: 18, color: widget.accent),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        _submitSearch('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: widget.accent.withAlpha(120)),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_supportsGenreChips && _genreOptions.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                _genreChip(null),
                for (final g in _genreOptions.toList()..sort())
                  _genreChip(g),
              ],
            ),
          ),
      ],
    );

    if (_pool.isEmpty && _loading && !_discovering) {
      return Column(
        children: [
          controls,
          Expanded(
            child: Center(
              child: CircularProgressIndicator(
                  color: widget.accent, strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    if (_pool.isEmpty && _error != null && !_loading) {
      return Column(
        children: [
          controls,
          Expanded(
            child: _ErrorState(
              error: _error!,
              accent: widget.accent,
              onRetry: () => _resetAndLoad(randomize: true),
            ),
          ),
        ],
      );
    }

    final visible = _visible;

    if (visible.isEmpty && !_loading && !_discovering) {
      final emptyMsg = _searchQuery.isNotEmpty
          ? 'No results for "$_searchQuery"'
          : _genre != null
              ? 'No $_genre ${widget.title.toLowerCase()} loaded yet'
              : 'No ${widget.title} to discover yet';
      return Column(
        children: [
          controls,
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_outlined,
                      size: 48, color: widget.accent.withAlpha(60)),
                  const SizedBox(height: 12),
                  Text(
                    emptyMsg,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widget.accent.withAlpha(120),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: controls),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _MediaCard(
                    item: visible[index],
                    category: widget.apiCategory ?? '',
                    accent: widget.accent,
                    onTap: () => _openDetail(visible[index]),
                  );
                },
                childCount: visible.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SeeMoreButton(
              loading: _loading || _discovering,
              hasMore: true, // always offer See more / Discover more
              accent: widget.accent,
              discovering: _discovering,
              onPressed: _seeMore,
            ),
          ),
        ],
      ),
    );
  }

  Widget _genreChip(String? value) {
    final selected = _genre == value;
    final label = value ?? 'All';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _genre = value;
            _shown = max(_shown, _pageSize);
          });
        },
        selectedColor: widget.accent.withAlpha(40),
        checkmarkColor: widget.accent,
        labelStyle: TextStyle(
          color: selected ? widget.accent : null,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected
              ? widget.accent.withAlpha(120)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final category = widget.apiCategory;
    if (category == null) return;
    await showMediaDetailDialog(
      context: context,
      category: category,
      item: item,
      accent: widget.accent,
      collection: TrackerCollectionService.instance,
    );
  }
}

// ─── Collection tab (one shelf of the category) ─────────────

class _CollectionTab extends StatefulWidget {
  final String apiCategory;
  final Color accent;
  final String title;
  final TrackerSlot slot;

  const _CollectionTab({
    required this.apiCategory,
    required this.accent,
    required this.title,
    required this.slot,
  });

  @override
  State<_CollectionTab> createState() => _CollectionTabState();
}

class _CollectionTabState extends State<_CollectionTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    TrackerCollectionService.instance.version.addListener(_onStoreChanged);
    _reload();
  }

  @override
  void dispose() {
    TrackerCollectionService.instance.version.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// Somewhere else wrote to the store — an import from Steam, a shelf
  /// button in the detail dialog — so this shelf reads itself again and
  /// shows what is really on it.
  void _onStoreChanged() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    final items = await TrackerCollectionService.instance
        .itemsFor(widget.apiCategory, widget.slot.id);
    if (!mounted) return;
    setState(() {
      _items = List.of(items);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }

    if (_items.isEmpty) {
      return _PlaceholderTab(
        accent: widget.accent,
        title: widget.title,
        icon: widget.slot.icon,
        message: widget.slot.empty,
        // An empty Owned shelf is exactly the moment to go and fetch them.
        action: widget.apiCategory == 'games' && widget.slot.id == 'owned'
            ? _SteamImportAction(accent: widget.accent)
            : null,
      );
    }

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: _reload,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _MediaCard(
                    item: _items[index],
                    category: widget.apiCategory,
                    accent: widget.accent,
                    onTap: () async {
                      await showMediaDetailDialog(
                        context: context,
                        category: widget.apiCategory,
                        item: _items[index],
                        accent: widget.accent,
                        collection: TrackerCollectionService.instance,
                      );
                      if (mounted) await _reload();
                    },
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ─── Media card — poster + title + year ──────────────────────

class _MediaCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String category;
  final Color? accent;
  final VoidCallback? onTap;

  const _MediaCard({
    required this.item,
    required this.category,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = _getTitle();
    final year = _getYear();
    final imageUrl = _getImageUrl();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (_, _) => const Center(
                          child: AppLogo(size: 40, fit: BoxFit.contain),
                        ),
                        errorWidget: (_, _, _) => const Center(
                          child: AppLogo(size: 40, fit: BoxFit.contain),
                        ),
                      )
                    : const Center(
                        child: AppLogo(size: 40, fit: BoxFit.contain),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (_getSubtitle().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _getSubtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withAlpha(180),
              ),
            ),
          ],
          const SizedBox(height: 2),
          if (year.isNotEmpty)
            Text(
              year,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
        ],
      ),
    );
  }

  String _getTitle() {
    switch (category) {
      case 'games':
      case 'tv':
        return item['name'] as String? ?? 'Unknown';
      case 'movies':
      case 'anime':
      case 'books':
      case 'music':
      case 'podcasts':
        return item['title'] as String? ?? 'Unknown';
      default:
        return (item['name'] ?? item['title'] ?? 'Unknown').toString();
    }
  }

  String _getSubtitle() {
    switch (category) {
      case 'music':
      case 'podcasts':
        return (item['artist'] as String?) ?? '';
      case 'books':
        final authors = item['authors'];
        if (authors is List && authors.isNotEmpty) {
          return authors.take(2).join(', ');
        }
        return '';
      case 'movies':
        final director = item['director'];
        if (director != null) return director.toString();
        return '';
      case 'games':
        final devs = item['developers'];
        if (devs is List && devs.isNotEmpty) {
          return devs.take(2).join(', ');
        }
        return '';
      default:
        return '';
    }
  }

  String _getYear() {
    switch (category) {
      case 'games':
        final released = item['released'] as String?;
        if (released != null && released.length >= 4) {
          return released.substring(0, 4);
        }
        return '';
      case 'movies':
        final raw = item['year']?.toString();
        final match = RegExp(r'\d{4}').firstMatch(raw ?? '');
        if (match != null) return match.group(0)!;
        final released = item['released'] as String?;
        if (released != null && released.length >= 4) {
          return released.substring(0, 4);
        }
        return '';
      case 'tv':
        final premiered = item['premiered'] as String?;
        if (premiered != null && premiered.length >= 4) {
          return premiered.substring(0, 4);
        }
        return '';
      case 'anime':
        final airedFrom = item['aired_from'] as String?;
        if (airedFrom != null && airedFrom.length >= 4) {
          return airedFrom.substring(0, 4);
        }
        return '';
      case 'books':
        final year = item['first_publish_year'];
        if (year != null) return year.toString();
        return '';
      case 'music':
        final year = item['year'];
        if (year != null) return year.toString();
        final releaseDate = item['release_date'] as String?;
        if (releaseDate != null && releaseDate.length >= 4) {
          return releaseDate.substring(0, 4);
        }
        return '';
      default:
        return '';
    }
  }

  String? _getImageUrl() {
    switch (category) {
      case 'games':
        return item['background_image'] as String?;
      case 'movies':
        return item['poster'] as String?;
      case 'tv':
      case 'anime':
        return item['image_url'] as String?;
      case 'books':
      case 'music':
        return item['cover_url'] as String?;
      case 'podcasts':
        return item['artwork_url'] as String?;
      default:
        return null;
    }
  }
}

// ─── Detail dialog ──────────────────────────────────────────

Future<void> showMediaDetailDialog({
  required BuildContext context,
  required String category,
  required Map<String, dynamic> item,
  required Color accent,
  required TrackerCollectionService collection,
}) {
  return showDialog(
    context: context,
    builder: (_) => _MediaDetailDialog(
      category: category,
      item: item,
      accent: accent,
      collection: collection,
    ),
  );
}

class _MediaDetailDialog extends StatefulWidget {
  final String category;
  final Map<String, dynamic> item;
  final Color accent;
  final TrackerCollectionService collection;

  const _MediaDetailDialog({
    required this.category,
    required this.item,
    required this.accent,
    required this.collection,
  });

  @override
  State<_MediaDetailDialog> createState() => _MediaDetailDialogState();
}

class _MediaDetailDialogState extends State<_MediaDetailDialog> {
  late Map<String, dynamic> _item;
  bool _loadingDetail = true;
  bool _detailFailed = false;

  /// Which shelf of this category the item sits on, by slot id.
  final Map<String, bool> _flags = {};
  late final TrackerTabs _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = trackerTabsFor(widget.category);
    _item = Map<String, dynamic>.from(widget.item);
    _loadFlags();
    _loadDetail();
  }

  Future<void> _loadFlags() async {
    final flags = <String, bool>{};
    for (final slot in _tabs.slots) {
      flags[slot.id] = await widget.collection
          .contains(widget.category, _item['id'], slot.id);
    }
    if (!mounted) return;
    setState(() => _flags.addAll(flags));
  }

  Future<void> _loadDetail() async {
    final id = _item['id'];
    if (id == null) {
      setState(() {
        _loadingDetail = false;
        _detailFailed = true;
      });
      return;
    }
    try {
      final detail =
          await MediaApi.detail(category: widget.category, id: id);
      if (!mounted) return;
      setState(() {
        _item = {..._item, ...detail};
        _loadingDetail = false;
        _detailFailed = detail.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _detailFailed = true;
      });
    }
  }

  Future<void> _toggle(TrackerSlot slot) async {
    final added =
        await widget.collection.toggle(widget.category, _item, slot.id);
    if (!mounted) return;
    // Shelves are exclusive: filling one empties the rest.
    setState(() {
      for (final other in _tabs.slots) {
        _flags[other.id] = other.id == slot.id ? added : false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added to ${slot.label}' : 'Removed from ${slot.label}',
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Music: playlists ─────────────────────────────────────

  Future<void> _pickPlaylist() async {
    final names = await widget.collection.playlists();
    final counts = <String, int>{
      for (final name in names) name: await widget.collection.playlistCount(name),
    };
    if (!mounted) return;

    showActionSheet(
      context,
      title: 'Add to playlist',
      subtitle: _title,
      icon: Icons.playlist_add,
      items: [
        for (final name in names)
          ActionSheetItem(
            icon: Icons.playlist_play,
            title: name,
            subtitle: '${counts[name]} ${counts[name] == 1 ? 'track' : 'tracks'}',
            onTap: () => _addToPlaylist(name),
          ),
        ActionSheetItem(
          icon: Icons.add,
          title: 'New playlist',
          subtitle: 'Start an empty playlist',
          onTap: _newPlaylist,
        ),
      ],
    );
  }

  Future<void> _addToPlaylist(String name) async {
    final added = await widget.collection.addToPlaylist(name, _item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Added to $name' : 'Already in $name'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _newPlaylist() async {
    final name = await promptPlaylistName(context, accent: widget.accent);
    if (name == null || !mounted) return;
    await widget.collection.createPlaylist(name);
    if (!mounted) return;
    await _addToPlaylist(name);
  }

  String get _title {
    final t = _item['name'] ?? _item['title'];
    if (t != null) return t.toString();
    return 'Unknown';
  }

  String? get _imageUrl {
    switch (widget.category) {
      case 'games':
        return _item['background_image'] as String?;
      case 'movies':
        return _item['poster'] as String?;
      case 'tv':
      case 'anime':
        return _item['image_url'] as String?;
      case 'books':
      case 'music':
        return _item['cover_url'] as String?;
      case 'podcasts':
        return _item['artwork_url'] as String?;
      default:
        return null;
    }
  }

  String? get _description {
    for (final key in ['plot', 'summary', 'synopsis', 'description']) {
      final v = _item[key];
      if (v is String && v.trim().isNotEmpty) {
        return _stripHtml(v);
      }
    }
    return null;
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  List<Widget> _metaRows() {
    final rows = <MapEntry<String, String>>[];
    void add(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        rows.add(MapEntry(label, value.trim()));
      }
    }

    switch (widget.category) {
      case 'movies':
        add('Year', _yearText());
        add('Director', _item['director']?.toString());
        add('Genre', _listOrString(_item['genre']));
        add('Runtime', _item['runtime']?.toString());
        add('Rated', _item['rated']?.toString());
        add('IMDb', _item['imdb_rating']?.toString());
        add('Actors', _item['actors']?.toString());
        add('Country', _item['country']?.toString());
        add('Language', _item['language']?.toString());
        add('Box office', _item['box_office']?.toString());
        break;
      case 'tv':
        add('Year', _yearText());
        add('Status', _item['status']?.toString());
        add('Premiered', _item['premiered']?.toString());
        add('Genre', _listOrString(_item['genres']));
        add('Network', _item['network']?.toString());
        add('Runtime',
            _item['runtime'] == null ? null : '${_item['runtime']} min');
        add('Rating', _item['rating']?.toString());
        add('Language', _item['language']?.toString());
        break;
      case 'anime':
        add('Year', _yearText());
        add('Type', _item['type']?.toString());
        add('Status', _item['status']?.toString());
        add('Episodes', _item['episodes']?.toString());
        add('Score', _item['score']?.toString());
        add('Genre', _listOrString(_item['genres']));
        add('Studios', _listOrString(_item['studios']));
        add('Aired', _item['aired_from']?.toString());
        break;
      case 'books':
        add('Year', _yearText());
        add('Authors', _listOrString(_item['authors']));
        add('Pages', _item['number_of_pages']?.toString());
        add('Publisher', _listOrString(_item['publishers']));
        add('Subjects', _listOrString(_item['subjects']));
        break;
      case 'games':
        add('Year', _yearText());
        add('Developer', _listOrString(_item['developers']));
        add('Publisher', _listOrString(_item['publishers']));
        add('Genre', _listOrString(_item['genres']));
        add('Rating', _item['rating']?.toString());
        add('Metacritic', _item['metacritic']?.toString());
        add('Playtime',
            _item['playtime'] == null ? null : '${_item['playtime']} min');
        add('Platforms', _platformsText());
        add('Website', _item['website']?.toString());
        break;
      case 'music':
        add('Year', _yearText());
        add('Artist', _item['artist']?.toString());
        add('Album', _item['album']?.toString());
        add('Genre', _listOrString(_item['genres']));
        add('Duration', _durationText());
        add('Explicit', _item['explicit'] == true ? 'Yes' : null);
        break;
      case 'podcasts':
        add('Host', _item['artist']?.toString());
        add('Episodes', _item['episode_count']?.toString());
        add('Genre', _listOrString(_item['genres']));
        add('Country', _item['country']?.toString());
        break;
      default:
        break;
    }

    return rows
        .map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.key,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.accent.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.value,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  String? _platformsText() {
    final platforms = _item['platforms'];
    if (platforms is List && platforms.isNotEmpty) {
      final names = platforms.map((p) {
        if (p is Map) return (p['name'] ?? p['slug'] ?? '').toString();
        return p.toString();
      }).where((s) => s.isNotEmpty && s != 'null');
      final joined = names.join(', ');
      return joined.isEmpty ? null : joined;
    }
    return null;
  }

  String? _listOrString(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final parts =
          value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty);
      final joined = parts.join(', ');
      return joined.isEmpty ? null : joined;
    }
    final s = value.toString();
    return s.trim().isEmpty ? null : s;
  }

  String _yearText() {
    switch (widget.category) {
      case 'movies':
        final match =
            RegExp(r'\d{4}').firstMatch(_item['year']?.toString() ?? '');
        if (match != null) return match.group(0)!;
        final released = _item['released']?.toString();
        if (released != null && released.length >= 4) {
          return released.substring(0, 4);
        }
        return '';
      case 'tv':
        final premiered = _item['premiered']?.toString();
        if (premiered != null && premiered.length >= 4) {
          return premiered.substring(0, 4);
        }
        return '';
      case 'anime':
        final aired = _item['aired_from']?.toString();
        if (aired != null && aired.length >= 4) return aired.substring(0, 4);
        return '';
      case 'books':
        return _item['first_publish_year']?.toString() ?? '';
      case 'games':
        final released = _item['released']?.toString();
        if (released != null && released.length >= 4) {
          return released.substring(0, 4);
        }
        return '';
      case 'music':
        final year = _item['year'];
        if (year != null) return year.toString();
        final releaseDate = _item['release_date']?.toString();
        if (releaseDate != null && releaseDate.length >= 4) {
          return releaseDate.substring(0, 4);
        }
        return '';
      default:
        return '';
    }
  }

  String? _durationText() {
    final ms = _item['duration_ms'];
    if (ms is num) {
      final totalSec = (ms ~/ 1000);
      final m = totalSec ~/ 60;
      final s = totalSec % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = _imageUrl;
    final description = _description;
    final year = _yearText();
    final subtitle = _subtitleText();

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final slot in _tabs.slots) ...[
                    Expanded(
                      child: _DetailActionButton(
                        label: slot.label,
                        icon: _flags[slot.id] == true ? Icons.check : slot.icon,
                        active: _flags[slot.id] == true,
                        accent: widget.accent,
                        onPressed: () => _toggle(slot),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_tabs.playlists)
                    Expanded(
                      child: _DetailActionButton(
                        label: 'Add to playlist',
                        icon: Icons.playlist_add,
                        active: false,
                        accent: widget.accent,
                        onPressed: _pickPlaylist,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 96,
                            height: 140,
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 300,
                                    placeholder: (_, _) => const Center(
                                      child: AppLogo(size: 32),
                                    ),
                                    errorWidget: (_, _, _) => const Center(
                                      child: AppLogo(size: 32),
                                    ),
                                  )
                                : const Center(
                                    child: AppLogo(size: 32),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withAlpha(200),
                                  ),
                                ),
                              ],
                              if (year.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: widget.accent.withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    year,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: widget.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_tracksEpisodes) ...[
                      const SizedBox(height: 14),
                      _trackEpisodesButton(),
                    ],
                    if (_loadingDetail) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: CircularProgressIndicator(
                          color: widget.accent,
                          strokeWidth: 2,
                        ),
                      ),
                    ] else ...[
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          description,
                          style: const TextStyle(fontSize: 13, height: 1.45),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (_metaRows().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        ..._metaRows(),
                      ],
                      if (_detailFailed &&
                          description == null &&
                          _metaRows().isEmpty)
                        Text(
                          'Extra details unavailable — using list info.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleText() {
    switch (widget.category) {
      case 'music':
      case 'podcasts':
        return _item['artist']?.toString() ?? '';
      case 'books':
        return _listOrString(_item['authors']) ?? '';
      case 'movies':
        return _item['director']?.toString() ?? '';
      case 'games':
        return _listOrString(_item['developers']) ?? '';
      default:
        return '';
    }
  }

  /// Shows that keep an episode map — TV and anime — open the tracking page.
  bool get _tracksEpisodes =>
      (_item['id'] != null) &&
      (widget.category == 'tv' || widget.category == 'anime');

  /// Full page of checkmarks: every season, every episode, mark one or all.
  Widget _trackEpisodesButton() {
    final series =
        EpisodeTrackerService.seriesKey(widget.category, _item['id']);
    return SizedBox(
      width: double.infinity,
      child: ValueListenableBuilder<Map<String, Set<String>>>(
        valueListenable: EpisodeTrackerService.instance.watched,
        builder: (context, watched, _) {
          final done = watched[series]?.length ?? 0;
          return OutlinedButton.icon(
            key: const ValueKey('track-episodes'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SeriesTrackingScreen(
                  category: widget.category,
                  item: _item,
                  accent: widget.accent,
                ),
              ),
            ),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text(
              done > 0 ? 'Episodes · $done watched' : 'Track episodes',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accent,
              side: BorderSide(color: widget.accent.withAlpha(90)),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          );
        },
      ),
    );
  }
}

// ─── Dialog action button ───────────────────────────────────

class _DetailActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onPressed;

  const _DetailActionButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: active ? accent.withAlpha(40) : null,
        foregroundColor: active ? accent : null,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 34),
      ),
    );
  }
}

// ─── See more button ────────────────────────────────────────

class _SeeMoreButton extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final Color accent;
  final bool discovering;
  final VoidCallback onPressed;

  const _SeeMoreButton({
    required this.loading,
    required this.hasMore,
    required this.accent,
    this.discovering = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMore && !loading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: loading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: accent,
                  strokeWidth: 2,
                ),
              )
            : FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: Icon(
                  discovering ? Icons.auto_awesome : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  discovering
                      ? 'Discovering…'
                      : 'See more', // expands window / next page / live seeds
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent.withAlpha(30),
                  foregroundColor: accent,
                  visualDensity: VisualDensity.comfortable,
                ),
              ),
      ),
    );
  }
}

// ─── Error state ─────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  final Color accent;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.error,
    required this.accent,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: accent.withAlpha(60)),
            const SizedBox(height: 12),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: accent.withAlpha(120),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Placeholder tab (empty Wishlist / Library) ─────────────

/// The one thing an empty Owned shelf can do about being empty.
class _SteamImportAction extends StatelessWidget {
  const _SteamImportAction({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: FilledButton.icon(
        onPressed: () => showSteamImportSheet(context, accent: accent),
        style: FilledButton.styleFrom(backgroundColor: accent),
        icon: const Icon(Icons.cloud_download_outlined, size: 18),
        label: const Text('Import from Steam'),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final Color accent;
  final String title;
  final IconData icon;
  final String message;

  /// Shown under the message when this particular emptiness has something
  /// worth doing about it — only the games' Owned shelf does today.
  final Widget? action;

  const _PlaceholderTab({
    required this.accent,
    required this.title,
    required this.icon,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: accent.withAlpha(60)),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent.withAlpha(120),
                ),
          ),
          ?action,
        ],
      ),
    );
  }
}

// ─── Playlists (music) ──────────────────────────────────────

/// Asks what to call a new playlist; null when the dialog was dismissed or
/// nothing worth keeping was typed.
///
/// The field is owned by the dialog itself, so it outlives this future and is
/// only disposed once the closing animation has let go of it.
Future<String?> promptPlaylistName(
  BuildContext context, {
  required Color accent,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _PlaylistNameDialog(accent: accent),
  );
  final clean = name?.trim();
  if (clean == null || clean.isEmpty) return null;
  return clean;
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.accent});

  final Color accent;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(foregroundColor: widget.accent),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// The Playlists tab: every playlist you have, how big it is, and a way to
/// start another.
class PlaylistsTab extends StatefulWidget {
  const PlaylistsTab({
    super.key,
    required this.apiCategory,
    required this.accent,
    required this.title,
  });

  final String apiCategory;
  final Color accent;
  final String title;

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab>
    with AutomaticKeepAliveClientMixin {
  List<String> _names = [];
  final Map<String, int> _counts = {};
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final collection = TrackerCollectionService.instance;
    final names = await collection.playlists();
    final counts = <String, int>{};
    for (final name in names) {
      counts[name] = await collection.playlistCount(name);
    }
    if (!mounted) return;
    setState(() {
      _names = List.of(names);
      _counts
        ..clear()
        ..addAll(counts);
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = await promptPlaylistName(context, accent: widget.accent);
    if (name == null || !mounted) return;
    await TrackerCollectionService.instance.createPlaylist(name);
    if (mounted) await _reload();
  }

  void _options(String name) {
    showActionSheet(
      context,
      title: name,
      subtitle: '${_counts[name] ?? 0} tracks',
      icon: Icons.queue_music,
      items: [
        ActionSheetItem(
          icon: Icons.delete_outline,
          title: 'Delete playlist',
          subtitle: 'The tracks themselves are not touched',
          tone: ActionSheetTone.destructive,
          onTap: () async {
            await TrackerCollectionService.instance.deletePlaylist(name);
            if (mounted) await _reload();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }
    // The "New playlist" row is the point of an empty tab, so the list is
    // always shown — a message sits under it instead of in front of it.
    final empty = _names.isEmpty;

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          ListTile(
            key: const ValueKey('new-playlist'),
            leading: Icon(Icons.add, color: widget.accent),
            title: const Text('New playlist'),
            onTap: _create,
          ),
          const Divider(height: 1),
          if (empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Text(
                'No playlists yet — name one here, then add tracks to it '
                'from any track you open.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          for (final name in _names)
            ListTile(
              key: ValueKey('playlist-$name'),
              leading: Icon(Icons.queue_music, color: widget.accent),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_counts[name] ?? 0} '
                '${_counts[name] == 1 ? 'track' : 'tracks'}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlaylistScreen(
                      name: name,
                      apiCategory: widget.apiCategory,
                      accent: widget.accent,
                    ),
                  ),
                );
                if (mounted) await _reload();
              },
              onLongPress: () => _options(name),
            ),
        ],
      ),
    );
  }
}

/// One playlist: its tracks as the same cards Discovery uses, with the way
/// to take one back out (long press).
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.name,
    required this.apiCategory,
    required this.accent,
  });

  final String name;
  final String apiCategory;
  final Color accent;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await TrackerCollectionService.instance
        .playlistItems(widget.name);
    if (!mounted) return;
    setState(() {
      _items = List.of(items);
      _loading = false;
    });
  }

  void _options(Map<String, dynamic> item) {
    final title = (item['title'] ?? item['name'] ?? '').toString();
    showActionSheet(
      context,
      title: title.isEmpty ? widget.name : title,
      subtitle: 'In ${widget.name}',
      icon: Icons.music_note,
      items: [
        ActionSheetItem(
          icon: Icons.remove_circle_outline,
          title: 'Remove from playlist',
          subtitle: 'The track itself is not touched',
          tone: ActionSheetTone.destructive,
          onTap: () async {
            await TrackerCollectionService.instance
                .removeFromPlaylist(widget.name, item['id']);
            if (mounted) await _reload();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('delete-playlist'),
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await TrackerCollectionService.instance
                  .deletePlaylist(widget.name);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }
    if (_items.isEmpty) {
      return _PlaceholderTab(
        accent: widget.accent,
        title: widget.name,
        icon: Icons.queue_music_outlined,
        message: 'Nothing in this playlist yet',
      );
    }

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: _reload,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _items[index];
                  return GestureDetector(
                    onLongPress: () => _options(item),
                    child: _MediaCard(
                      item: item,
                      category: widget.apiCategory,
                      accent: widget.accent,
                      onTap: () async {
                        await showMediaDetailDialog(
                          context: context,
                          category: widget.apiCategory,
                          item: item,
                          accent: widget.accent,
                          collection: TrackerCollectionService.instance,
                        );
                        if (mounted) await _reload();
                      },
                    ),
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
