import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/auth_api.dart';
import '../services/account_service.dart';

/// Sign in, confirm an email with a six-digit code, or manage the session
/// this device already has.
///
/// No magic links: a code typed here is the whole confirmation flow, which
/// is what the app can do without asking a phone to open a link.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  /// Opens the screen, and answers whether the person came away signed in
  /// and confirmed.
  static Future<bool> show(BuildContext context) async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountScreen()),
    );
    return signedIn ?? false;
  }

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

enum _Mode { signIn, signUp, code, signedIn }

enum _Flow { confirmEmail, resetPassword }

class _AccountScreenState extends State<AccountScreen> {
  late _Mode _mode;
  _Flow _flow = _Flow.confirmEmail;

  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _newPassword;
  late final TextEditingController _code;

  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _ticker;

  AccountService get _account => AccountService.instance;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
    _password = TextEditingController();
    _newPassword = TextEditingController();
    _code = TextEditingController();

    final current = _account.account.value;
    if (current != null) {
      _mode = _Mode.signedIn;
    } else {
      final waiting = _account.awaitingCodeFor.value;
      if (waiting != null) {
        _email.text = waiting;
        _mode = _Mode.code;
        _startResendCooldown();
      } else {
        _mode = _Mode.signIn;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _password.dispose();
    _newPassword.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _ticker?.cancel();
    setState(() => _resendIn = 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        _resendIn -= 1;
        if (_resendIn <= 0) timer.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      _Mode.signIn => 'Sign in',
      _Mode.signUp => 'Create account',
      _Mode.code => _flow == _Flow.confirmEmail ? 'Confirm your email' : 'New password',
      _Mode.signedIn => 'Account',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          switch (_mode) {
            _Mode.signIn => _signInForm(),
            _Mode.signUp => _signUpForm(),
            _Mode.code => _codeForm(),
            _Mode.signedIn => _signedInView(),
          },
        ],
      ),
    );
  }

  // ─── Fields ────────────────────────────────────────────────

  Widget _field({
    required String key,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool obscure = false,
    TextInputAction action = TextInputAction.next,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_busy,
        keyboardType: keyboardType,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        textInputAction: action,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _errorLine() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        _error!,
        key: const ValueKey('account-error'),
        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _submitButton(String label) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey('account-submit'),
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap, {String? key}) {
    return TextButton(
      key: key == null ? null : ValueKey(key),
      onPressed: _busy ? null : onTap,
      child: Text(label),
    );
  }

  // ─── The four views ────────────────────────────────────────

  Widget _signInForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Your shelves, your people, on every phone you sign in on.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        _field(
          key: 'account-email',
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        _field(
          key: 'account-password',
          controller: _password,
          label: 'Password',
          obscure: true,
          action: TextInputAction.done,
        ),
        _errorLine(),
        _submitButton('Sign in'),
        _link('Forgot password?', _forgotPassword, key: 'account-forgot'),
        _link('New here? Create an account', () {
          setState(() {
            _mode = _Mode.signUp;
            _error = null;
          });
        }, key: 'account-to-signup'),
      ],
    );
  }

  Widget _signUpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('We send a six-digit code to confirm the address is yours. '
            'Until then you can browse, but not post.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        _field(
          key: 'account-email',
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        _field(
          key: 'account-password',
          controller: _password,
          label: 'Password',
          hint: 'At least 10 characters',
          obscure: true,
        ),
        _errorLine(),
        _submitButton('Create account'),
        _link('I already have an account', () {
          setState(() {
            _mode = _Mode.signIn;
            _error = null;
          });
        }, key: 'account-to-signin'),
      ],
    );
  }

  Widget _codeForm() {
    final confirming = _flow == _Flow.confirmEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          confirming
              ? 'Enter the six digits we emailed to ${_email.text.trim()}.'
              : 'Enter the six digits we emailed to ${_email.text.trim()}, then choose a new password.',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        _field(
          key: 'account-code',
          controller: _code,
          label: 'Six-digit code',
          keyboardType: TextInputType.number,
          action: confirming ? TextInputAction.done : TextInputAction.next,
          hint: '000000',
        ),
        if (!confirming)
          _field(
            key: 'account-new-password',
            controller: _newPassword,
            label: 'New password',
            hint: 'At least 10 characters',
            obscure: true,
            action: TextInputAction.done,
          ),
        _errorLine(),
        _submitButton(confirming ? 'Confirm' : 'Set password'),
        if (confirming)
          _link(
            _resendIn > 0 ? 'Send another code in $_resendIn s' : 'Send another code',
            _resendIn > 0 ? () {} : _resend,
            key: 'account-resend',
          ),
        _link(
          confirming ? 'Use a different email' : 'Back to sign in',
          () {
            setState(() {
              _mode = _Mode.signIn;
              _flow = _Flow.confirmEmail;
              _error = null;
              _code.clear();
              _newPassword.clear();
            });
          },
          key: 'account-back',
        ),
      ],
    );
  }

  Widget _signedInView() {
    final person = _account.account.value;
    if (person == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.person_outline, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                person.email,
                key: const ValueKey('account-email-shown'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: (person.emailVerified ? cs.primary : cs.error).withAlpha(120),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            person.emailVerified ? 'Email confirmed' : 'Email not confirmed',
            key: const ValueKey('account-verified'),
            style: TextStyle(
              fontSize: 12,
              color: person.emailVerified ? cs.primary : cs.error,
            ),
          ),
        ),
        if (!person.emailVerified) ...[
          const SizedBox(height: 14),
          const Text(
            'Confirm your email to post, comment and message. Your shelves '
            'work either way.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('account-send-code'),
            onPressed: _busy ? null : _sendConfirmationCode,
            child: const Text('Email me a code'),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton(
          key: const ValueKey('account-change-password'),
          onPressed: _busy ? null : _forgotPassword,
          child: const Text('Change password'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const ValueKey('account-signout'),
          onPressed: _busy ? null : () => _finish(signOut: true),
          child: const Text('Sign out'),
        ),
        const SizedBox(height: 10),
        TextButton(
          key: const ValueKey('account-signout-all'),
          onPressed: _busy ? null : () => _finish(signOutEverywhere: true),
          child: const Text('Sign out everywhere'),
        ),
      ],
    );
  }

  // ─── What the buttons do ───────────────────────────────────

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.signIn:
          await _account.signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
          if (!mounted) return;
          Navigator.of(context).pop(true);

        case _Mode.signUp:
          await _account.signUp(
            email: _email.text.trim(),
            password: _password.text,
          );
          if (!mounted) return;
          setState(() => _mode = _Mode.code);
          _startResendCooldown();

        case _Mode.code:
          if (_flow == _Flow.confirmEmail) {
            await _account.verify(email: _email.text.trim(), code: _code.text.trim());
          } else {
            await _account.resetPassword(
              email: _email.text.trim(),
              code: _code.text.trim(),
              password: _newPassword.text,
            );
          }
          if (!mounted) return;
          Navigator.of(context).pop(true);

        case _Mode.signedIn:
          return;
      }
    } on AuthException catch (exc) {
      if (!mounted) return;
      setState(() => _error = exc.message);
      if (exc.code == 'needs_verification') {
        setState(() => _mode = _Mode.code);
        _startResendCooldown();
      }
    } catch (exc) {
      if (!mounted) return;
      setState(() => _error = '$exc');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.sendCode(_email.text.trim());
      _startResendCooldown();
    } on AuthException catch (exc) {
      if (mounted) setState(() => _error = exc.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendConfirmationCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.sendCode(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _mode = _Mode.code;
        _flow = _Flow.confirmEmail;
      });
      _startResendCooldown();
    } on AuthException catch (exc) {
      if (mounted) setState(() => _error = exc.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final address = _email.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Enter your email first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.forgotPassword(address);
      if (!mounted) return;
      setState(() {
        _mode = _Mode.code;
        _flow = _Flow.resetPassword;
      });
      _startResendCooldown();
    } on AuthException catch (exc) {
      if (mounted) setState(() => _error = exc.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({bool signOut = false, bool signOutEverywhere = false}) async {
    setState(() => _busy = true);
    if (signOutEverywhere) {
      await _account.signOutEverywhere();
    } else if (signOut) {
      await _account.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }
}
