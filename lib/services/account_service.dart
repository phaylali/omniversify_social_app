import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/services/auth_api.dart';

/// Who is signed in on this device, and the session that proves it.
///
/// One source of truth for the settings screen, the account screen and
/// anything that has to know whether the person may post. The bearer token
/// lives in the platform keystore rather than plain preferences — a session
/// is a credential, and a backup of the phone should not carry it away. If
/// the keystore refuses (it happens on odd devices), the app still works for
/// the session: the person just signs in again after a restart.
class AccountService {
  AccountService._();

  static final AccountService instance = AccountService._();

  static const _tokenKey = 'account_session_token_v1';
  static const _storage = FlutterSecureStorage();

  /// The signed-in person, or null when nobody is.
  final ValueNotifier<Account?> account = ValueNotifier<Account?>(null);

  /// Address waiting for its six-digit code, so the app can reopen the
  /// entry after a login said "confirm your email first".
  final ValueNotifier<String?> awaitingCodeFor = ValueNotifier<String?>(null);

  String? _token;

  /// The bearer token, for anything that has to call the API directly.
  String? get token => _token;

  bool get signedIn => _token != null && account.value != null;

  /// Browsing is open to everyone; posting, commenting and messaging need
  /// this to be true.
  bool get verified => account.value?.emailVerified ?? false;

  /// Read the saved session and check it is still alive. Called once when
  /// the app starts.
  Future<void> restore() async {
    final saved = await _readToken();
    if (saved == null) return;
    _token = saved;
    try {
      account.value = await AuthApi.me(saved);
    } on AuthException catch (exc) {
      // 401 means it was signed out or expired; anything else (no network)
      // keeps the session and tries again later.
      if (exc.status == 401) await signOutLocally();
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await AuthApi.signUp(email: email, password: password, displayName: displayName);
    awaitingCodeFor.value = email;
  }

  Future<AuthSession> verify({required String email, required String code}) async {
    final session = await AuthApi.verify(email: email, code: code);
    await _adopt(session);
    return session;
  }

  Future<AuthSession> signIn({required String email, required String password}) async {
    try {
      final session = await AuthApi.login(email: email, password: password);
      await _adopt(session);
      return session;
    } on AuthException catch (exc) {
      if (exc.code == 'needs_verification') awaitingCodeFor.value = email;
      rethrow;
    }
  }

  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final session = await AuthApi.resetPassword(
      email: email,
      code: code,
      password: password,
    );
    await _adopt(session);
    return session;
  }

  Future<void> sendCode(String email) => AuthApi.resendCode(email);

  Future<void> forgotPassword(String email) => AuthApi.forgotPassword(email);

  /// Sign out of this device only.
  Future<void> signOut() async {
    final token = _token;
    if (token != null) {
      try {
        await AuthApi.logout(token);
      } catch (_) {
        // Offline: the token still dies locally, and the server expires it.
      }
    }
    await signOutLocally();
  }

  /// Sign out everywhere — every device this account is on.
  Future<void> signOutEverywhere() async {
    final token = _token;
    if (token != null) {
      try {
        await AuthApi.logoutAll(token);
      } catch (_) {}
    }
    await signOutLocally();
  }

  /// Forget the session without asking the server.
  Future<void> signOutLocally() async {
    _token = null;
    account.value = null;
    awaitingCodeFor.value = null;
    await _writeToken(null);
  }

  Future<void> _adopt(AuthSession session) async {
    _token = session.token;
    account.value = session.account;
    awaitingCodeFor.value = session.account.emailVerified ? null : session.account.email;
    await _writeToken(session.token);
  }

  Future<String?> _readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('[account] keystore read failed: $e');
      return null;
    }
  }

  Future<void> _writeToken(String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: _tokenKey);
      } else {
        await _storage.write(key: _tokenKey, value: value);
      }
    } catch (e) {
      debugPrint('[account] keystore write failed: $e');
    }
  }

  /// Start from nothing — tests use this between cases.
  @visibleForTesting
  Future<void> resetForTests() async {
    _token = null;
    account.value = null;
    awaitingCodeFor.value = null;
    await _writeToken(null);
  }
}
