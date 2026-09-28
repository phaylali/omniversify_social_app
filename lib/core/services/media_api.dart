import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Unified media API service — talks to the omniversify-api backend.
///
/// Returns parsed JSON as `Map<String, dynamic>` so the UI can render
/// anything the backend provides without hard-coding every field.
class MediaApi {
  MediaApi._();

  /// Read at call time so `.env` load order never sticks on a stale base URL.
  static String get _base => ApiConfig.omniversifyApiUrl;

  // ─── Generic fetcher ──────────────────────────────────────

  static Future<MediaPage> fetch({
    required String category,
    String? search,
    int page = 1,
    int limit = 10,
    bool live = true,
    String? artist,
    String? genre,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'live': '$live',
    };
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }
    if (artist != null && artist.isNotEmpty) {
      params['artist'] = artist;
    }
    if (genre != null && genre.isNotEmpty) {
      params['genre'] = genre;
    }

    final uri =
        Uri.parse('$_base/api/v1/$category').replace(queryParameters: params);
    final resp = await http.get(uri);

    if (resp.statusCode != 200) {
      throw MediaApiException('Failed to load $category: ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    return MediaPage(
      results: results,
      page: json['page'] as int? ?? page,
      total: json['total'] as int? ?? results.length,
      limit: json['limit'] as int? ?? limit,
    );
  }

  /// Fetch a single item by id: `GET /api/v1/{category}/{id}`.
  static Future<Map<String, dynamic>> detail({
    required String category,
    required dynamic id,
  }) async {
    final uri = Uri.parse('$_base/api/v1/$category/$id');
    final resp = await http.get(uri);

    if (resp.statusCode != 200) {
      throw MediaApiException(
          'Failed to load $category/$id: ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body);
    if (json is! Map<String, dynamic>) {
      throw MediaApiException('Unexpected detail payload for $category/$id');
    }
    return json;
  }

  /// Merge title + artist searches for music (API supports both params).
  static Future<MediaPage> searchMusic({
    required String query,
    int page = 1,
    int limit = 9,
  }) async {
    final titlePage = await fetch(
      category: 'music',
      search: query,
      page: page,
      limit: limit,
    );
    MediaPage artistPage;
    try {
      artistPage = await fetch(
        category: 'music',
        artist: query,
        page: page,
        limit: limit,
      );
    } catch (_) {
      artistPage = const MediaPage(results: [], page: 1, total: 0, limit: 9);
    }

    final byId = <dynamic, Map<String, dynamic>>{};
    for (final r in titlePage.results) {
      byId[r['id']] = r;
    }
    for (final r in artistPage.results) {
      byId[r['id']] = r;
    }
    final merged = byId.values.toList();
    // Prefer the larger reported total so See more can keep going.
    final reportedTotal =
        titlePage.total >= artistPage.total ? titlePage.total : artistPage.total;
    return MediaPage(
      results: merged,
      page: page,
      total: reportedTotal > merged.length ? reportedTotal : merged.length,
      limit: limit,
    );
  }

  // ─── Category helpers ─────────────────────────────────────

  static Future<MediaPage> games(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'games', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> movies(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'movies', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> tv(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'tv', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> anime(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'anime', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> books(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'books', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> music(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'music', search: search, page: page, limit: limit, live: live);

  static Future<MediaPage> podcasts(
          {String? search, int page = 1, int limit = 10, bool live = true}) =>
      fetch(category: 'podcasts', search: search, page: page, limit: limit, live: live);
}

/// A single page of results from the backend.
class MediaPage {
  final List<Map<String, dynamic>> results;
  final int page;
  final int total;
  final int limit;

  const MediaPage({
    required this.results,
    required this.page,
    required this.total,
    required this.limit,
  });

  bool get hasMore => page * limit < total;
}

class MediaApiException implements Exception {
  final String message;
  const MediaApiException(this.message);
  @override
  String toString() => message;
}
