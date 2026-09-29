import 'package:flutter/material.dart';
import '../data/dummy_data.dart';
import '../models/post.dart';
import '../services/mute_service.dart';
import '../screens/story_viewer_screen.dart';

/// Instagram-style story avatars shown at the top of the home feed.
class StoriesRow extends StatelessWidget {
  const StoriesRow({super.key});

  List<PostUser> _uniqueUsers() {
    final seen = <String>{};
    final users = <PostUser>[];
    for (final post in dummyPosts) {
      if (seen.add(post.user.handle)) users.add(post.user);
    }
    return users;
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 104,
      child: ValueListenableBuilder<Set<String>>(
        // Muted accounts lose their story bubble along with everything else.
        valueListenable: MuteService.instance.muted,
        builder: (context, muted, _) {
          final users = [
            for (final user in _uniqueUsers())
              if (!muted.contains(user.handle)) user,
          ];

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: users.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _YourStory(gold: gold);
              final user = users[index - 1];
              return _StoryBubble(
                user: user,
                gold: gold,
                // Stories are still placeholders — this opens the viewer.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StoryViewerScreen(
                      users: users,
                      initialIndex: index - 1,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _YourStory extends StatelessWidget {
  const _YourStory({required this.gold});

  final Color gold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _ring(
                gold: gold,
                gap: cs.surface,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: gold.withAlpha(30),
                  child: Text(
                    currentUser.name[0].toUpperCase(),
                    style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                  child: Icon(Icons.add, size: 14, color: gold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 62,
            child: Text(
              'Your story',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(170)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.user, required this.gold, this.onTap});

  final PostUser user;
  final Color gold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          _ring(
            gold: gold,
            gap: Theme.of(context).colorScheme.surface,
            child: CircleAvatar(
              radius: 26,
              backgroundColor: gold.withAlpha(30),
              child: Text(
                user.name[0].toUpperCase(),
                style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 62,
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(170)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Gradient ring with a surface-colored gap, like Instagram story borders.
Widget _ring({required Color gold, required Color gap, required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gold, gold.withAlpha(90), gold],
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: gap,
      ),
      child: child,
    ),
  );
}
