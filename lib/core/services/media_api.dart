import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Unified media API service — talks to the omniversify-api backend.
///
/// Returns parsed JSON as `Map<String, dynamic>` so the UI can render
/// anything the backend provides without hard-coding every field.
class MediaApi {
  MediaApi._();

  static final _base = ApiConfig.omniversifyApiUrl;

  // ─── Generic fetcher ──────────────────────────────────────

  static Future<MediaPage> fetch({
    required String category,
    String? search,
    int page = 1,
    int limit = 10,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }

    final uri = Uri.parse('$_base/api/v1/$category').replace(queryParameters: params);
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

  // ─── Category helpers ─────────────────────────────────────

  static Future<MediaPage> games({String? search, int page = 1, int limit = 10}) =>
      fetch(category: 'games', search: search, page: page, limit: limit);

  static Future<MediaPage> movies({String? search, int page = 1, int limit = 10}) =>
      fetch(category: 'movies', search: search, page: page, limit: limit);

  static Future<MediaPage> tv({String? search, int page = 1, int limit = 10}) =>
      fetch(category: 'tv', search: search, page: page, limit: limit);

  static Future<MediaPage> anime({String? search, int page = 1, int limit = 10}) =>
      fetch(category: 'anime', search: search, page: page, limit: limit);

  static Future<MediaPage> books({String? search, int page = 1, int limit = 10}) =>
      fetch(category: 'books', search: search, page: page, limit: limit);
}

/// A single page of results from the backend.
class MediaPage {
  final List<Map<String, dynamic>> results;
  final int page;
  final int total;
  final int limit;

  const MediaPage({required this.results, required this.page, required this.total, required this.limit});

  bool get hasMore => page * limit < total;
}

class MediaApiException implements Exception {
  final String message;
  const MediaApiException(this.message);
  @override
  String toString() => message;
}
