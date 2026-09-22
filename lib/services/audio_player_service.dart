import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';
import 'artwork_loader.dart';
import 'widget_service.dart';

/// Repeat modes for the music player.
///
/// Named [MusicRepeatMode] to avoid collision with Flutter's built-in
/// [RepeatMode] from `package:flutter/material.dart`.
enum MusicRepeatMode { off, one, all }

/// Singleton audio player that survives screen navigation.
///
/// Responsibilities:
/// - Manages a playlist of [SongItem]s and current playback index.
/// - Provides shuffle and repeat (off / one / all) modes.
/// - Persists shuffle / repeat / volume across app launches.
/// - Connects to [audio_service] to expose an Android media notification
///   with play/pause/next/prev/seek controls.
/// - Pushes now-playing state to the Android home-screen widget.
/// - Exposes a [stateStream] that UI widgets listen to for rebuilds.
///
/// All state is held here; the music player screen is a pure consumer.
class AudioPlayerService {
  AudioPlayerService._();
  static final AudioPlayerService instance = AudioPlayerService._();

  static const String _kShuffle = 'music_shuffle_on';
  static const String _kRepeat = 'music_repeat_mode';
  static const String _kVolume = 'music_volume';

  /// Underlying audioplayers instance — exposed for advanced use.
  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;

  // ── Playlist state ──────────────────────────────────────
  List<SongItem> _playlist = [];
  int? _currentIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isTransitioning = false;
  double _volume = 1.0;

  // ── Shuffle / repeat state ──────────────────────────────
  bool _shuffleOn = false;
  MusicRepeatMode _repeatMode = MusicRepeatMode.off;
  final Random _rng = Random();

  /// Ordered list of playlist indices representing the shuffled queue.
  /// Built when shuffle is toggled on, or when the queue is exhausted
  /// in repeat-all mode.
  List<int> _shuffledIndices = [];

  // ── Public getters ──────────────────────────────────────
  List<SongItem> get playlist => _playlist;
  int? get currentIndex => _currentIndex;
  SongItem? get currentSong =>
      _currentIndex != null && _currentIndex! < _playlist.length
          ? _playlist[_currentIndex!]
          : null;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  double get volume => _volume;
  bool get shuffleOn => _shuffleOn;
  MusicRepeatMode get repeatMode => _repeatMode;

  /// Broadcast stream for any state change — UI widgets listen here.
  final _stateController = StreamController<void>.broadcast();
  Stream<void> get stateStream => _stateController.stream;
  Future<void>? _initFuture;
  Future<void>? _prefsFuture;

  /// audio_service handler for Android notification / media session.
  MusicAudioHandler? _audioHandler;
  String? _lastArtPath;
  String? _lastArtSongPath;

  /// Emit a state change to the stream, update media session + widget.
  void _emit() {
    if (!_stateController.isClosed) _stateController.add(null);
    _updateMediaItem();
    _updateWidget();
  }

