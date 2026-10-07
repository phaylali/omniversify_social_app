import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Which way up the screen should lock for a clip of this size.
///
/// Portrait keeps the phone upright — media_kit would otherwise turn it on
/// its side for every clip, letterboxing a vertical video between two black
/// columns. Landscape takes the width of the screen, as it always has. A
/// clip whose size has not been read yet counts as landscape, which is
/// exactly what happened before this existed.
@visibleForTesting
List<DeviceOrientation> orientationsForClip(int width, int height) {
  const landscape = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  if (width <= 0 || height <= 0) return landscape;
  // A square fills more of an upright screen than a sideways one.
  return height >= width
      ? const [DeviceOrientation.portraitUp]
      : landscape;
}

/// Fullscreen in the shape of the clip rather than in one shape for all.
///
/// media_kit locks the phone to landscape every time, so watching a vertical
/// video meant turning the device on its side to see a strip of picture
/// between two black columns. The screen now follows what is on it: a
/// portrait clip keeps the device upright, a landscape one takes the width.
Future<void> _enterFullscreenFor(int width, int height) async {
  await _setScreen(orientationsForClip(width, height));
}

/// Put the screen back: system bars restored, rotation handed to the sensor,
/// which is how the rest of the app behaves — it never picks an orientation.
Future<void> _exitToSensor() => _setScreen(null);

/// [orientations] null means every orientation, i.e. let the sensor decide.
Future<void> _setScreen(List<DeviceOrientation>? orientations) async {
  try {
    await SystemChrome.setEnabledSystemUIMode(
      orientations == null ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
      overlays: orientations == null ? SystemUiOverlay.values : const [],
    );
    await SystemChrome.setPreferredOrientations(orientations ?? const []);
  } catch (exception, stacktrace) {
    // A device that refuses to rotate still plays the video.
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}

class AppVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool showControls;
  final BoxFit fit;

  /// Size the player to the clip instead of to the box it was handed.
  ///
  /// A vertical video inside a fixed landscape box is a stamp-sized strip of
  /// picture between two black bars. With this on, the frame takes the shape
  /// of what it is actually playing — tall for a portrait clip, wide for a
  /// landscape one — up to 220 on the long edge.
  final bool hugVideo;

  const AppVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.showControls = true,
    this.fit = BoxFit.contain,
    this.hugVideo = false,
  });

  @override
  State<AppVideoPlayer> createState() => _AppVideoPlayerState();
}

class _AppVideoPlayerState extends State<AppVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  bool _showPlayOverlay = false;
  bool _isBuffering = false;

  /// The clip's own size in pixels, once the header has been read. Until
  /// then the box keeps the shape it has always had, rather than jumping
  /// around while the file opens.
  int? _videoWidth;
  int? _videoHeight;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() {});
    });

    _player.stream.width.listen((width) {
      if (mounted) setState(() => _videoWidth = width);
    });

    _player.stream.height.listen((height) {
      if (mounted) setState(() => _videoHeight = height);
    });

    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _player.stream.completed.listen((completed) {
      if (completed && mounted) {
        setState(() => _showPlayOverlay = true);
      }
    });

    _player.open(Media(widget.url), play: widget.autoPlay);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() {
    _player.playOrPause();
    setState(() => _showPlayOverlay = false);
  }

  /// The box this clip wants, or null when it should fill its parent — the
  /// feed already wraps the player in the aspect ratio it wants.
  Size? _box() {
    if (!widget.hugVideo) return null;
    final width = _videoWidth ?? 0;
    final height = _videoHeight ?? 0;
    if (width <= 0 || height <= 0) return const Size(220, 150);
    const maxSide = 220.0;
    final scale = maxSide / (width > height ? width : height);
    return Size(width * scale, height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final player = GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Video(
            controller: _controller,
            fit: widget.fit,
            onEnterFullscreen: () =>
                _enterFullscreenFor(_videoWidth ?? 0, _videoHeight ?? 0),
            onExitFullscreen: _exitToSensor,
          ),

          if (_isBuffering)
            const Center(
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),

          if (_showPlayOverlay || !_player.state.playing)
            Container(
              color: Colors.black26,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white.withAlpha(200),
                size: 56,
              ),
            ),
        ],
      ),
    );

    final box = _box();
    if (box == null) return player;
    return SizedBox(width: box.width, height: box.height, child: player);
  }
}

class ScrollVideoPlayer extends StatefulWidget {
  final String url;
  final bool isActive;

  const ScrollVideoPlayer({
    super.key,
    required this.url,
    required this.isActive,
  });

  @override
  State<ScrollVideoPlayer> createState() => _ScrollVideoPlayerState();
}

class _ScrollVideoPlayerState extends State<ScrollVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  bool _isBuffering = true;
  bool _hasError = false;
  bool _isPlaying = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _player.stream.error.listen((error) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _error = error;
        });
      }
    });

    // Rebuild when dimensions resolve so cover-fit has real sizes.
    _player.stream.width.listen((_) {
      if (mounted) setState(() {});
    });
    _player.stream.height.listen((_) {
      if (mounted) setState(() {});
    });

    _openVideo();
  }

  Future<void> _openVideo() async {
    try {
      // Loop like a real scrolls feed; open already playing when active
      // so the first visible page does not wait for didUpdateWidget,
      // which never fires for the initial page.
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.open(Media(widget.url), play: widget.isActive);
      if (widget.isActive) {
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void didUpdateWidget(ScrollVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _hasError = false;
      _error = '';
      _isBuffering = true;
      _openVideo();
      return;
    }
    if (widget.isActive && !oldWidget.isActive) {
      _player.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _player.pause();
      _player.seek(Duration.zero);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.error_outline,
                  color: Colors.white.withAlpha(120), size: 48),
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _error = '';
                  _isBuffering = true;
                });
                _openVideo();
              },
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final screen = MediaQuery.of(context).size;
    final width = (_player.state.width ?? 0) > 0
        ? _player.state.width!.toDouble()
        : screen.width;
    final height = (_player.state.height ?? 0) > 0
        ? _player.state.height!.toDouble()
        : screen.height;

    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Video(
                  controller: _controller,
                  fit: BoxFit.cover,
                  onEnterFullscreen: () => _enterFullscreenFor(
                      _player.state.width ?? 0, _player.state.height ?? 0),
                  onExitFullscreen: _exitToSensor,
                ),
                if (_isBuffering)
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                if (!_isBuffering && !_isPlaying)
                  Container(
                    color: Colors.black26,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white.withAlpha(200),
                      size: 72,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
