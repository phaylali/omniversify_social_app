import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/media_api.dart';
import '../services/episode_tracker_service.dart';
import '../widgets/action_sheet.dart';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Air date the way the app writes dates: '2019-02-28' → '28 Feb 2019'.
/// A bare year stays a year, and anything the API left unfilled (null,
/// empty, 'TBA') disappears rather than showing a placeholder.
String? airDateText(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty || value.toUpperCase() == 'TBA') return null;

  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(value);
  if (iso == null) return value;

  final month = int.parse(iso.group(2)!);
  if (month < 1 || month > _months.length) return value;
  return '${int.parse(iso.group(3)!)} ${_months[month - 1]} ${iso.group(1)}';
}

/// One episode as the tracking page sees it — however much of the API
/// filled in. The season map often holds nothing but numbers, sometimes a
/// title and an air date too.
class SeriesEpisode implements Comparable<SeriesEpisode> {
  const SeriesEpisode({
    required this.seasonKey,
    required this.episodeKey,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.date,
    this.description,
  });

  /// 'S01' — how the backend keys a season.
  final String seasonKey;

  /// 'E05' — how the backend keys an episode.
  final String episodeKey;

  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final String? date;
  final String? description;

  /// What the tracker stores and what the API reports: `S01E05`.
  String get key => '$seasonKey$episodeKey';

  /// From a row of `GET /{category}/{id}/episodes`.
  factory SeriesEpisode.fromApi(Map<String, dynamic> json) {
    final seasonKey = json['season']?.toString() ?? '';
    final episodeKey = json['episode']?.toString() ?? '';
    return SeriesEpisode(
      seasonKey: seasonKey,
      episodeKey: episodeKey,
      seasonNumber: _asNumber(json['season_number']) ?? digitsOf(seasonKey),
      episodeNumber: _asNumber(json['episode_number']) ?? digitsOf(episodeKey),
      title: _asText(json['title']),
      date: _asText(json['date']),
      description: _asText(json['description']),
    );
  }

  /// From a detail payload's embedded `{S01: {E01: {…}}}` map — the fallback
  /// for categories with no `/episodes` route (anime today), and for a show
  /// whose episode list the API never filled in.
  static List<SeriesEpisode> fromEpisodeMap(dynamic map) {
    if (map is! Map) return const [];
    final out = <SeriesEpisode>[];
    map.forEach((season, episodes) {
      if (episodes is! Map) return;
      final seasonKey = season.toString();
      episodes.forEach((episode, meta) {
        final data = meta is Map ? meta : const <dynamic, dynamic>{};
        out.add(SeriesEpisode(
          seasonKey: seasonKey,
          episodeKey: episode.toString(),
          seasonNumber: digitsOf(seasonKey),
          episodeNumber: digitsOf(episode.toString()),
          title: _asText(data['title']),
          date: _asText(data['date']),
          description: _asText(data['description']),
        ));
      });
    });
    return out..sort();
  }

  /// Numeric part of a season/episode key: 'S01' → 1, 'E12' → 12.
  static int digitsOf(String key) {
    final digits = StringBuffer();
    for (final ch in key.codeUnits) {
      if (ch >= 0x30 && ch <= 0x39) digits.writeCharCode(ch);
    }
    final text = digits.toString();
    return text.isEmpty ? 0 : (int.tryParse(text) ?? 0);
  }

  static int? _asNumber(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String? _asText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  int compareTo(SeriesEpisode other) {
    final bySeason = seasonNumber.compareTo(other.seasonNumber);
    if (bySeason != 0) return bySeason;
    final byEpisode = episodeNumber.compareTo(other.episodeNumber);
    if (byEpisode != 0) return byEpisode;
    return key.compareTo(other.key);
  }
}

/// The full tracking page for one series: every season, every episode, each
/// with a checkmark — plus one tap to mark a whole season for shows you
/// binged long ago and can't be bothered to tick box by box.
class SeriesTrackingScreen extends StatefulWidget {
  const SeriesTrackingScreen({
    super.key,
    required this.category,
    required this.item,
    this.accent = const Color(0xFFC2B067),
    this.episodes,
  });

  /// 'tv', 'anime', … — decides which route is asked for the episode list.
  final String category;

  /// The show: the detail payload, or a list snapshot merged with it.
  final Map<String, dynamic> item;

  final Color accent;

  /// A ready-made episode list. Tests pass one in so nothing hits the network.
  final List<SeriesEpisode>? episodes;

  @override
  State<SeriesTrackingScreen> createState() => _SeriesTrackingScreenState();
}

class _SeriesTrackingScreenState extends State<SeriesTrackingScreen> {
  List<SeriesEpisode>? _episodes;
  Map<String, List<SeriesEpisode>> _seasons = const {};
  bool _loading = false;
  String? _error;
  late final String _series;

