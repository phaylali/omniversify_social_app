import 'dart:convert';
import 'package:http/http.dart' as http;

class LinkPreviewService {
  LinkPreviewService._();

  /// Swapped for a fake in tests.
  static http.Client client = http.Client();

  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static List<String> extractUrls(String text) {
    return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static String? detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com/watch') ||
        u.contains('youtube.com/live/') ||
        u.contains('youtu.be/') ||
        u.contains('youtube.com/shorts/')) {
      return 'youtube';
    }
    if (u.contains('tiktok.com')) return 'tiktok';
    if (u.contains('twitter.com/') || u.contains('x.com/')) return 'twitter';
    if (u.contains('instagram.com/')) return 'instagram';
    if (u.contains('spotify.com/')) return 'spotify';
    if (u.contains('twitch.tv/')) return 'twitch';
    if (u.contains('vimeo.com/')) return 'vimeo';
    if (u.contains('reddit.com/')) return 'reddit';
    return null;
  }

  static Future<LinkPreviewData?> fetchPreview(String url) async {
    try {
      final platform = detectPlatform(url);
      if (platform == 'youtube') return await _fetchYouTube(url);
      if (platform == 'twitter') return await _fetchTwitter(url);
      return await _fetchGeneric(url);
    } catch (_) {
      return null;
    }
  }

  static Future<LinkPreviewData?> _fetchYouTube(String url) async {
    final videoId = _extractYouTubeId(url);
    if (videoId == null) return _fetchGeneric(url);

    try {
      final oembedResp = await client.get(
        Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json'),
      ).timeout(const Duration(seconds: 5));

      if (oembedResp.statusCode == 200) {
        final data = jsonDecode(oembedResp.body);
        return LinkPreviewData(
          url: url,
          title: data['title'] ?? '',
          description: data['author_name'] ?? '',
          imageUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
          // Only some videos keep the big frame. The small one exists for
          // every video ever made, so it stands in when that one is empty.
          fallbackImageUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
          platform: 'youtube',
          favicon: 'https://www.youtube.com/favicon.ico',
        );
      }
    } catch (_) {}
    return _fetchGeneric(url);
  }

  static String? _extractYouTubeId(String url) {
    final regExp = RegExp(r'(?:youtube\.com/(?:watch\?.*v=|shorts/|embed/|live/)|youtu\.be/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  static Future<LinkPreviewData?> _fetchTwitter(String url) async {
    return _fetchGeneric(url);
  }

  static Future<LinkPreviewData?> _fetchGeneric(String url) async {
    try {
      // A plain browser, not a bot: sites like Instagram only hand over
      // their open graph tags to something that looks like a reader.
      final resp = await client.get(Uri.parse(url), headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final html = resp.body;
      final title = _extractMeta(html, 'og:title') ?? _extractTag(html, 'title') ?? '';
      final description = _extractMeta(html, 'og:description') ?? _extractMeta(html, 'description') ?? '';
      final imageUrl = _extractMeta(html, 'og:image') ?? _extractMeta(html, 'twitter:image') ?? '';
      final favicon = _extractFavicon(html, url);

      if (title.isEmpty && imageUrl.isEmpty) return null;

      return LinkPreviewData(
        url: url,
        title: title,
        description: description.length > 200 ? '${description.substring(0, 197)}...' : description,
        imageUrl: imageUrl,
        platform: detectPlatform(url) ?? 'web',
        favicon: favicon,
      );
    } catch (_) {
      return null;
    }
  }

  /// An attribute value, wrapped in straight or curly quotes.
  static const _quote = '["\u2018\u2019]';

  /// Anything but a closing quote. A class of its own: splicing a whole
  /// class into a pattern drags the bracket that closed it along, which
  /// quietly breaks everything it is spliced into.
  static const _notQuote = '[^"\u2018\u2019]';

  static String? _extractMeta(String html, String property) {
    final escaped = RegExp.escape(property);
    final patterns = [
      '<meta\\s+(?:[^>]*?)property=$_quote$escaped$_quote(?:[^>]*?)content=$_quote($_notQuote+)$_quote',
      '<meta\\s+(?:[^>]*?)content=$_quote($_notQuote+)$_quote(?:[^>]*?)property=$_quote$escaped$_quote',
      '<meta\\s+(?:[^>]*?)name=$_quote$escaped$_quote(?:[^>]*?)content=$_quote($_notQuote+)$_quote',
    ];
    for (final pattern in patterns) {
      final m = RegExp(pattern, caseSensitive: false).firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _extractTag(String html, String tag) {
    final m = RegExp('<$tag[^>]*>([^<]+)</$tag>', caseSensitive: false).firstMatch(html);
    return m?.group(1)?.trim();
  }

  static String _extractFavicon(String html, String baseUrl) {
    final m = RegExp(
      '<link[^>]+rel=$_quote$_notQuote*icon$_notQuote*$_quote[^>]+href=$_quote($_notQuote+)$_quote',
      caseSensitive: false,
    ).firstMatch(html);
    if (m != null) {
      final href = m.group(1)!;
      if (href.startsWith('http')) return href;
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$href';
    }
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.host}/favicon.ico';
  }
}

class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String imageUrl;
  final String? fallbackImageUrl;
  final String platform;
  final String favicon;

  const LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
    this.fallbackImageUrl,
    required this.platform,
    required this.favicon,
  });

  String get domain {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}
