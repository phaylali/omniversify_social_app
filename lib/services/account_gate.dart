import 'package:flutter/material.dart';

import '../screens/account_screen.dart';
import 'account_service.dart';

/// Browsing is open to everybody; writing is not.
///
/// Posts, comments, story replies and messages need a confirmed email
/// behind them, so every composer runs past this first. It answers true
/// when the person may go ahead, and otherwise opens the account screen
/// so they can sign in or confirm — then looks again, because coming back
/// from that screen signed in and confirmed is exactly the point.
Future<bool> mayPost(BuildContext context) async {
  if (AccountService.instance.verified) return true;
  if (!context.mounted) return false;

  await AccountScreen.show(context);

  if (!context.mounted) return false;
  return AccountService.instance.verified;
}
