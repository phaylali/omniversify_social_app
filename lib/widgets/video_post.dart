import 'package:flutter/material.dart';
import '../models/post.dart';
import '../widgets/post_components.dart';
import '../widgets/video_player.dart';

class VideoPostWidget extends StatelessWidget {
  final Post post;
  const VideoPostWidget({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
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
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(post.text, style: const TextStyle(fontSize: 14)),
            ),
          if (post.videoUrl != null)
            AspectRatio(
              aspectRatio: 9 / 16,
              child: AppVideoPlayer(url: post.videoUrl!, autoPlay: true),
            ),
          PostFooter(postId: post.id),
        ],
      ),
    );
  }
}
