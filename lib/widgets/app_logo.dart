import 'package:flutter/material.dart';

/// Branded placeholder shown when an image is missing or fails to load.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 48,
    this.fit = BoxFit.contain,
    this.radius,
    this.backgroundColor,
  });

  final double size;
  final BoxFit fit;
  final BorderRadius? radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      'assets/logo/logo.webp',
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (_, __, ___) => Icon(
        Icons.image_not_supported_outlined,
        size: size * 0.6,
        color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
      ),
    );
    if (radius == null && backgroundColor == null) return image;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: radius,
      ),
      child: image,
    );
  }
}
