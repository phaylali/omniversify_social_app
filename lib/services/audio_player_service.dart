import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song_item.dart';

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
/// - Connects to [audio_service] to expose an Android media notification
///   with play/pause/next/prev/seek controls.
/// - Exposes a [stateStream] that UI widgets listen to for rebuilds.
///
/// All state is held here; the music player screen is a pure consumer.
class AudioPlayerService {
  AudioPlayerService._();
  static final AudioPlayerService instance = AudioPlayerService._();

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
  bool _initialized = false;

  /// audio_service handler for Android notification / media session.
  MusicAudioHandler? _audioHandler;

  /// Emit a state change to the stream and update the media session.
  void _emit() {
    if (!_stateController.isClosed) _stateController.add(null);
    _updateMediaItem();
  }

  /// Initialize player listeners. Safe to call multiple times (idempotent).
  void init() {
    if (_initialized) return;
    _initialized = true;

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
  }

  /// Connect to audio_service for the Android media notification.
  ///
  /// Must be called once after [init]. This sets up the foreground service
  /// notification that shows current track info and playback controls.
  Future<void> connectAudioService() async {
    if (_audioHandler != null) return;
    _audioHandler = MusicAudioHandler(this);
    await AudioService.init(
      builder: () => _audioHandler!,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.omniversify.music',
        androidNotificationChannelName: 'Omniversify Music',
        androidStopForegroundOnPause: true,
        androidNotificationOngoing: true,
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

  void stop() {
    _player.stop();
    _currentIndex = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
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
    _emit();
  }

  // ── Shuffle / Repeat toggles ────────────────────────────

  /// Toggle shuffle on/off. When turned on, builds a new shuffled queue.
  void toggleShuffle() {
    _shuffleOn = !_shuffleOn;
    if (_shuffleOn) {
      _buildShuffleQueue();
    }
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

  /// Push current song metadata to the media session notification.
  void _updateMediaItem() {
    final song = currentSong;
    if (song == null || _audioHandler == null) return;
    _audioHandler!.mediaItem.add(MediaItem(
      id: song.path,
      title: song.title,
      artist: song.artist ?? 'Unknown',
      album: song.album ?? '',
      duration: _duration,
    ));
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
    _service._playlist.asMap().entries.forEach((entry) {
      final song = entry.value;
      queue.add([
        MediaItem(
          id: song.path,
          title: song.title,
          artist: song.artist ?? 'Unknown',
          album: song.album ?? '',
          duration: song.duration != null
              ? Duration(milliseconds: song.duration!)
              : null,
        ),
      ]);
    });

    // Set initial media item if something is already playing.
    final song = _service.currentSong;
    if (song != null) {
      mediaItem.add(MediaItem(
        id: song.path,
        title: song.title,
        artist: song.artist ?? 'Unknown',
        album: song.album ?? '',
        duration: _service.duration,
      ));
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

    // Update media item on every state change so notification stays current.
    final song = _service.currentSong;
    if (song != null) {
      mediaItem.add(MediaItem(
        id: song.path,
        title: song.title,
        artist: song.artist ?? 'Unknown',
        album: song.album ?? '',
        duration: _service.duration,
      ));
    }
  }

  @override
  Future<void> play() async => _service.togglePlay();

  @override
  Future<void> pause() async => _service.togglePlay();

  @override
  Future<void> stop() async {
    _service.stop();
    await super.stop();
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