  /// Initialize player listeners + restore persisted settings.
  /// Safe to call multiple times (idempotent).
  Future<void> init() {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    await _loadPrefs();

    _player.onDurationChanged.listen((d) {
      if (d > Duration.zero) {
        _duration = d;
        _emit();
      }
    });

    _player.onPositionChanged.listen((p) {
      _position = p;
      _emit();
    });

    // Track completion handler — decides next track based on repeat/shuffle.
    _player.onPlayerComplete.listen((_) => _onComplete());

    try {
      await _player.setVolume(_volume);
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    if (_prefsFuture != null) return _prefsFuture!;
    _prefsFuture = _loadPrefsImpl();
    return _prefsFuture!;
  }

  Future<void> _loadPrefsImpl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shuffleOn = prefs.getBool(_kShuffle) ?? _shuffleOn;
      final r = prefs.getString(_kRepeat);
      if (r != null) {
        for (final mode in MusicRepeatMode.values) {
          if (mode.name == r) {
            _repeatMode = mode;
            break;
          }
        }
      }
      _volume = (prefs.getDouble(_kVolume) ?? _volume).clamp(0.0, 1.0);
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShuffle, _shuffleOn);
      await prefs.setString(_kRepeat, _repeatMode.name);
      await prefs.setDouble(_kVolume, _volume);
    } catch (_) {}
  }

  /// Connect to audio_service for the Android media notification.
  ///
  /// Must be called once after [init]. This sets up the foreground service
  /// notification that shows current track info and playback controls.
  Future<void> connectAudioService() async {
    if (_audioHandler != null) return;
    await init();
    if (_audioHandler != null) return;
    _audioHandler = MusicAudioHandler(this);
    await AudioService.init(
      builder: () => _audioHandler!,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.omniversify.music',
        androidNotificationChannelName: 'Omniversify Music',
        // Keep the notification (with controls) visible while paused.
        // audio_service asserts: ongoing can only be true when
        // androidStopForegroundOnPause is also true — so ongoing must be false.
        androidStopForegroundOnPause: false,
        androidNotificationOngoing: false,
        artDownscaleWidth: 300,
        artDownscaleHeight: 300,
      ),
    );
  }

  // ── Track completion logic ──────────────────────────────

  void _onComplete() {
    // Repeat one: restart current track from beginning.
    if (_repeatMode == MusicRepeatMode.one) {
      seek(Duration.zero);
      _player.resume();
      _emit();
      return;
    }

    final nextIdx = _nextIndex();
    if (nextIdx != null) {
      play(nextIdx);
    } else {
      // Reached end of playlist.
      if (_repeatMode == MusicRepeatMode.all) {
        // Wrap around to start.
        play(0);
      } else {
        // Stop playback.
        _isPlaying = false;
        _position = Duration.zero;
        _emit();
      }
    }
  }

  /// Returns the next track index accounting for shuffle and repeat,
  /// or null if playback should stop (end of playlist, no repeat).
  int? _nextIndex() {
    if (_playlist.isEmpty || _currentIndex == null) return null;

    if (_shuffleOn) {
      final posInShuffle = _shuffledIndices.indexOf(_currentIndex!);
      if (posInShuffle >= 0 && posInShuffle < _shuffledIndices.length - 1) {
        return _shuffledIndices[posInShuffle + 1];
      }
      // Exhausted shuffled queue — reshuffle if repeat-all.
      if (_repeatMode == MusicRepeatMode.all) {
        _buildShuffleQueue(excludeCurrent: true);
        return _shuffledIndices.isNotEmpty ? _shuffledIndices.first : null;
      }
      return null;
    }

    // Sequential mode — just advance by one.
    if (_currentIndex! < _playlist.length - 1) {
      return _currentIndex! + 1;
    }
    return null;
  }

  // ── Playlist management ─────────────────────────────────

  Future<void> setPlaylist(List<SongItem> songs) async {
    _playlist = songs;
    if (_shuffleOn) _buildShuffleQueue();
  }

  // ── Playback controls ───────────────────────────────────

  /// Play the track at [index]. Uses cached duration for instant UI update;
  /// falls back to polling the player when no cached duration exists.
  Future<void> play(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (_isTransitioning) return;
    _isTransitioning = true;
    final song = _playlist[index];
    _currentIndex = index;
    _isPlaying = true;
    _position = Duration.zero;
    _duration = song.duration != null && song.duration! > 0
        ? Duration(milliseconds: song.duration!)
        : Duration.zero;
    _emit();

    try {
      await _player.stop();
      await _player.play(DeviceFileSource(song.path));
      // Background poll: only needed when we had no cached duration.
      if (_duration == Duration.zero) {
        _fetchDurationBackground();
      }
    } catch (_) {
      _isPlaying = false;
      _emit();
    } finally {
      _isTransitioning = false;
    }
  }

  /// Poll the player for duration when no cached value is available.
  /// Tries up to 10 times at 200ms intervals.
  void _fetchDurationBackground() async {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        final d = await _player.getDuration();
        if (d != null && d > Duration.zero) {
          _duration = d;
          _emit();
          break;
        }
      } catch (_) {
        break;
      }
    }
  }

  void togglePlay() {
    if (_currentIndex == null) return;
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.resume();
    }
    _isPlaying = !_isPlaying;
    _emit();
  }

  /// Stop playback but keep the current track selected so Play can resume.
  /// Used by the notification Stop action — must not clear the playlist.
  void stop() {
    _player.pause();
    _isPlaying = false;
    _position = Duration.zero;
    try {
      _player.seek(Duration.zero);
    } catch (_) {}
    _emit();
  }

  /// Skip to the next track, respecting shuffle and repeat modes.
  void next() {
    if (_shuffleOn) {
      if (_shuffledIndices.isEmpty) {
        _buildShuffleQueue();
      }
      final posInShuffle = _currentIndex != null
          ? _shuffledIndices.indexOf(_currentIndex!)
          : -1;
      if (posInShuffle >= 0 && posInShuffle < _shuffledIndices.length - 1) {
        play(_shuffledIndices[posInShuffle + 1]);
      } else if (_repeatMode == MusicRepeatMode.all) {
        _buildShuffleQueue();
        if (_shuffledIndices.isNotEmpty) play(_shuffledIndices.first);
      }
    } else {
      if (_currentIndex == null || _currentIndex! >= _playlist.length - 1) {
        if (_repeatMode == MusicRepeatMode.all && _playlist.isNotEmpty) {
          play(0);
        }
        return;
      }
      play(_currentIndex! + 1);
    }
  }

  /// Skip to the previous track. If more than 3 seconds into the current
  /// track, restarts it instead (standard media player behavior).
  void previous() {
    if (_position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    if (_shuffleOn) {
      final posInShuffle = _currentIndex != null
          ? _shuffledIndices.indexOf(_currentIndex!)
          : -1;
      if (posInShuffle > 0) {
        play(_shuffledIndices[posInShuffle - 1]);
      } else if (_repeatMode == MusicRepeatMode.all &&
          _shuffledIndices.isNotEmpty) {
        play(_shuffledIndices.last);
      }
    } else {
      if (_currentIndex == null || _currentIndex! <= 0) {
        if (_repeatMode == MusicRepeatMode.all && _playlist.isNotEmpty) {
          play(_playlist.length - 1);
        } else {
          seek(Duration.zero);
        }
        return;
      }
      play(_currentIndex! - 1);
    }
  }

  void seek(Duration position) {
    _player.seek(position);
    _position = position;
    _emit();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_volume);
    } catch (_) {}
    _savePrefs();
    _emit();
  }

  // ── Shuffle / Repeat toggles ────────────────────────────

  /// Toggle shuffle on/off. When turned on, builds a new shuffled queue.
  void toggleShuffle() {
    _shuffleOn = !_shuffleOn;
    if (_shuffleOn) {
      _buildShuffleQueue();
    }
    _savePrefs();
    _emit();
  }

  /// Cycle through repeat modes: off → all → one → off.
  void cycleRepeat() {
    switch (_repeatMode) {
      case MusicRepeatMode.off:
        _repeatMode = MusicRepeatMode.all;
        break;
      case MusicRepeatMode.all:
        _repeatMode = MusicRepeatMode.one;
        break;
      case MusicRepeatMode.one:
        _repeatMode = MusicRepeatMode.off;
        break;
    }
    _savePrefs();
    _emit();
  }

  /// Build a randomized index queue. Keeps the current track at position 0
  /// when [excludeCurrent] is false (default for shuffle toggle).
  void _buildShuffleQueue({bool excludeCurrent = false}) {
    final indices = List<int>.generate(_playlist.length, (i) => i);
    indices.shuffle(_rng);
    if (_currentIndex != null && !excludeCurrent) {
      indices.remove(_currentIndex!);
      indices.insert(0, _currentIndex!);
    }
    _shuffledIndices = indices;
  }

  // ── Audio service / media notification helpers ──────────

  // Only push mediaItem when the track or artwork actually changes.
  // Re-adding on every position tick makes the notification art flash.
  String? _lastMediaItemKey;

  /// Push current song metadata to the media session notification.
  /// Artwork is attached asynchronously once [ArtworkLoader] resolves it.
  void _updateMediaItem() {
    final song = currentSong;
    if (song == null || _audioHandler == null) return;
    final artPath = _lastArtSongPath == song.path ? _lastArtPath : null;
    final key = '${song.path}|$artPath|${_duration.inMilliseconds}';
    if (key == _lastMediaItemKey) return;
    _lastMediaItemKey = key;
    _audioHandler!.mediaItem.add(_buildMediaItem(song, artPath: artPath));
    if (_lastArtSongPath != song.path) {
      _attachArtwork(song);
    }
  }

  Future<void> _attachArtwork(SongItem song) async {
    final handler = _audioHandler;
    if (handler == null) return;
    try {
      final bytes = await ArtworkLoader.instance.load(song);
      if (bytes == null || bytes.isEmpty) return;
      // Song changed while we were loading — drop stale art.
      if (currentSong?.path != song.path) return;
      final file = await ArtworkLoader.instance.writeForNotification(song, bytes);
      if (file == null) return;
      if (currentSong?.path != song.path) return;
      _lastArtPath = file.path;
      _lastArtSongPath = song.path;
      _lastMediaItemKey = null; // force mediaItem refresh with new art
      handler.mediaItem.add(_buildMediaItem(song, artPath: file.path));
      _updateWidget(artworkPath: file.path);
    } catch (_) {}
  }

  MediaItem _buildMediaItem(SongItem song, {String? artPath}) {
    return MediaItem(
      id: song.path,
      title: song.title,
      artist: song.artist ?? 'Unknown',
      album: song.album ?? '',
      duration: _duration,
      artUri: artPath != null ? Uri.file(artPath) : null,
    );
  }

  // Skip RemoteViews refresh when nothing visible changed — otherwise
  // the widget art reloads (and flashes) on every position tick.
  String? _lastWidgetKey;

  void _updateWidget({String? artworkPath}) {
    final song = currentSong;
    if (song == null) {
      if (_lastWidgetKey != 'idle') {
        _lastWidgetKey = 'idle';
        MusicWidgetService.instance.clear();
      }
      return;
    }
    final artUri = artworkPath != null
        ? Uri.file(artworkPath).toString()
        : (_lastArtSongPath == song.path && _lastArtPath != null
            ? Uri.file(_lastArtPath!).toString()
            : null);
    final key =
        '${song.path}|${song.artist}|$_isPlaying|$artUri';
    if (key == _lastWidgetKey) return;
    _lastWidgetKey = key;
    MusicWidgetService.instance.save(
      title: song.title,
      artist: song.artist ?? 'Unknown',
      isPlaying: _isPlaying,
      artworkUri: artUri,
    );
  }

  void dispose() {
    _player.dispose();
    _audioHandler?.stop();
    _stateController.close();
  }
}

