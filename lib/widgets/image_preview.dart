import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_logo.dart';
import 'file_image_stub.dart'
    if (dart.library.io) 'file_image.dart';

class ImagePreview extends StatefulWidget {
  final String imageUrl;
  final String? imageFile;
  final Uint8List? imageBytes;
  final String? heroTag;

  const ImagePreview({super.key, required this.imageUrl, this.imageFile, this.imageBytes, this.heroTag});

  static void show(BuildContext context, String imageUrl, {String? heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => ImagePreview(imageUrl: imageUrl, heroTag: heroTag),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Full-screen preview for a local image file (e.g. a comment attachment).
  static void showFile(BuildContext context, String filePath, {String? heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, _, _) => ImagePreview(imageUrl: filePath, imageFile: filePath, heroTag: heroTag),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Full-screen preview for raw bytes (e.g. an image picked on web).
  static void showMemory(BuildContext context, Uint8List bytes, {String? heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, _, _) => ImagePreview(imageUrl: '', imageBytes: bytes, heroTag: heroTag),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
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
                child: widget.imageBytes != null
                      ? Image.memory(
                          widget.imageBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const AppLogo(size: 80, fit: BoxFit.contain),
                        )
                    : widget.imageFile != null
                        ? fileImage(
                            widget.imageFile!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const AppLogo(size: 80, fit: BoxFit.contain),
                          )
                        : Image.network(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const AppLogo(size: 80, fit: BoxFit.contain),
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
