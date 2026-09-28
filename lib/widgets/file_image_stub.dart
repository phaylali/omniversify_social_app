import 'package:flutter/material.dart';

/// Web stand-in for `file_image.dart` — no local files exist in the browser.
///
/// Call sites should already prefer the bytes path ([Image.memory]) on the
/// web; this just keeps the shared code compiling.
Widget fileImage(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return SizedBox(width: width, height: height);
}
