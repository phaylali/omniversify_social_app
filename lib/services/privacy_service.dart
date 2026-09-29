import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who gets to see what you're reading or playing.
enum ShareAudience {
  /// Everyone on Omniversify.
  public,

  /// Only the people you're acquainted with.
  acquaintances,

  /// Nobody but you.
  private,
}

extension ShareAudienceInfo on ShareAudience {
  String get label => switch (this) {
    ShareAudience.public => 'Public',
    ShareAudience.acquaintances => 'Acquaintances',
    ShareAudience.private => 'Private',
  };

  String get blurb => switch (this) {
    ShareAudience.public => 'Everyone on Omniversify can see it',
    ShareAudience.acquaintances => 'Only people you\'re acquainted with',
    ShareAudience.private => 'No one — you keep it to yourself',
  };

  IconData get icon => switch (this) {
    ShareAudience.public => Icons.public,
    ShareAudience.acquaintances => Icons.people_outline,
    ShareAudience.private => Icons.lock_outline,
  };

  /// Short caption for a chip, e.g. `Shared with acquaintances`.
  String get shareLine => switch (this) {
    ShareAudience.public => 'Shared publicly',
    ShareAudience.acquaintances => 'Shared with acquaintances',
    ShareAudience.private => 'Not shared',
  };
}

/// The privacy choice behind the music player and the reader.
///
/// Lives in [SharedPreferences] and mirrors itself into a [ValueNotifier],
/// so the settings screen, the player and the reader all read one source of
/// truth and rebuild the moment the choice changes.
class PrivacyService {
  PrivacyService._();

  static final PrivacyService instance = PrivacyService._();

  static const String _kAudience = 'privacy_share_audience_v1';

  /// Current choice. Acquaintances is the sensible default for a social app.
  final ValueNotifier<ShareAudience> audience = ValueNotifier<ShareAudience>(
    ShareAudience.acquaintances,
  );

  bool _loaded = false;

  /// Reads the stored choice once. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kAudience);
    audience.value = ShareAudience.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => ShareAudience.acquaintances,
    );
    _loaded = true;
  }

  /// Switches audience and persists it.
  Future<void> set(ShareAudience value) async {
    audience.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAudience, value.name);
  }

  /// Whether the current activity is shared with anyone at all.
  bool get isShared => audience.value != ShareAudience.private;
}
