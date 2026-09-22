import 'dart:convert';
import 'package:http/http.dart' as http;

class LinkPreviewService {
  LinkPreviewService._();

  static final _urlRegex = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static List<String> extractUrls(String text) {
    return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static String? detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com/watch') || u.contains('youtu.be/') || u.contains('youtube.com/shorts/')) return 'youtube';
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
      if (platform == 'youtube') return _fetchYouTube(url);
      if (platform == 'twitter') return _fetchTwitter(url);
      if (platform == 'tiktok') return _fetchGeneric(url);
      return _fetchGeneric(url);
    } catch (_) {
      return null;
    }
  }

  static Future<LinkPreviewData?> _fetchYouTube(String url) async {
    final videoId = _extractYouTubeId(url);
    if (videoId == null) return _fetchGeneric(url);

    try {
      final oembedResp = await http.get(
        Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json'),
      ).timeout(const Duration(seconds: 5));

      if (oembedResp.statusCode == 200) {
        final data = jsonDecode(oembedResp.body);
        return LinkPreviewData(
          url: url,
          title: data['title'] ?? '',
          description: data['author_name'] ?? '',
          imageUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
          platform: 'youtube',
          favicon: 'https://www.youtube.com/favicon.ico',
        );
      }
    } catch (_) {}
    return _fetchGeneric(url);
  }

  static String? _extractYouTubeId(String url) {
    final regExp = RegExp(r'(?:youtube\.com/(?:watch\?.*v=|shorts/|embed/)|youtu\.be/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  static Future<LinkPreviewData?> _fetchTwitter(String url) async {
    return _fetchGeneric(url);
  }

  static Future<LinkPreviewData?> _fetchGeneric(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; OmniversifyBot/1.0)',
        'Accept': 'text/html',
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

  static String? _extractMeta(String html, String property) {
    final escaped = RegExp.escape(property);
    final q = '["\u2018\u2019]';
    final qAttr = '["\u2018\u2019]';
    final patterns = [
      '<meta\\s+(?:[^>]*?)property=$q$escaped$q(?:[^>]*?)content=$q([^"$q]+)$q',
      '<meta\\s+(?:[^>]*?)content=$q([^"$q]+)$q(?:[^>]*?)property=$q$escaped$q',
      '<meta\\s+(?:[^>]*?)name=$q$escaped$q(?:[^>]*?)content=$q([^"$q]+)$q',
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
    final q = '["\u2018\u2019]';
    final m = RegExp('<link[^>]+rel=$q[^"$q]*icon[^"$q]*$q[^>]+href=$q([^"$q]+)$q', caseSensitive: false).firstMatch(html);
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
  final String platform;
  final String favicon;

  const LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
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
