import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/services/media_api.dart';
import '../services/tracker_collection_service.dart';
import 'series_tracking_screen.dart';

/// One episode still to come, with the series it belongs to.
class UpcomingEpisode {
  const UpcomingEpisode({
    required this.series,
    required this.episode,
    required this.days,
  });

  final Map<String, dynamic> series;
  final SeriesEpisode episode;

  /// Whole days from today until it airs — at least 1, or it would not be
  /// here.
  final int days;
}

/// The episodes of [rows] that are still to come, soonest first — the unit
/// the Upcoming tab is built from, and what a test can check without a
/// network.
///
/// Anything without a readable date is left out: an undated episode has no
/// countdown to show and must not be guessed at.
List<UpcomingEpisode> upcomingEpisodes(
  Map<String, dynamic> series,
  List<Map<String, dynamic>> rows,
) {
  final found = <UpcomingEpisode>[];
  for (final row in rows) {
    final episode = SeriesEpisode.fromApi(row);
    final days = daysUntilAired(episode.date);
    if (days == null) continue;
    found.add(UpcomingEpisode(series: series, episode: episode, days: days));
  }
  found.sort((a, b) {
    final byDays = a.days.compareTo(b.days);
    if (byDays != 0) return byDays;
    final bySeason = a.episode.seasonNumber.compareTo(b.episode.seasonNumber);
    if (bySeason != 0) return bySeason;
    return a.episode.episodeNumber.compareTo(b.episode.episodeNumber);
  });
  return found;
}

/// The Upcoming tab: episodes of the series you are following that have not
/// aired yet, nearest first.
///
/// Dates come straight from the episode rows, so a show the backend has not
/// dated yet simply contributes nothing rather than guessing — and nothing
/// on this tab can be marked watched, because it has not happened.
class UpcomingTab extends StatefulWidget {
  const UpcomingTab({
    super.key,
    required this.apiCategory,
    required this.accent,
    required this.title,
  });

  final String apiCategory;
  final Color accent;
  final String title;

  @override
  State<UpcomingTab> createState() => _UpcomingTabState();
}

class _UpcomingTabState extends State<UpcomingTab>
    with AutomaticKeepAliveClientMixin {
  final List<UpcomingEpisode> _entries = [];

  /// How many series are asked at once, and how many at a time — the first
  /// visit to a show also costs the backend a TVmaze lookup, so a queue
  /// keeps the tab from opening forty of them at once.
  static const _maxSeries = 30;
  static const _concurrency = 4;

  bool _loading = true;
  int _followed = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Every series on the Watching or Watched shelf of this category.
  Future<List<Map<String, dynamic>>> _tracked() async {
    final collection = TrackerCollectionService.instance;
    final byId = <String, Map<String, dynamic>>{};
    for (final slot in const ['watching', 'watched']) {
      for (final item in await collection.itemsFor(widget.apiCategory, slot)) {
        final id = item['id'];
        if (id != null) byId[id.toString()] = item;
      }
    }
    return byId.values.take(_maxSeries).toList();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final tracked = await _tracked();
    if (!mounted) return;
    setState(() {
      _followed = tracked.length;
      _entries.clear();
    });

    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= tracked.length) return;
        final series = tracked[index];
        List<UpcomingEpisode> found;
        try {
          final rows = await MediaApi.episodes(
            category: widget.apiCategory,
            id: series['id'],
          );
          found = upcomingEpisodes(series, rows);
        } catch (_) {
          // A show whose episode list will not load is skipped, not fatal.
          found = const [];
        }
        if (found.isEmpty || !mounted) continue;
        setState(() {
          _entries
            ..addAll(found)
            ..sort((a, b) {
              final byDays = a.days.compareTo(b.days);
              if (byDays != 0) return byDays;
              final bySeason =
                  a.episode.seasonNumber.compareTo(b.episode.seasonNumber);
              if (bySeason != 0) return bySeason;
              return a.episode.episodeNumber.compareTo(b.episode.episodeNumber);
            });
        });
      }
    }

    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading && _entries.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }
    if (_entries.isEmpty) return _empty();

    return RefreshIndicator(
      color: widget.accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              '${_plural(_followed, 'series', 'series')} followed · '
              '${_plural(_entries.length, 'episode', 'episodes')} still to come',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          for (final entry in _entries) _row(entry),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upcoming, size: 44, color: widget.accent.withAlpha(90)),
            const SizedBox(height: 14),
            Text(
              _followed == 0
                  ? 'Nothing on the horizon.\nMark a series as Watching from '
                      'Discovery and its next episodes count down here.'
                  : 'Everything your $_followed '
                      '${_followed == 1 ? 'series has' : 'series have'} '
                      'aired so far — the next one will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: widget.accent,
                  strokeWidth: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(UpcomingEpisode entry) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final seriesTitle =
        (entry.series['name'] ?? entry.series['title'] ?? '').toString();
    final poster = entry.series['image_url'] as String?;
    final episode = entry.episode;

    return ListTile(
      key: ValueKey('upcoming-${entry.series['id']}-${episode.key}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 62,
          child: poster != null && poster.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: poster,
                  fit: BoxFit.cover,
                  memCacheWidth: 160,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                )
              : const SizedBox.shrink(),
        ),
      ),
      title: Text(
        seriesTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        _episodeLabel(episode),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 1.35, color: muted),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.accent.withAlpha(30),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          daysLeftText(entry.days),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: widget.accent,
          ),
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeriesTrackingScreen(
            category: widget.apiCategory,
            item: entry.series,
            accent: widget.accent,
          ),
        ),
      ),
    );
  }

  /// '1 episode' / '4 episodes' — the count in digits, as the app writes it.
  String _plural(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';

  /// 'Season 2 · Episode 5 · The finale' — digits as digits, same as the
  /// tracking page.
  String _episodeLabel(SeriesEpisode episode) {
    final season =
        episode.seasonNumber == 0 ? 'Specials' : 'Season ${episode.seasonNumber}';
    final base = '$season · Episode ${episode.episodeNumber}';
    final title = episode.title;
    return (title == null || title.isEmpty) ? base : '$base · $title';
  }
}
