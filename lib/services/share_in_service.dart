import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What another app handed us: the words or link Android sent over on the
/// share sheet, plus what the other side of the wire looked like.
class SharedIn {
  const SharedIn({this.text = '', this.subject = ''});

  final String text;
  final String subject;

  /// Android sent a file (an image, say) and no words to go with it.
  bool get fileOnly => text.trim().isEmpty && subject.trim().isEmpty;

  /// What the preview card shows — the caption, then the subject line.
  String get preview {
    if (text.trim().isNotEmpty) return text.trim();
    return subject.trim();
  }

  bool get looksLikeLink =>
      text.trim().startsWith('http://') || text.trim().startsWith('https://');

  factory SharedIn.from(Object? event) {
    final map = (event as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return SharedIn(
      text: (map['text'] as String?)?.trim() ?? '',
      subject: (map['subject'] as String?)?.trim() ?? '',
    );
  }
}

/// Listens to the share channel opened by `MainActivity` for `ACTION_SEND`
/// intents — "Share to Omniversify" in another app's share sheet.
///
/// The platform pushes the payload as soon as it arrives, whether the app was
/// already running or is being opened by the share, and keeps it only until
/// it has been handed over once. The widget that shows the share sheet
/// listens to [incoming] and clears it by calling [consume].
class ShareInService {
  ShareInService._();

  static final ShareInService instance = ShareInService._();

  static const _events = EventChannel('omniversify/share_in');

  /// The most recent share, until something picks it up.
  final ValueNotifier<SharedIn?> incoming = ValueNotifier(null);

  bool _subscribed = false;
  StreamSubscription<dynamic>? _subscription;

  /// Starts listening — call once, after the first frame. Anything that
  /// arrived before Dart was running is waiting on the other side of the
  /// channel and arrives on the first subscription.
  void init() {
    if (_subscribed || kIsWeb) return;
    _subscribed = true;
    try {
      _subscription = _events.receiveBroadcastStream().listen(
        (event) => incoming.value = SharedIn.from(event),
        // No channel on the platforms that have no Android share sheet.
        onError: (_) {},
      );
    } catch (_) {
      _subscribed = false;
    }
  }

  /// Stops listening and forgets the share in flight — tests only, so the
  /// channel does not outlive the test run.
  @visibleForTesting
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _subscribed = false;
    incoming.value = null;
  }

  /// The share has been picked up — don't show it a second time.
  void consume() => incoming.value = null;
}
