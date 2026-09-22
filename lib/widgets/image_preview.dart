import 'dart:ui';
import 'package:flutter/material.dart';

class ImagePreview extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const ImagePreview({super.key, required this.imageUrl, this.heroTag});

  static void show(BuildContext context, String imageUrl, {String? heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => ImagePreview(imageUrl: imageUrl, heroTag: heroTag),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black38),
            ),

            // Zoomable image
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Hero(
                  tag: widget.heroTag ?? widget.imageUrl,
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  ),
                ),
              ),
            ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Hint
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0, right: 0,
              child: Center(
                child: Text(
                  'Pinch to zoom · Tap to close',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
