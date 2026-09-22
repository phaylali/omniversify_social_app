import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class AppVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool showControls;
  final BoxFit fit;

  const AppVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.showControls = true,
    this.fit = BoxFit.contain,
  });

  @override
  State<AppVideoPlayer> createState() => _AppVideoPlayerState();
}

class _AppVideoPlayerState extends State<AppVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  bool _showPlayOverlay = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Video(
            controller: _controller,
            fit: widget.fit,
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
      if (mounted) setState(() => _hasError = true);
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
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void didUpdateWidget(ScrollVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
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
        child: IconButton(
          icon: Icon(Icons.error_outline,
              color: Colors.white.withAlpha(120), size: 48),
          onPressed: () {
            setState(() {
              _hasError = false;
              _isBuffering = true;
            });
            _openVideo();
          },
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _player.state.width?.toDouble() ?? MediaQuery.of(context).size.width,
            height: _player.state.height?.toDouble() ?? MediaQuery.of(context).size.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Video(controller: _controller),
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
