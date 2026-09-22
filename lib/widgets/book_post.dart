import 'package:flutter/material.dart';
import '../models/post.dart';
import 'post_components.dart';
import 'image_preview.dart';

class BookPostWidget extends StatefulWidget {
  final Post post;

  const BookPostWidget({super.key, required this.post});

  @override
  State<BookPostWidget> createState() => _BookPostWidgetState();
}

class _BookPostWidgetState extends State<BookPostWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.post.bookData;
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
                  onLongPress: () => ImagePreview.show(context, data.coverUrl ?? ''),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      data.coverUrl ?? '',
                      width: 75,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 75,
                        height: 120,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.book, size: 28),
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

          if (data.genre != null) ...[
            const SizedBox(height: 6),
            GenreChip(label: data.genre!),
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
          PostFooter(postId: widget.post.id, badge: const MediaBadge(label: 'Book', icon: Icons.book)),
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final data = widget.post.bookData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (data.author != null) ...[
          const SizedBox(height: 2),
          Text(data.author!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 4),
        if (data.rating != null) RatingStars(rating: data.rating!, maxRating: 5),
        const SizedBox(height: 4),
        if (data.publishDate != null) _metaRow(context, Icons.calendar_today_outlined, data.publishDate!),
        if (data.pages != null) _metaRow(context, Icons.menu_book_outlined, '${data.pages} pages'),
        if (data.isbn != null) _metaRow(context, Icons.qr_code_outlined, data.isbn!),
      ],
    );
  }

  Widget _buildSynopsis(BuildContext context) {
    final data = widget.post.bookData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
        if (data.author != null) Text(data.author!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        Text(data.synopsis ?? 'No synopsis available.', style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5, fontSize: 12)),
      ],
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
