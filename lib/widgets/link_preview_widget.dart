import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/link_preview_service.dart';

class LinkPreviewWidget extends StatefulWidget {
  final String url;
  const LinkPreviewWidget({super.key, required this.url});

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget> {
  LinkPreviewData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LinkPreviewService.fetchPreview(widget.url);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  String get _domain {
    try {
      return Uri.parse(widget.url).host.replaceFirst('www.', '');
    } catch (_) {
      return widget.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Container(
        height: 60,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))),
      );
    }

    // Fallback: show a simple tappable link card when preview fetch fails
    if (_data == null) {
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withAlpha(40), width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.link, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _domain,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.open_in_new, color: cs.primary.withAlpha(120), size: 14),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withAlpha(60), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_data!.imageUrl.isNotEmpty)
              SizedBox(
                height: 160,
                width: double.infinity,
                child: Image.network(
                  _data!.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(_platformIcon, color: cs.onSurface.withAlpha(80), size: 32),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_data!.favicon.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Image.network(_data!.favicon, width: 14, height: 14, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _data!.domain,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: cs.onSurface.withAlpha(120)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _platformBadge(cs),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _data!.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_data!.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _data!.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: cs.onSurface.withAlpha(140)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _platformIcon {
    switch (_data!.platform) {
      case 'youtube': return Icons.play_circle_outline;
      case 'tiktok': return Icons.music_note_outlined;
      case 'twitter': return Icons.alternate_email;
      case 'instagram': return Icons.camera_alt_outlined;
      case 'spotify': return Icons.music_note;
      case 'twitch': return Icons.videocam_outlined;
      default: return Icons.language;
    }
  }

  Widget _platformBadge(ColorScheme cs) {
    final colors = {
      'youtube': Colors.red,
      'tiktok': Colors.black,
      'twitter': const Color(0xFF1DA1F2),
      'instagram': const Color(0xFFE4405F),
      'spotify': const Color(0xFF1DB954),
    };
    final color = colors[_data!.platform] ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _data!.platform.toUpperCase(),
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