// ── AudioService handler for Android media notification ──────────

/// Bridges [AudioPlayerService] to the system media session / notification.
///
/// Android shows a persistent notification with:
/// - Current track title, artist, album art
/// - Play/pause, next, previous buttons
/// - Seek bar (scrubbing)
///
/// This handler translates system callbacks into [AudioPlayerService] calls.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayerService _service;

  MusicAudioHandler(this._service) {
    _init();
  }

  void _init() {
    // Forward every state change from the player to the system session.
    _service.stateStream.listen((_) {
      _broadcastState();
    });

    // Expose current playlist as the system queue.
    final items = _service._playlist
        .map(
          (song) => MediaItem(
            id: song.path,
            title: song.title,
            artist: song.artist ?? 'Unknown',
            album: song.album ?? '',
            duration: song.duration != null
                ? Duration(milliseconds: song.duration!)
                : null,
          ),
        )
        .toList();
    if (items.isNotEmpty) queue.add(items);

    // Set initial media item if something is already playing.
    final song = _service.currentSong;
    if (song != null) {
      mediaItem.add(_service._buildMediaItem(song));
    }
  }

  /// Push current playback state to the system media session.
  void _broadcastState() {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_service.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Indices of buttons shown in the compact (Android notification) view.
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.ready,
      playing: _service.isPlaying,
      updatePosition: _service.position,
      bufferedPosition: _service.position,
      speed: 1.0,
    ));
    // mediaItem is updated only in AudioPlayerService._updateMediaItem
    // when the track/artwork actually changes (avoids notification art flash).
  }

  @override
  Future<void> play() async {
    if (_service.currentSong == null) return;
    if (!_service.isPlaying) _service.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (_service.isPlaying) _service.togglePlay();
  }

  @override
  Future<void> stop() async {
    // Keep the track selected so Play from the notification can resume it.
    _service.stop();
  }

  @override
  Future<void> seek(Duration position) async => _service.seek(position);

  @override
  Future<void> skipToNext() async => _service.next();

  @override
  Future<void> skipToPrevious() async => _service.previous();

  @override
  Future<void> skipToQueueItem(int index) async => _service.play(index);
}
