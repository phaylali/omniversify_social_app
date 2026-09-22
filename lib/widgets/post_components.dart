import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post.dart';
import '../data/post_state.dart';
import 'post_interaction_panel.dart';

class PostHeader extends StatelessWidget {
  final String name;
  final String handle;
  final bool verified;
  final DateTime timestamp;
  final VoidCallback? onAvatarTap;

  const PostHeader({
    super.key,
    required this.name,
    required this.handle,
    this.verified = false,
    required this.timestamp,
    this.onAvatarTap,
  });

  static VoidCallback avatarTapHandler(BuildContext context, PostUser user) {
    return () {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfileViewScreen(user: user),
      ));
    };
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: gold.withAlpha(40),
            child: Text(
              name[0].toUpperCase(),
              style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (verified) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.verified, size: 14, color: gold),
                  ],
                ],
              ),
              Text('$handle · ${_timeAgo(timestamp)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
            ],
          ),
        ),
        // Three dots menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz, size: 20, color: Theme.of(context).textTheme.bodySmall?.color),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onSelected: (value) {
            if (value == 'copy_link') {
              Clipboard.setData(ClipboardData(text: 'https://app.omniversify.com/post/${name.toLowerCase()}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: Colors.red), SizedBox(width: 8), Text('Report', style: TextStyle(color: Colors.red))])),
            const PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, size: 18, color: Colors.red), SizedBox(width: 8), Text('Block', style: TextStyle(color: Colors.red))])),
            const PopupMenuItem(value: 'mute', child: Row(children: [Icon(Icons.volume_off_outlined, size: 18), SizedBox(width: 8), Text('Mute')])),
            const PopupMenuItem(value: 'copy_link', child: Row(children: [Icon(Icons.link, size: 18), SizedBox(width: 8), Text('Copy link')])),
          ],
        ),
      ],
    );
  }
}

class PostFooter extends ConsumerWidget {
  final String postId;
  final Widget? badge;

  const PostFooter({super.key, required this.postId, this.badge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postStateProvider)[postId];
    if (state == null) return const SizedBox.shrink();

    return Row(
      children: [
        // ── Like icon ──
        GestureDetector(
          onTap: () => ref.read(postStateProvider.notifier).toggleLike(postId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(
              state.liked ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: state.liked ? Colors.red : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),

        // ── Like count ──
        GestureDetector(
          onTap: () => PostInteractionPanel.show(context, postId, initialTab: 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '${state.likes}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: state.liked ? Colors.red : Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // ── Comment icon ──
        GestureDetector(
          onTap: () => PostInteractionPanel.show(context, postId, initialTab: 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(Icons.chat_bubble_outline, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
          ),
        ),

        // ── Comment count ──
        GestureDetector(
          onTap: () => PostInteractionPanel.show(context, postId, initialTab: 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('${state.comments}', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
          ),
        ),

        const SizedBox(width: 8),

        // ── Share icon ──
        GestureDetector(
          onTap: () => ref.read(postStateProvider.notifier).share(postId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(Icons.share_outlined, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
          ),
        ),

        // ── Share count ──
        GestureDetector(
          onTap: () => PostInteractionPanel.show(context, postId, initialTab: 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('${state.shares}', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
          ),
        ),

        const SizedBox(width: 8),

        // ── Save ──
        GestureDetector(
          onTap: () => ref.read(postStateProvider.notifier).toggleBookmark(postId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(
              state.saved ? Icons.bookmark : Icons.bookmark_border,
              size: 20,
              color: state.saved ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),

        // ── Badge (right-aligned) ──
        const Spacer(),
        if (badge != null) badge!,
      ],
    );
  }
}

class PostCard extends StatelessWidget {
  final Widget child;

  const PostCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
        Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor),
      ],
    );
  }
}

class MediaBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const MediaBadge({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: gold.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gold.withAlpha(60), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: gold),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: gold, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  final double rating;
  final double maxRating;
  final double size;

  const RatingStars({super.key, required this.rating, this.maxRating = 10, this.size = 13});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: size, color: gold),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: size - 2, color: gold, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class GenreChip extends StatelessWidget {
  final String label;

  const GenreChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
    );
  }
}

class PlatformChip extends StatelessWidget {
  final String label;

  const PlatformChip({super.key, required this.label});

  static Color _colorFor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('pc') || p.contains('windows') || p.contains('steam')) {
      return const Color(0xFF6C8CFF); // PC blue
    }
    if (p.contains('playstation') || p == 'ps5' || p == 'ps4') {
      return const Color(0xFF2E6FD9); // PlayStation blue lighter
    }
    if (p.contains('xbox')) {
      return const Color(0xFF107C10); // Xbox green
    }
    if (p.contains('nintendo') || p.contains('switch')) {
      return const Color(0xFFE60012); // Nintendo red
    }
    if (p.contains('mac') || p.contains('apple')) {
      return const Color(0xFF999999); // Apple gray
    }
    if (p.contains('mobile') || p.contains('ios') || p.contains('android')) {
      return const Color(0xFF6C63FF); // Mobile purple
    }
    return const Color(0xFF999999);
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
