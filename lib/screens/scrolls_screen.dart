import 'package:flutter/material.dart';
import '../widgets/video_player.dart';

class ScrollItem {
  final String username;
  final String caption;
  final int likes;
  final int comments;
  final String? videoUrl;
  final String? imageUrl;

  const ScrollItem({
    required this.username,
    required this.caption,
    this.likes = 0,
    this.comments = 0,
    this.videoUrl,
    this.imageUrl,
  });
}

final List<ScrollItem> _scrollItems = [
  const ScrollItem(
    username: '@youssef_ma',
    caption: 'Sunset timelapse from the rooftop #goldenhour # Morocco',
    likes: 2400,
    comments: 186,
    imageUrl: 'https://picsum.photos/seed/scroll0/1080/1920',
  ),
  const ScrollItem(
    username: '@amina_stream',
    caption: 'Elden Ring DLC boss fight was insane #gaming #eldenring',
    likes: 5200,
    comments: 412,
    videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  ),
  const ScrollItem(
    username: '@omar_gamer',
    caption: 'Cooking tagine with grandma #moroccanfood #homemade',
    likes: 1800,
    comments: 94,
    imageUrl: 'https://picsum.photos/seed/scroll2/1080/1920',
  ),
  const ScrollItem(
    username: '@fatima_otaku',
    caption: 'Attack on Titan OST on the piano #anime #music',
    likes: 8900,
    comments: 623,
    videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  ),
  const ScrollItem(
    username: '@karim_photo',
    caption: 'Streets of Chefchaouen #travel #bluecity',
    likes: 3100,
    comments: 215,
    imageUrl: 'https://picsum.photos/seed/scroll4/1080/1920',
  ),
  const ScrollItem(
    username: '@sara_fitness',
    caption: 'Morning workout routine #fitness #gym',
    likes: 4500,
    comments: 328,
    videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
  ),
  const ScrollItem(
    username: '@youssef_ma',
    caption: 'The Hassan II Mosque at night #casablanca #architecture',
    likes: 7200,
    comments: 489,
    imageUrl: 'https://picsum.photos/seed/scroll6/1080/1920',
  ),
];

class ScrollsScreen extends StatefulWidget {
  const ScrollsScreen({super.key});

  @override
  State<ScrollsScreen> createState() => _ScrollsScreenState();
}

class _ScrollsScreenState extends State<ScrollsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _arrowController;
  late Animation<Offset> _arrowAnimation;
  bool _showArrow = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _arrowAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _arrowController, curve: Curves.easeOut));

    _arrowController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _showArrow) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _showArrow) _arrowController.reverse(from: 0.0);
        });
      }
      if (status == AnimationStatus.dismissed && _showArrow) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _showArrow) _arrowController.forward();
        });
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _arrowController.forward();
    });
  }

  @override
  void dispose() {
    _arrowController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_showArrow) {
      setState(() => _showArrow = false);
      _arrowController.stop();
    }
    setState(() => _currentIndex = index);
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: _scrollItems.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            final item = _scrollItems[index];
            final isActive = index == _currentIndex;

            return Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video or image background
                  if (item.videoUrl != null)
                    ScrollVideoPlayer(url: item.videoUrl!, isActive: isActive)
                  else
                    Image.network(
                      item.imageUrl ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: gold.withAlpha(120),
                            strokeWidth: 2,
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.movie_filter, size: 64, color: gold.withAlpha(80)),
                      ),
                    ),

                  // Gradient overlay for readability
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    height: 280,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withAlpha(180)],
                        ),
                      ),
                    ),
                  ),

                  // Right side action buttons
                  Positioned(
                    right: 12,
                    bottom: 120,
                    child: Column(
                      children: [
                        _actionButton(context, Icons.add_circle_outline, 'Create'),
                        const SizedBox(height: 20),
                        _actionButton(context, Icons.favorite_border, _formatCount(item.likes)),
                        const SizedBox(height: 20),
                        _actionButton(context, Icons.chat_bubble_outline, _formatCount(item.comments)),
                        const SizedBox(height: 20),
                        _actionButton(context, Icons.share_outlined, 'Share'),
                        const SizedBox(height: 20),
                        _actionButton(context, Icons.bookmark_border, 'Save'),
                      ],
                    ),
                  ),

                  // Bottom user info
                  Positioned(
                    left: 16,
                    bottom: 16,
                    right: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: gold.withAlpha(40),
                              child: Text(
                                item.username[1].toUpperCase(),
                                style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.username,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white.withAlpha(100), width: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Follow', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.caption,
                          style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Video indicator
                  if (item.videoUrl != null)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, color: Colors.white70, size: 14),
                            SizedBox(width: 4),
                            Text('VIDEO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        // Animated scroll indicator
        if (_showArrow)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _arrowAnimation,
              child: FadeTransition(
                opacity: _arrowController,
                child: const Center(
                  child: Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 28),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11)),
      ],
    );
  }
}
