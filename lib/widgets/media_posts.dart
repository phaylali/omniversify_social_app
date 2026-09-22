import 'package:flutter/material.dart';
import '../models/post.dart';
import 'post_components.dart';
import 'image_preview.dart';

class MoviePostWidget extends StatelessWidget {
  final Post post;

  const MoviePostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final data = post.movieData;
    if (data == null) return const SizedBox.shrink();
    return _MediaPostCard(
      post: post,
      badge: const MediaBadge(label: 'Movie', icon: Icons.movie),
    );
  }
}

class TvShowPostWidget extends StatelessWidget {
  final Post post;

  const TvShowPostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final data = post.tvShowData;
    if (data == null) return const SizedBox.shrink();
    return _MediaPostCard(
      post: post,
      badge: const MediaBadge(label: 'TV Show', icon: Icons.tv),
      extraInfo: data.seasons != null
          ? '${data.seasons} season${data.seasons! > 1 ? 's' : ''} · ${data.episodes ?? 0} ep'
          : null,
    );
  }
}

class AnimePostWidget extends StatelessWidget {
  final Post post;

  const AnimePostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final data = post.animeData;
    if (data == null) return const SizedBox.shrink();
    return _MediaPostCard(
      post: post,
      badge: const MediaBadge(label: 'Anime', icon: Icons.animation),
      extraInfo: data.episodes != null ? '${data.episodes} ep · ${data.studio ?? ''}' : data.studio,
    );
  }
}

class _MediaPostCard extends StatefulWidget {
  final Post post;
  final Widget badge;
  final String? extraInfo;

  const _MediaPostCard({
    required this.post,
    required this.badge,
    this.extraInfo,
  });

  @override
  State<_MediaPostCard> createState() => _MediaPostCardState();
}

class _MediaPostCardState extends State<_MediaPostCard> {
  bool _expanded = false;

  MediaMetadata get _data {
    final p = widget.post;
    return p.movieData ?? p.tvShowData ?? p.animeData ?? const MediaMetadata(title: '');
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final gold = Theme.of(context).colorScheme.primary;

    return PostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostHeader(
            name: widget.post.user.name,
            handle: widget.post.user.handle,
            verified: widget.post.user.verified,
            timestamp: widget.post.timestamp,
            onAvatarTap: PostHeader.avatarTapHandler(context, widget.post.user),
          ),
          const SizedBox(height: 8),
          Text(widget.post.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),

          // ── Poster + Metadata ──
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => ImagePreview.show(context, data.posterUrl ?? ''),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      data.posterUrl ?? '',
                      width: 100,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 150,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          widget.post.type == PostType.movie ? Icons.movie :
                          widget.post.type == PostType.tvShow ? Icons.tv : Icons.animation,
                          size: 28,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _expanded ? _buildSynopsis(context) : _buildMetadata(context),
                ),
              ],
            ),
          ),

          // ── Genres ──
          if (data.genres.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(children: data.genres.map((g) => GenreChip(label: g)).toList()),
          ],

          // ── More/Less ──
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_expanded ? 'Less' : 'More', style: TextStyle(fontSize: 11, color: gold)),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 14, color: gold),
              ],
            ),
          ),

          const SizedBox(height: 4),
          PostFooter(postId: widget.post.id, badge: widget.badge),
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (data.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(data.subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 4),
        if (data.rating != null) RatingStars(rating: data.rating!),
        const SizedBox(height: 4),
        if (data.director != null) _metaRow(context, Icons.person_outline, data.director!),
        if (data.releaseDate != null) _metaRow(context, Icons.calendar_today_outlined, data.releaseDate!),
        if (data.studio != null) _metaRow(context, Icons.business_outlined, data.studio!),
        if (widget.extraInfo != null) _metaRow(context, Icons.info_outline, widget.extraInfo!),
        if (data.aired != null) _metaRow(context, Icons.play_circle_outline, data.aired!),
      ],
    );
  }

  Widget _buildSynopsis(BuildContext context) {
    return Text(
      _data.synopsis ?? 'No synopsis available.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5, fontSize: 12),
    );
  }

  Widget _metaRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
