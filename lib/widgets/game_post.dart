import 'package:flutter/material.dart';
import '../models/post.dart';
import 'post_components.dart';
import 'image_preview.dart';

class GamePostWidget extends StatefulWidget {
  final Post post;

  const GamePostWidget({super.key, required this.post});

  @override
  State<GamePostWidget> createState() => _GamePostWidgetState();
}

class _GamePostWidgetState extends State<GamePostWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.post.gameData;
    if (data == null) return const SizedBox.shrink();
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
                        child: const Icon(Icons.sports_esports, size: 28),
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

          if (data.platforms.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 3, children: data.platforms.map((p) => PlatformChip(label: p)).toList()),
          ],
          if (data.genres.isNotEmpty) ...[
            const SizedBox(height: 3),
            Wrap(children: data.genres.map((g) => GenreChip(label: g)).toList()),
          ],

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
          PostFooter(postId: widget.post.id, badge: const MediaBadge(label: 'Game', icon: Icons.sports_esports)),
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final data = widget.post.gameData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        if (data.rating != null) RatingStars(rating: data.rating!),
        const SizedBox(height: 4),
        if (data.developer != null) _metaRow(context, Icons.business_outlined, data.developer!),
        if (data.publisher != null) _metaRow(context, Icons.publish_outlined, data.publisher!),
        if (data.releaseDate != null) _metaRow(context, Icons.calendar_today_outlined, data.releaseDate!),
        if (data.playtime != null) _metaRow(context, Icons.timer_outlined, '${data.playtime}h played'),
      ],
    );
  }

  Widget _buildSynopsis(BuildContext context) {
    return Text(widget.post.gameData!.synopsis ?? 'No description available.', style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5, fontSize: 12));
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
