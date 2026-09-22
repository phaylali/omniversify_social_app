import 'package:flutter/material.dart';
import '../models/post.dart';
import 'post_components.dart';
import 'image_preview.dart';

class LocationPostWidget extends StatelessWidget {
  final Post post;

  const LocationPostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final data = post.locationData;
    if (data == null) return const SizedBox.shrink();
    final gold = Theme.of(context).colorScheme.primary;

    return PostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostHeader(
            name: post.user.name,
            handle: post.user.handle,
            verified: post.user.verified,
            timestamp: post.timestamp,
            onAvatarTap: PostHeader.avatarTapHandler(context, post.user),
          ),
          const SizedBox(height: 8),
          Text(post.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),

          GestureDetector(
            onLongPress: () => ImagePreview.show(context, data.imageUrl ?? ''),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
              children: [
                Image.network(
                  data.imageUrl ?? '',
                  width: double.infinity,
                  height: 130,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 130,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.location_on_outlined, size: 36)),
                  ),
                ),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withAlpha(180)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: gold),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                              if (data.city != null || data.country != null)
                                Text(
                                  [data.city, data.country].where((e) => e != null).join(', '),
                                  style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        if (data.rating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 13, color: gold),
                              const SizedBox(width: 2),
                              Text(data.rating!.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w600, fontSize: 12)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),

          if (data.description != null) ...[
            const SizedBox(height: 6),
            Text(data.description!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4, fontSize: 12)),
          ],

          const SizedBox(height: 6),
          PostFooter(postId: post.id, badge: const MediaBadge(label: 'Location', icon: Icons.location_on)),
        ],
      ),
    );
  }
}

class WorkoutPostWidget extends StatelessWidget {
  final Post post;

  const WorkoutPostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final data = post.workoutData;
    if (data == null) return const SizedBox.shrink();
    final gold = Theme.of(context).colorScheme.primary;

    final IconData icon;
    switch (data.type.toLowerCase()) {
      case 'running': icon = Icons.directions_run; break;
      case 'cycling': icon = Icons.directions_bike; break;
      case 'swimming': icon = Icons.pool; break;
      case 'weights': icon = Icons.fitness_center; break;
      default: icon = Icons.sports_martial_arts;
    }

    return PostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostHeader(
            name: post.user.name,
            handle: post.user.handle,
            verified: post.user.verified,
            timestamp: post.timestamp,
            onAvatarTap: PostHeader.avatarTapHandler(context, post.user),
          ),
          const SizedBox(height: 8),
          Text(post.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: gold.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: gold.withAlpha(40), width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: gold.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: gold, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.type, style: TextStyle(fontWeight: FontWeight.w700, color: gold, fontSize: 14)),
                      if (data.intensity != null) Text(data.intensity!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              _statChip(context, Icons.timer_outlined, '${data.durationMinutes ?? 0} min'),
              const SizedBox(width: 6),
              _statChip(context, Icons.local_fire_department_outlined, '${data.calories ?? 0} cal'),
            ],
          ),

          if (data.notes != null) ...[
            const SizedBox(height: 6),
            Text(data.notes!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4, fontSize: 12)),
          ],

          const SizedBox(height: 6),
          PostFooter(postId: post.id, badge: const MediaBadge(label: 'Workout', icon: Icons.fitness_center)),
        ],
      ),
    );
  }

  Widget _statChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
