import 'package:home_widget/home_widget.dart';

/// Pushes music player state to the Android home-screen widget.
///
/// Keys are read by `MusicWidgetProvider` via `HomeWidgetPlugin.getData`.
class MusicWidgetService {
  MusicWidgetService._();
  static final MusicWidgetService instance = MusicWidgetService._();

  static const String _kTitle = 'widget_title';
  static const String _kArtist = 'widget_artist';
  static const String _kPlaying = 'widget_is_playing';
  static const String _kArtwork = 'widget_artwork_uri';

  bool _enabled = false;

  Future<void> save({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artworkUri,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(_kTitle, title);
      await HomeWidget.saveWidgetData<String>(_kArtist, artist);
      await HomeWidget.saveWidgetData<bool>(_kPlaying, isPlaying);
      if (artworkUri != null) {
        await HomeWidget.saveWidgetData<String>(_kArtwork, artworkUri);
      }
      if (!_enabled) {
        _enabled = true;
      }
      await HomeWidget.updateWidget(
        qualifiedAndroidName:
            'com.omniversify.omniversify_social_app.MusicWidgetProvider',
      );
    } catch (_) {
      // Widget is best-effort — never break playback for it.
    }
  }

  Future<void> clear() => save(
        title: 'Nothing playing',
        artist: 'Omniversify',
        isPlaying: false,
      );
}
