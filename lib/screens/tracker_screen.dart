import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/services/media_api.dart';

/// A generic tracker screen with three tabs: Discover, Wishlist, Library.
/// Discover fetches live data from the omniversify-api backend as a grid.

class TrackerScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color? accentColor;

  /// API category key: games, movies, tv, anime, books.
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _accent = widget.accentColor ?? const Color(0xFFC2B067);
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accent,
          indicatorWeight: 2,
          labelColor: _accent,
          unselectedLabelColor: body?.color,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'Discover'),
            Tab(text: 'Wishlist'),
            Tab(text: 'Library'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DiscoverGrid(
            apiCategory: widget.apiCategory,
            accent: _accent,
            title: widget.title,
          ),
          _PlaceholderTab(
            accent: _accent,
            title: widget.title,
            icon: Icons.favorite_outline,
            message: 'Your ${widget.title} wishlist is empty',
          ),
          _PlaceholderTab(
            accent: _accent,
            title: widget.title,
            icon: Icons.bookmark_outline,
            message: 'Your ${widget.title} library is empty',
          ),
        ],
      ),
    );
  }
}

// ─── Discover grid — live API data with load more ─────────────

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

class _DiscoverGridState extends State<_DiscoverGrid> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    if (widget.apiCategory == null) return;
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await MediaApi.fetch(
        category: widget.apiCategory!,
        page: _page,
        limit: 10,
      );
      if (!mounted) return;
      final existingIds = _items.map((e) => e['id']).toSet();
      final newItems = page.results.where((e) => !existingIds.contains(e['id'])).toList();
      setState(() {
        _items.addAll(newItems);
        _page++;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiCategory == null) {
      return _PlaceholderTab(
        accent: widget.accent,
        title: widget.title,
        icon: Icons.explore_outlined,
        message: 'No API configured for ${widget.title}',
      );
    }

    if (_items.isEmpty && _loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }

    if (_items.isEmpty && _error != null) {
      return _ErrorState(
        error: _error!,
        accent: widget.accent,
        onRetry: () {
          _page = 1;
          _hasMore = true;
          _items.clear();
          _load();
        },
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_outlined, size: 48, color: widget.accent.withAlpha(60)),
            const SizedBox(height: 12),
            Text(
              'No ${widget.title} to discover yet',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.accent.withAlpha(120),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: () async {
        _page = 1;
        _hasMore = true;
        _items.clear();
        await _load();
      },
      child: CustomScrollView(
        slivers: [
          // Grid of media cards
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
                    accent: widget.accent,
                    category: widget.apiCategory ?? '',
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
          // Load more button
          SliverToBoxAdapter(
            child: _LoadMoreButton(
              loading: _loading,
              hasMore: _hasMore,
              accent: widget.accent,
              onPressed: _load,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Media card — poster + title + year ──────────────────────

class _MediaCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color accent;
  final String category;

  const _MediaCard({
    required this.item,
    required this.accent,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final title = _getTitle();
    final year = _getYear();
    final imageUrl = _getImageUrl();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster
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
                      placeholder: (_, __) => _PlaceholderIcon(accent: accent, category: category),
                      errorWidget: (_, __, ___) => _PlaceholderIcon(accent: accent, category: category),
                    )
                  : _PlaceholderIcon(accent: accent, category: category),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Title — max 2 lines, truncate
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
        const SizedBox(height: 2),
        // Year
        if (year.isNotEmpty)
          Text(
            year,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
      ],
    );
  }

  String _getTitle() {
    switch (category) {
      case 'games':
        return item['name'] as String? ?? 'Unknown';
      case 'movies':
        return item['title'] as String? ?? 'Unknown';
      case 'tv':
        return item['name'] as String? ?? 'Unknown';
      case 'anime':
        return item['title'] as String? ?? 'Unknown';
      case 'books':
        return item['title'] as String? ?? 'Unknown';
      default:
        return (item['name'] ?? item['title'] ?? 'Unknown').toString();
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
        final year = item['year'];
        if (year != null) return year.toString();
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
        return item['image_url'] as String?;
      case 'anime':
        return item['image_url'] as String?;
      case 'books':
        return item['cover_url'] as String?;
      default:
        return null;
    }
  }
}

// ─── Placeholder icon when no image ──────────────────────────

class _PlaceholderIcon extends StatelessWidget {
  final Color accent;
  final String category;

  const _PlaceholderIcon({required this.accent, required this.category});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(_getIcon(), color: accent.withAlpha(80), size: 32),
    );
  }

  IconData _getIcon() {
    switch (category) {
      case 'games':
        return Icons.sports_esports_outlined;
      case 'movies':
        return Icons.movie_outlined;
      case 'tv':
        return Icons.tv_outlined;
      case 'anime':
        return Icons.animation_outlined;
      case 'books':
        return Icons.book_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}

// ─── Load more button ───────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final Color accent;
  final VoidCallback onPressed;

  const _LoadMoreButton({
    required this.loading,
    required this.hasMore,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMore && !loading) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
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
            : TextButton.icon(
                onPressed: onPressed,
                icon: Icon(Icons.expand_more, color: accent, size: 20),
                label: Text(
                  'Load more',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
            Icon(Icons.cloud_off_outlined, size: 48, color: accent.withAlpha(60)),
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

// ─── Placeholder tab (Wishlist / Library) ───────────────────

class _PlaceholderTab extends StatelessWidget {
  final Color accent;
  final String title;
  final IconData icon;
  final String message;

  const _PlaceholderTab({
    required this.accent,
    required this.title,
    required this.icon,
    required this.message,
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
        ],
      ),
    );
  }
}