  @override
  void initState() {
    super.initState();
    _series = EpisodeTrackerService.seriesKey(
      widget.category,
      widget.item['id'],
    );
    _apply(widget.episodes);
    _loading = _episodes == null;
    if (_episodes == null) {
      _load();
    } else {
      // Progress has to be read before the first rows decide what to show;
      // the ValueListenableBuilder below repaints the page when it lands.
      unawaited(EpisodeTrackerService.instance.load());
    }
  }

  void _apply(List<SeriesEpisode>? episodes) {
    if (episodes == null) {
      _episodes = null;
      _seasons = const {};
      return;
    }
    final sorted = [...episodes]..sort();
    final groups = <String, List<SeriesEpisode>>{};
    for (final ep in sorted) {
      groups.putIfAbsent(ep.seasonKey, () => []).add(ep);
    }
    _episodes = sorted;
    _seasons = groups;
  }

  Future<void> _load() async {
    // The first call comes straight from initState, where _loading is
    // already true and setState would only schedule a pointless rebuild.
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await EpisodeTrackerService.instance.load();

    var episodes = const <SeriesEpisode>[];
    var failed = false;
    try {
      final rows = await MediaApi.episodes(
        category: widget.category,
        id: widget.item['id'],
      );
      episodes = rows.map(SeriesEpisode.fromApi).toList()..sort();
    } catch (_) {
      // No /episodes route for this category — the maps below fill in.
      failed = true;
    }

    if (episodes.isEmpty) {
      episodes = SeriesEpisode.fromEpisodeMap(widget.item['episodes']);
    }
    if (episodes.isEmpty) {
      // The list snapshot in the dialog carries no season map; ask for one.
      try {
        final detail = await MediaApi.detail(
          category: widget.category,
          id: widget.item['id'],
        );
        episodes = SeriesEpisode.fromEpisodeMap(detail['episodes']);
      } catch (_) {
        // Nothing more to fall back on — the message below explains why.
      }
    }

    if (!mounted) return;
    setState(() {
      _apply(episodes);
      _loading = false;
      _error = episodes.isEmpty
          ? (failed
              ? 'The episode list could not be loaded.'
              : 'No episodes are listed for this series yet.')
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final name = (item['name'] ?? item['title'] ?? 'Series').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('track-menu'),
            tooltip: 'Tracking options',
            icon: const Icon(Icons.more_vert),
            onPressed: _openMenu,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && (_episodes == null || _episodes!.isEmpty)) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2),
      );
    }
    if (_episodes == null || _episodes!.isEmpty) {
      return _MessageState(
        accent: widget.accent,
        icon: Icons.playlist_remove,
        message: _error ??
            'No episodes are listed for this series yet.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    return ValueListenableBuilder<Map<String, Set<String>>>(
      valueListenable: EpisodeTrackerService.instance.watched,
      builder: (context, watched, _) {
        final seen = watched[_series] ?? const <String>{};
        final episodes = _episodes!;
        final details = _detailsCard();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ?details,
            _progressCard(episodes, seen),
            ..._seasons.entries.map(
              (entry) => _seasonSection(entry.key, entry.value, seen),
            ),
          ],
        );
      },
    );
  }

  // ─── Details ────────────────────────────────────────────────

  /// First non-empty value among [keys] — TV writes `premiered`, anime
  /// writes `aired_from`, and a list of genres joins itself.
  String? _firstOf(List<String> keys) {
    for (final key in keys) {
      final value = widget.item[key];
      if (value == null) continue;
      if (value is List) {
        final parts = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(' · ');
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// Status, rating, run time, air dates, network, genres — the show above
  /// its own list of checkmarks. Returns null when the API told us nothing,
  /// so an info-free show doesn't get an empty box.
  Widget? _detailsCard() {
    final status = _firstOf(['status']);
    final rating = _firstOf(['rating', 'score']);
    final runtime = _firstOf(['runtime']);
    final network = _firstOf(['network', 'studios', 'producers']);
    final genres = _firstOf(['genres']);
    final from = airDateText(_firstOf(['premiered', 'aired_from']));
    final to = airDateText(_firstOf(['ended', 'aired_to']));
    final span = (from != null && to != null) ? '$from – $to' : (from ?? to);

    final facts = <String>[
      ?status,
      if (rating != null) '★ $rating',
      if (runtime != null) '$runtime min',
    ];
    if (facts.isEmpty && span == null && network == null && genres == null) {
      return null;
    }

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return Container(
      key: const ValueKey('track-details'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (facts.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final fact in facts)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      fact,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.accent,
                      ),
                    ),
                  ),
              ],
            ),
          if (span != null) ...[
            const SizedBox(height: 10),
            Text(span, style: TextStyle(fontSize: 13, color: muted)),
          ],
          if (network != null) ...[
            const SizedBox(height: 4),
            Text(network, style: TextStyle(fontSize: 13, color: muted)),
          ],
          if (genres != null) ...[
            const SizedBox(height: 8),
            Text(genres, style: TextStyle(fontSize: 13, color: muted)),
          ],
        ],
      ),
    );
  }

  // ─── Progress + next up ─────────────────────────────────────

  Widget _progressCard(List<SeriesEpisode> episodes, Set<String> seen) {
    final total = episodes.length;
    final done = episodes.where((e) => seen.contains(e.key)).length;

    SeriesEpisode? next;
    for (final ep in episodes) {
      if (!seen.contains(ep.key)) {
        next = ep;
        break;
      }
    }
    final nextEpisode = next;

    return Container(
      key: const ValueKey('track-progress'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '$done of $total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const ValueKey('track-bar'),
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: widget.accent,
              backgroundColor:
                  Theme.of(context).colorScheme.onSurface.withAlpha(24),
            ),
          ),
          const SizedBox(height: 14),
          if (nextEpisode == null)
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: widget.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Every episode watched',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next up',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _episodeLabel(nextEpisode),
                        key: const ValueKey('track-next'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  key: const ValueKey('mark-next'),
                  onPressed: () => EpisodeTrackerService.instance.setEpisode(
                    _series,
                    nextEpisode.key,
                    true,
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Mark watched'),
                  style: FilledButton.styleFrom(
                    foregroundColor: widget.accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ─── Seasons ────────────────────────────────────────────────

  Widget _seasonSection(
    String seasonKey,
    List<SeriesEpisode> episodes,
    Set<String> seen,
  ) {
    final done = episodes.where((e) => seen.contains(e.key)).length;
    final all = done == episodes.length;
    final label = _seasonLabel(episodes.first.seasonNumber);

    return Padding(
      key: ValueKey('season-$seasonKey'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$done of ${episodes.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const Spacer(),
              IconButton(
                key: ValueKey('season-$seasonKey-mark'),
                tooltip: all
                    ? 'Unmark this season'
                    : 'Mark the whole season watched',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  all ? Icons.playlist_remove : Icons.playlist_add_check,
                  size: 20,
                  color: all
                      ? Theme.of(context).textTheme.bodySmall?.color
                      : widget.accent,
                ),
                onPressed: () => EpisodeTrackerService.instance.setSeason(
                  _series,
                  episodes.map((e) => e.key),
                  !all,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (final ep in episodes) _episodeRow(ep, seen.contains(ep.key)),
        ],
      ),
    );
  }

  Widget _episodeRow(SeriesEpisode ep, bool watched) {
    final date = airDateText(ep.date);
    final subtitle = (date == null && ep.description == null)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (date != null)
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              if (date != null && ep.description != null)
                const SizedBox(height: 2),
              if (ep.description != null)
                Text(
                  ep.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
            ],
          );

    return CheckboxListTile(
      key: ValueKey('ep-${ep.key}'),
      value: watched,
      onChanged: (value) => EpisodeTrackerService.instance.setEpisode(
        _series,
        ep.key,
        value ?? false,
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: widget.accent,
      checkboxShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      title: Text(
        _episodeLabel(ep),
        style: TextStyle(
          fontSize: 14,
          fontWeight: watched ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle,
    );
  }

  /// 'Season 3 · Episode 12 · The finale' — one line, digits as digits.
  String _episodeLabel(SeriesEpisode ep) {
    final title = ep.title;
    final base = '${_seasonLabel(ep.seasonNumber)} · Episode ${ep.episodeNumber}';
    return (title == null || title.isEmpty) ? base : '$base · $title';
  }

  String _seasonLabel(int number) =>
      number == 0 ? 'Specials' : 'Season $number';

  // ─── Menu ───────────────────────────────────────────────────

  void _openMenu() {
    final episodes = _episodes ?? const <SeriesEpisode>[];
    showActionSheet(
      context,
      title: 'Episode tracking',
      subtitle: (widget.item['name'] ?? widget.item['title'] ?? '')
          .toString(),
      icon: Icons.playlist_add_check,
      items: [
        ActionSheetItem(
          icon: Icons.done_all,
          title: 'Mark every episode watched',
          subtitle: '${episodes.length} episodes ticked in one go',
          onTap: episodes.isEmpty
              ? null
              : () => EpisodeTrackerService.instance.setSeason(
                    _series,
                    episodes.map((e) => e.key),
                    true,
                  ),
        ),
        ActionSheetItem(
          icon: Icons.delete_outline,
          title: 'Clear tracking for this series',
          subtitle: 'Every checkmark on this page is removed',
          tone: ActionSheetTone.destructive,
          onTap: () => EpisodeTrackerService.instance.clear(_series),
        ),
      ],
    );
  }
}

/// Empty / failed state with one way forward, matching the tracker tabs.
class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.accent,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final Color accent;
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: accent),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(foregroundColor: accent),
            ),
          ],
        ),
      ),
    );
  }
}
