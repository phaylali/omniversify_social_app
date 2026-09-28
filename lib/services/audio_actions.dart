import 'package:flutter/services.dart';

/// Result of a privileged audio-file action (ringtone / delete).
class AudioActionResult {
  const AudioActionResult({
    required this.ok,
    this.needsWriteSettings = false,
    this.needsAllFiles = false,
    this.message,
  });

  final bool ok;
  final bool needsWriteSettings;
  final bool needsAllFiles;
  final String? message;

  factory AudioActionResult.from(Map<Object?, Object?> map) => AudioActionResult(
        ok: map['ok'] == true,
        needsWriteSettings: map['needsWriteSettings'] == true,
        needsAllFiles: map['needsAllFiles'] == true,
        message: map['message'] as String?,
      );
}

/// Thin wrapper over the `omniversify/audio_actions` Android channel.
///
/// Permission policy: NOTHING is requested eagerly. WRITE_SETTINGS and
/// "All files access" prompts only happen when the user triggers the
/// matching action (ringtone / delete) and the check comes back false.
class AudioActions {
  AudioActions._();

  static const MethodChannel _channel = MethodChannel('omniversify/audio_actions');

  static Future<T?> _safe<T>(Future<T?> Function() fn, {T? fallback}) async {
    try {
      return await fn() ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  /// Whether the app may write system settings (needed to set a ringtone).
  static Future<bool> canWriteSettings() async =>
      await _safe(() => _channel.invokeMethod<bool>('canWriteSettings')) ?? false;

  /// Opens the per-app "modify system settings" screen.
  static Future<void> openWriteSettings() =>
      _safe(() => _channel.invokeMethod<bool>('openWriteSettings'));

  /// Whether the app holds "All files access" (Android 10+).
  static Future<bool> canManageAllFiles() async =>
      await _safe(() => _channel.invokeMethod<bool>('canManageAllFiles')) ?? false;

  /// Opens the per-app "All files access" screen.
  static Future<void> openAllFilesAccessSettings() =>
      _safe(() => _channel.invokeMethod<bool>('openAllFilesAccessSettings'));

  /// Sets [path] as the phone's default ringtone.
  static Future<AudioActionResult> setRingtone(String path) async {
    final map = await _safe(
      () => _channel.invokeMapMethod<Object?, Object?>('setRingtone', {'path': path}),
    );
    if (map == null) {
      return const AudioActionResult(ok: false, message: 'Not supported on this device');
    }
    return AudioActionResult.from(map);
  }

  /// Deletes the file at [path]. May report [AudioActionResult.needsAllFiles].
  static Future<AudioActionResult> deleteFile(String path) async {
    final map = await _safe(
      () => _channel.invokeMapMethod<Object?, Object?>('deleteFile', {'path': path}),
    );
    if (map == null) {
      return const AudioActionResult(ok: false, message: 'Not supported on this device');
    }
    return AudioActionResult.from(map);
  }
}
