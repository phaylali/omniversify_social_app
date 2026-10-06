import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';

import 'package:omniversify_social_app/core/services/auth_api.dart';
import 'package:omniversify_social_app/screens/account_screen.dart';
import 'package:omniversify_social_app/services/account_service.dart';

import 'account_fixtures.dart';

/// The backend, in miniature: exactly the answers the real one gives, and
/// a record of what the app asked it.
class _Backend {
  _Backend(this.routes);

  /// Path under `/api/v1/auth` → response.
  final Map<String, http.Response> routes;
  final List<http.Request> calls = [];

  static http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Client get client => MockClient((request) async {
        calls.add(request);
        return routes[request.url.path.replaceFirst('/api/v1/auth', '')] ??
            http.Response('{"detail":"no route"}', 404);
      });
}

const _session = {
  'token': 'session-token-1',
  'user': {
    'id': 'user-1',
    'email': 'a@b.co',
    'display_name': null,
    'email_verified': true,
    'created_at': '2026-10-06T22:00:00+00:00',
  },
};

/// Opens the account screen the way the settings tile does, so there is a
/// route underneath it to come back to.
Future<void> _openAccountScreen(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const ValueKey('open-account'),
            onPressed: () => AccountScreen.show(context),
            child: const Text('Account'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('open-account')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Types an address, a password and submits — whichever form is showing.
Future<void> _submitCredentials(WidgetTester tester,
    {String email = 'a@b.co',
    String password = 'six six six six',
    bool createAccount = false}) async {
  if (createAccount) {
    await tester.tap(find.byKey(const ValueKey('account-to-signup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.enterText(
      find.byKey(const ValueKey('account-email')), email);
  await tester.enterText(
      find.byKey(const ValueKey('account-password')), password);
  await tester.tap(find.byKey(const ValueKey('account-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Signed out → code screen → six digits → confirmed and signed in.
Future<void> _confirmEmail(WidgetTester tester) async {
  AccountService.instance.awaitingCodeFor.value = 'a@b.co';
  await _openAccountScreen(tester);
  await tester.enterText(
      find.byKey(const ValueKey('account-code')), '123456');
  await tester.tap(find.byKey(const ValueKey('account-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    signOutForTest();
    addTearDown(() => AuthApi.client = http.Client());
  });

  group('creating an account', () {
    testWidgets('asks for the six-digit code that was emailed', (tester) async {
      final backend = _Backend({
        '/signup': _Backend.json(
          {'status': 'needs_verification', 'email': 'a@b.co'},
          status: 202,
        ),
      });
      AuthApi.client = backend.client;

      await _openAccountScreen(tester);
      await _submitCredentials(tester, createAccount: true);

      expect(find.byKey(const ValueKey('account-code')), findsOneWidget);
      expect(find.textContaining('a@b.co'), findsOneWidget);
      expect(AccountService.instance.awaitingCodeFor.value, 'a@b.co');

      // The password went as a JSON body over POST, never in the URL.
      expect(backend.calls.single.url.toString(),
          contains('/api/v1/auth/signup'));
      expect(backend.calls.single.method, 'POST');
      expect(utf8.decode(backend.calls.single.bodyBytes),
          contains('six six six six'));
      expect(backend.calls.single.url.toString(), isNot(contains('six six')));
    });

    testWidgets('is refused when the address already has one',
        (tester) async {
      final backend = _Backend({
        '/signup': _Backend.json(
          {'detail': 'That email is already registered.'},
          status: 409,
        ),
      });
      AuthApi.client = backend.client;

      await _openAccountScreen(tester);
      await _submitCredentials(tester, createAccount: true);

      expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
      expect(find.text('That email is already registered.'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-code')), findsNothing);
      expect(AccountService.instance.signedIn, isFalse);
    });
  });

  group('the six-digit code', () {
    testWidgets('confirms the email and signs this device in',
        (tester) async {
      final backend = _Backend({'/verify': _Backend.json(_session)});
      AuthApi.client = backend.client;

      await _confirmEmail(tester);

      expect(backend.calls.single.url.toString(),
          contains('/api/v1/auth/verify'));
      expect(AccountService.instance.verified, isTrue);
      expect(AccountService.instance.signedIn, isTrue);
      expect(AccountService.instance.token, 'session-token-1');
      expect(AccountService.instance.account.value?.email, 'a@b.co');
      // Back to the route that opened it, now signed in.
      expect(find.byKey(const ValueKey('open-account')), findsOneWidget);
    });

    testWidgets('is refused when it does not match', (tester) async {
      final backend = _Backend({
        '/verify': _Backend.json(
          {'detail': 'That code is not valid.'},
          status: 400,
        ),
      });
      AuthApi.client = backend.client;

      await _confirmEmail(tester);

      expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
      expect(find.text('That code is not valid.'), findsOneWidget);
      expect(AccountService.instance.signedIn, isFalse);
      expect(AccountService.instance.verified, isFalse);
    });
  });

  group('signing in', () {
    testWidgets('goes straight to the code screen when the email is waiting',
        (tester) async {
      final backend = _Backend({
        '/login': _Backend.json(
          {
            'detail': {
              'message': 'Confirm your email first — we sent you a code.',
              'code': 'needs_verification',
            },
          },
          status: 403,
        ),
      });
      AuthApi.client = backend.client;

      await _openAccountScreen(tester);
      await _submitCredentials(tester);

      expect(find.byKey(const ValueKey('account-code')), findsOneWidget);
      expect(find.textContaining('a@b.co'), findsOneWidget);
      expect(AccountService.instance.awaitingCodeFor.value, 'a@b.co');
      expect(AccountService.instance.signedIn, isFalse);
    });

    testWidgets('shows exactly what the server said about a bad password',
        (tester) async {
      final backend = _Backend({
        '/login': _Backend.json(
          {'detail': 'Email or password is incorrect.'},
          status: 401,
        ),
      });
      AuthApi.client = backend.client;

      await _openAccountScreen(tester);
      await _submitCredentials(tester);

      expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-code')), findsNothing);
      expect(AccountService.instance.signedIn, isFalse);
    });

    testWidgets('never says whether the address exists', (tester) async {
      final unknown = _Backend({
        '/login': _Backend.json(
          {'detail': 'Email or password is incorrect.'},
          status: 401,
        ),
      });
      AuthApi.client = unknown.client;

      await _openAccountScreen(tester);
      await _submitCredentials(tester, email: 'never-heard-of-them@b.co');

      expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
    });
  });

  group('the session', () {
    testWidgets('signing out ends it on this device', (tester) async {
      final backend = _Backend({
        '/verify': _Backend.json(_session),
        '/logout': _Backend.json({'status': 'signed_out'}),
      });
      AuthApi.client = backend.client;

      await _confirmEmail(tester);
      expect(AccountService.instance.signedIn, isTrue);

      await AccountService.instance.signOut();

      expect(AccountService.instance.signedIn, isFalse);
      expect(AccountService.instance.token, isNull);
      expect(backend.calls.map((c) => c.url.path),
          contains('/api/v1/auth/logout'));
    });

    testWidgets('the settings tile says what to do about it', (tester) async {
      signOutForTest();
      expect(AccountService.instance.verified, isFalse);
      expect(AccountService.instance.signedIn, isFalse);

      signInForTest();
      expect(AccountService.instance.verified, isTrue);
      expect(AccountService.instance.account.value?.email,
          'phaylali@example.com');
    });
  });
}
