import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Something the backend refused, in words meant for a person.
class AuthException implements Exception {
  const AuthException(this.message, {this.code, this.status});

  final String message;

  /// Machine-readable reason when the server sent one, e.g.
  /// `needs_verification` from a login that still has to confirm its email.
  final String? code;

  /// HTTP status when the server answered; null when it never did (offline).
  final int? status;

  @override
  String toString() => message;
}

/// One signed-in person, as the backend describes them.
class Account {
  const Account({
    required this.id,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.createdAt,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool emailVerified;
  final String? createdAt;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        displayName: json['display_name'] as String?,
        emailVerified: json['email_verified'] as bool? ?? false,
        createdAt: json['created_at'] as String?,
      );
}

/// A session the backend handed out: the bearer token plus who it belongs to.
class AuthSession {
  const AuthSession({required this.token, required this.account});

  final String token;
  final Account account;
}

/// The account API — sign up, confirm an email with a six-digit code, sign in.
///
/// Talks to `/api/v1/auth` on the same backend as everything else; the live
/// URL lives in `.env` (`OMNIVERSIFY_API_URL`), never here.
class AuthApi {
  AuthApi._();

  /// Swapped for a mock client in tests, so no request leaves the process.
  static http.Client client = http.Client();

  /// `.env` decides which backend this is; without it, localhost — the same
  /// rule the rest of the app follows. Guarded so that a missing or unloaded
  /// `.env` surfaces as a message a person can read rather than a crash in
  /// the middle of signing in.
  static String get _base {
    try {
      return ApiConfig.omniversifyApiUrl;
    } catch (_) {
      return 'http://localhost:8000';
    }
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final uri = Uri.parse('$_base/api/v1/auth/$path');
    final http.Response resp;
    try {
      resp = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw AuthException('Cannot reach the server: $e');
    }

    Object? json;
    try {
      json = jsonDecode(resp.body);
    } on FormatException {
      json = null; // A non-JSON body only matters if we needed it.
    }
    final data = json is Map<String, dynamic> ? json : const <String, dynamic>{};

    if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
    throw _error(resp.statusCode, data['detail']);
  }

  static AuthException _error(int status, Object? detail) {
    if (detail is Map<String, dynamic>) {
      final message = detail['message'];
      final code = detail['code'];
      return AuthException(
        message is String && message.isNotEmpty
            ? message
            : 'Something went wrong ($status)',
        code: code is String ? code : null,
        status: status,
      );
    }
    if (detail is String && detail.isNotEmpty) {
      return AuthException(detail, status: status);
    }
    return AuthException('Something went wrong ($status)', status: status);
  }

  static AuthSession _session(Map<String, dynamic> data) {
    final token = data['token'];
    final user = data['user'];
    if (token is! String || user is! Map<String, dynamic>) {
      throw const AuthException('The server sent something unexpected.');
    }
    return AuthSession(token: token, account: Account.fromJson(user));
  }

  // ─── Before you are signed in ──────────────────────────────

  /// Create the account and have the code emailed. Throws 409 if that
  /// address already has one.
  static Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _post('signup', {
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty) 'display_name': displayName,
    });
  }

  /// Ask for another code. The server answers the same way whether or not
  /// that address exists, so this tells an inbox nothing.
  static Future<void> resendCode(String email) async {
    await _post('resend-code', {'email': email});
  }

  /// Type the six digits: the account is confirmed and this session is
  /// already signed in.
  static Future<AuthSession> verify({
    required String email,
    required String code,
  }) async {
    return _session(await _post('verify', {'email': email, 'code': code}));
  }

  static Future<AuthSession> login({
    required String email,
    required String password,
    String? device,
  }) async {
    return _session(await _post('login', {
      'email': email,
      'password': password,
      if (device != null && device.isNotEmpty) 'device': device,
    }));
  }

  /// Always succeeds from the caller's point of view — the server does not
  /// say whether the address has an account.
  static Future<void> forgotPassword(String email) async {
    await _post('forgot-password', {'email': email});
  }

  static Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    return _session(
      await _post('reset-password', {'email': email, 'code': code, 'password': password}),
    );
  }

  // ─── While you are signed in ───────────────────────────────

  static Future<Account> me(String token) async {
    final uri = Uri.parse('$_base/api/v1/auth/me');
    final http.Response resp;
    try {
      resp = await client.get(uri, headers: {'Authorization': 'Bearer $token'});
    } catch (e) {
      throw AuthException('Cannot reach the server: $e');
    }
    if (resp.statusCode == 400 || resp.statusCode == 401 || resp.statusCode >= 500) {
      Object? json;
      try {
        json = jsonDecode(resp.body);
      } on FormatException {
        json = null;
      }
      final detail = json is Map<String, dynamic> ? json['detail'] : null;
      throw AuthException(
        detail is String && detail.isNotEmpty ? detail : 'Something went wrong (${resp.statusCode})',
        status: resp.statusCode,
      );
    }
    final json = jsonDecode(resp.body);
    if (json is! Map<String, dynamic>) {
      throw const AuthException('The server sent something unexpected.');
    }
    return Account.fromJson(json);
  }

  static Future<void> logout(String token) => _post('logout', const {}, token: token);

  static Future<void> logoutAll(String token) =>
      _post('logout-all', const {}, token: token);
}
