import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post.dart';
import '../data/post_state.dart';
import '../data/dummy_data.dart';
import '../core/config/api_config.dart';
import '../services/mute_service.dart';
import 'action_sheet.dart';
import 'post_interaction_panel.dart';
import 'share_sheet.dart';

/// Compact relative time for comment rows: `now`, `2m`, `2h`, `5d`, `3w`, `4mo`, `4y`.
String compactAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
  return '${diff.inDays ~/ 365}y';
}

class PostHeader extends StatelessWidget {
  final String name;
  final String handle;
  final bool verified;
  final DateTime timestamp;
  final PostVisibility visibility;
  final VoidCallback? onAvatarTap;

  const PostHeader({
    super.key,
    required this.name,
    required this.handle,
    this.verified = false,
    required this.timestamp,
    this.visibility = PostVisibility.public,
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
                  Text(name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.5)),
                  if (verified) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.verified, size: 14, color: gold),
                  ],
                  if (visibility == PostVisibility.private) ...[
                    const SizedBox(width: 5),
                    // Privacy indicator — private posts are never shareable.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 11, color: Theme.of(context).textTheme.bodySmall?.color),
                          const SizedBox(width: 3),
                          Text(
                            'Private',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Text('$handle · ${_timeAgo(timestamp)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
            ],
          ),
        ),
        // Three dots menu — the same sheet the scrolls menu opens.
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.more_horiz, size: 20, color: Theme.of(context).textTheme.bodySmall?.color),
          onPressed: () => _showMenu(context),
        ),
      ],
    );
  }

  /// Report the account, report the post, mute, block or copy the link —
  /// laid out exactly like the scrolls `⋮` menu.
  void _showMenu(BuildContext context) {
    showActionSheet(
      context,
      title: name,
      subtitle: handle,
      items: [
        ActionSheetItem(
          icon: Icons.flag_outlined,
          title: 'Report user',
          subtitle: 'Tell us about $handle',
          onTap: () =>
              showActionNotice(context, 'Thanks — your report about $handle is in review'),
        ),
        ActionSheetItem(
          icon: Icons.report_outlined,
          title: 'Report content',
          subtitle: 'Tell us about this post',
          onTap: () => showActionNotice(context, 'Thanks — your report about this post is in review'),
        ),
        ActionSheetItem(
          icon: Icons.volume_off_outlined,
          title: 'Mute',
          subtitle: 'Hide $handle\'s posts for now',
          onTap: () => _hide(context, '$handle muted'),
        ),
        ActionSheetItem(
          icon: Icons.block,
          title: 'Block',
          subtitle: 'Stop seeing $handle anywhere',
          tone: ActionSheetTone.destructive,
          onTap: () => _hide(context, '$handle blocked'),
        ),
        ActionSheetItem(
          icon: Icons.link,
          title: 'Copy link',
          subtitle: 'Copy a link to this post',
          onTap: () {
            Clipboard.setData(ClipboardData(
                text: '${ApiConfig.omniversifyAppUrl}/post/${name.toLowerCase()}'));
            showActionNotice(context, 'Link copied to clipboard');
          },
        ),
      ],
    );
  }

  /// Hides the author everywhere — feed, stories and scrolls — until the
  /// player undoes it or the app restarts.
  void _hide(BuildContext context, String message) {
    MuteService.instance.mute(handle);
    showActionNotice(
      context,
      message,
      undoLabel: 'UNDO',
      onUndo: () => MuteService.instance.unmute(handle),
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

    // Private posts expose no working share action — the icon becomes a lock.
    final canShare = state.visibility == PostVisibility.public;

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
          onTap: canShare
              ? () {
                  final post = dummyPosts.where((p) => p.id == postId).firstOrNull;
                  ShareSheet.show(
                    context,
                    shareText: post != null
                        ? postShareText(post.user.name, post.user.handle, post.text)
                        : 'Check out this post',
                    onShared: () => ref.read(postStateProvider.notifier).share(postId),
                  );
                }
              : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sharing is off for private posts'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(
              canShare ? Icons.share_outlined : Icons.lock_outline,
              size: 18,
              color: canShare
                  ? Theme.of(context).textTheme.bodySmall?.color
                  : Theme.of(context).textTheme.bodySmall?.color?.withAlpha(110),
            ),
          ),
        ),

        // ── Share count (public posts only) ──
        if (canShare)
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
