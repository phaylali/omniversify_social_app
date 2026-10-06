import 'package:omniversify_social_app/core/services/auth_api.dart';
import 'package:omniversify_social_app/services/account_service.dart';

/// Puts this device in the state the composers now require: signed in with
/// a confirmed email. Tests that are *about* that rule clear it again with
/// [signOutForTest] and look at the account screen instead.
void signInForTest({String email = 'phaylali@example.com'}) {
  AccountService.instance.account.value = Account(
    id: 'test-user',
    email: email,
    emailVerified: true,
  );
  AccountService.instance.awaitingCodeFor.value = null;
}

/// Nobody is signed in — which is to say: browsing, but not posting.
void signOutForTest() {
  AccountService.instance.account.value = null;
  AccountService.instance.awaitingCodeFor.value = null;
}
