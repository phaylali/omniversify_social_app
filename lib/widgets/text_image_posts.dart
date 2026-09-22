import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/post.dart';
import 'post_components.dart';
import 'image_preview.dart';
import 'link_preview_widget.dart';

class TextPostWidget extends StatelessWidget {
  final Post post;

  const TextPostWidget({super.key, required this.post});

  List<String> _extractUrls(String text) {
    final urlPattern = RegExp(r'https?://[^\s]+');
    return urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final urls = _extractUrls(post.text);
    final accent = Theme.of(context).colorScheme.primary;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4);

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
          // Rich text with styled, tappable URLs
          _buildRichText(context, post.text, urls, accent, bodyStyle),
          // Link previews below the text
          ...urls.map((url) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinkPreviewWidget(url: url),
          )),
          const SizedBox(height: 8),
          PostFooter(postId: post.id),
        ],
      ),
    );
  }

  Widget _buildRichText(
    BuildContext context,
    String text,
    List<String> urls,
    Color accent,
    TextStyle? bodyStyle,
  ) {
    if (urls.isEmpty) {
      return Text(text, style: bodyStyle);
    }

    // Split text by URLs to build RichText spans
    final spans = <TextSpan>[];
    var remaining = text;

    for (final url in urls) {
      final idx = remaining.indexOf(url);
      if (idx < 0) continue;

      // Text before the URL
      if (idx > 0) {
        spans.add(TextSpan(text: remaining.substring(0, idx), style: bodyStyle));
      }

      // The URL itself — styled with accent color + underline
      spans.add(TextSpan(
        text: url,
        style: bodyStyle?.copyWith(
          color: accent,
          decoration: TextDecoration.underline,
          decorationColor: accent.withAlpha(120),
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));

      remaining = remaining.substring(idx + url.length);
    }

    // Remaining text after last URL
    if (remaining.isNotEmpty) {
      spans.add(TextSpan(text: remaining, style: bodyStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

class ImagePostWidget extends StatelessWidget {
  final Post post;

  const ImagePostWidget({super.key, required this.post});

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
          const SizedBox(height: 8),
          Text(post.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.4)),
          const SizedBox(height: 8),
          GestureDetector(
            onLongPress: () => ImagePreview.show(context, post.imageUrl ?? ''),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                post.imageUrl ?? '',
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.image_outlined, size: 40)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          PostFooter(postId: post.id),
        ],
      ),
    );
  }
}
