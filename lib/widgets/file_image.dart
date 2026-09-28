import 'dart:io';
import 'package:flutter/material.dart';

/// Renders a local image file (IO platforms only).
///
/// Swap in `file_image_stub.dart` on the web via conditional import —
/// `dart:io` cannot compile for the browser.
Widget fileImage(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.file(
    File(path),
    fit: fit,
    width: width,
    height: height,
    errorBuilder: errorBuilder,
  );
}
