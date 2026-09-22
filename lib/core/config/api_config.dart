import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Centralized API key configuration.
/// Keys are loaded from `.env` via `flutter_dotenv`.
///
/// Usage:
/// ```dart
/// final key = ApiConfig.rawgApiKey;
/// final igdbToken = await ApiConfig.getIgdbAccessToken();
/// ```
///
/// To add a new API key:
/// 1. Add it to `.env`: `NEW_API_KEY=your_key_here`
/// 2. Add a getter here: `static String get newApiKey => _get('NEW_API_KEY');`
/// 3. Add a placeholder to `.env.example`

class ApiConfig {
  ApiConfig._();

  // ─── .env loader (runs at app start) ───────────────────────
  static bool _loaded = false;

  /// Must be called once before `runApp()`.
  /// Uses `flutter_dotenv` to load `.env` from assets.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      await dotenv.load();
      _loaded = true;
    } catch (_) {
      // .env not found or failed — keys will be empty strings.
    }
  }

  static String _get(String key) => dotenv.env[key] ?? '';

  // ─── Omniversify Unified API ───────────────────────────────

  /// Backend API URL — defaults to localhost for development.
  static String get omniversifyApiUrl => _get('OMNIVERSIFY_API_URL').isEmpty
      ? 'http://localhost:8000'
      : _get('OMNIVERSIFY_API_URL');

  // ─── RAWG (Games) ──────────────────────────────────────────

  /// RAWG Video Games Database
  /// Free tier: 20,000 requests/month
  /// Docs: https://api.rawg.io/apidocs
  static String get rawgApiKey => _get('RAWG_API_KEY');

  static String get rawgBaseUrl => _get('RAWG_BASE_URL').isEmpty
      ? 'https://api.rawg.io/api'
      : _get('RAWG_BASE_URL');

  // ─── IGDB (Games) ─────────────────────────────────────────

  /// IGDB — Internet Games Database (via Twitch OAuth)
  /// More detailed than RAWG: themes, game modes, involved companies
  /// Register app: https://dev.twitch.tv/console/apps
  static String get igdbClientId => _get('IGDB_CLIENT_ID');

  static String get igdbClientSecret => _get('IGDB_CLIENT_SECRET');

  static String get igdbBaseUrl => _get('IGDB_BASE_URL').isEmpty
      ? 'https://api.igdb.com/v4'
      : _get('IGDB_BASE_URL');

  /// Cached IGDB access token
  static String? _igdbAccessToken;
  static DateTime? _igdbTokenExpiry;

  /// Get an IGDB access token via Twitch OAuth2 client credentials flow.
  /// Tokens are cached for ~60 days (Twitch tokens last 60 days).
  static Future<String?> getIgdbAccessToken() async {
    // Return cached token if still valid
    if (_igdbAccessToken != null &&
        _igdbTokenExpiry != null &&
        DateTime.now().isBefore(_igdbTokenExpiry!)) {
      return _igdbAccessToken;
    }

    if (igdbClientId.isEmpty || igdbClientSecret.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('https://id.twitch.tv/oauth2/token'),
        body: {
          'client_id': igdbClientId,
          'client_secret': igdbClientSecret,
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _igdbAccessToken = data['access_token'];
        // Cache for slightly less than the expires_in duration
        final expiresIn = (data['expires_in'] as int?) ?? 5184000;
        _igdbTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 3600));
        return _igdbAccessToken;
      }
    } catch (_) {}
    return null;
  }

  /// Check if IGDB is fully configured (client ID + secret present)
  static bool get igdbConfigured =>
      igdbClientId.isNotEmpty && igdbClientSecret.isNotEmpty;

  // ─── TMDB (Movies & TV) ───────────────────────────────────

  /// The Movie Database (TMDB)
  /// Free for non-commercial use, attribution required
  /// Register: https://www.themoviedb.org/settings/api
  static String get tmdbApiKey => _get('TMDB_API_KEY');

  static String get tmdbReadAccessToken => _get('TMDB_READ_ACCESS_TOKEN');

  static String get tmdbBaseUrl => _get('TMDB_BASE_URL').isEmpty
      ? 'https://api.themoviedb.org/3'
      : _get('TMDB_BASE_URL');

  static String get tmdbImageBaseUrl => 'https://image.tmdb.org/t/p';

  // ─── Jikan (Anime & Manga) ────────────────────────────────

  /// Jikan — unofficial MyAnimeList API
  /// No key needed, rate limit: 3 requests/second
  /// Docs: https://docs.api.jikan.moe/
  static String get jikanBaseUrl => _get('JIKAN_BASE_URL').isEmpty
      ? 'https://api.jikan.moe/v4'
      : _get('JIKAN_BASE_URL');

  // ─── Open Library (Books) ──────────────────────────────────

  /// Open Library — free, no key needed
  /// Rate limit: 3 req/sec with User-Agent header
  /// Docs: https://openlibrary.org/developers/api
  static String get openLibraryBaseUrl => _get('OPEN_LIBRARY_BASE_URL').isEmpty
      ? 'https://openlibrary.org/api'
      : _get('OPEN_LIBRARY_BASE_URL');

  // ─── Omniversify Sub-Services ──────────────────────────────

  /// Moroccan triple-date API (Gregorian / Islamic / Amazigh)
  static String get moroccoDateApiUrl => _get('MOROCCO_DATE_API_URL').isEmpty
      ? 'https://morocco-date-api.omniversify.com/api'
      : _get('MOROCCO_DATE_API_URL');

  /// Tifinagh transliteration & dictionary API
  static String get tifinaghApiUrl => _get('TIFINAGH_API_URL').isEmpty
      ? 'https://omniversify-tifinagh-dictionary-api.omniversify.com'
      : _get('TIFINAGH_API_URL');

  /// Omniversify app frontend base URL (for share links)
  static String get omniversifyAppUrl => _get('OMNIVERSIFY_APP_URL').isEmpty
      ? 'https://app.omniversify.com'
      : _get('OMNIVERSIFY_APP_URL');

  // ─── Helpers ───────────────────────────────────────────────

  /// Check if a required API key is configured
  static bool isKeyAvailable(String key) => _get(key).isNotEmpty;

  /// Get all configured API providers (for settings/debug)
  static Map<String, bool> get configuredProviders => {
        'RAWG (Games)': rawgApiKey.isNotEmpty,
        'IGDB (Games)': igdbConfigured,
        'TMDB (Movies/TV)': tmdbApiKey.isNotEmpty || tmdbReadAccessToken.isNotEmpty,
        'Jikan (Anime)': true, // no key needed
        'Open Library (Books)': true, // no key needed
      };
}
