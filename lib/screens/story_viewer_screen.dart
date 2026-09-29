import 'package:flutter/material.dart';

import '../models/post.dart';
import '../widgets/action_sheet.dart';

/// Full-screen placeholder for someone's story.
///
/// Real story media doesn't exist yet, so the poster's identity sits over
/// placeholder art while the segment bars, tap-to-advance and auto-advance
/// all behave exactly like the finished feature will.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.users,
    this.initialIndex = 0,
  });

  /// Everyone with a story, in row order.
  final List<PostUser> users;

  /// Which story to open first.
  final int initialIndex;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  /// How long one story segment stays on screen before moving on.
  static const Duration _segment = Duration(seconds: 5);

  late final PageController _page;
  late final AnimationController _progress;
  late int _index;

  /// Reply box for the story on screen — real, focusable, sendable.
  final TextEditingController _reply = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  /// Stories liked this session, by page index, so a like survives swiping.
  final Set<int> _likedStories = <int>{};

  @override
  void initState() {
    super.initState();
    _index = widget.users.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.users.length - 1);
    _page = PageController(initialPage: _index);
    _progress = AnimationController(vsync: this, duration: _segment)
      ..addStatusListener(_onProgressStatus)
      ..forward();
    // Keeps the send button in sync with what has been typed.
    _reply.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    _replyFocus.dispose();
    _progress.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_index >= widget.users.length - 1) {
      Navigator.of(context).pop();
    } else {
      _page.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _goTo(int index) {
    if (index < 0) {
      // Tapping back on the first story just replays it.
      _progress.forward(from: 0);
      return;
    }
    if (index >= widget.users.length) {
      Navigator.of(context).pop();
      return;
    }
    _page.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Right two thirds advance, the left slice goes back — story conventions.
  void _onTapUp(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < width * 0.35) {
      _goTo(_index - 1);
    } else {
      _goTo(_index + 1);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _progress.forward(from: 0);
  }

  /// Story like — stored per page so swiping away and back keeps the heart.
  void _toggleLike() {
    setState(() {
      if (!_likedStories.add(_index)) _likedStories.remove(_index);
    });
  }

  /// Sends whatever is sitting in the reply box.
  ///
  /// Stories have no backend yet, so this confirms the same way the report
  /// actions do rather than pretending to deliver anything.
  void _sendReply() {
    if (_reply.text.trim().isEmpty) return;
    final handle = widget.users[_index].handle;
    _reply.clear();
    FocusScope.of(context).unfocus();
    showActionNotice(context, 'Reply sent to $handle');
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    if (widget.users.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: IconButton(
            iconSize: 30,
            icon: Icon(Icons.close, color: Colors.white.withAlpha(200)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: _onTapUp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _page,
              onPageChanged: _onPageChanged,
              itemCount: widget.users.length,
              itemBuilder: (context, index) =>
                  _PlaceholderStory(user: widget.users[index], gold: gold),
            ),

            // Progress segments + poster identity, on their own scrim.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withAlpha(170), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _segments(gold),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: gold.withAlpha(45),
                              child: Text(
                                widget.users[_index].name[0].toUpperCase(),
                                style: TextStyle(
                                  color: gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.users[_index].name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.users[_index].handle,
                              style: TextStyle(
                                color: Colors.white.withAlpha(150),
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.white.withAlpha(220),
                                size: 24,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Reply bar: a real input and a like button. Each owns its taps —
            // pressing them focuses or likes instead of skipping a story.
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Anything in the bar that isn't the field still focuses it.
                  onTap: () => _replyFocus.requestFocus(),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 4,
                      top: 3,
                      bottom: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(90),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withAlpha(120),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _reply,
                            focusNode: _replyFocus,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendReply(),
                            cursorColor: gold,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText:
                                  'Reply to ${widget.users[_index].handle}',
                              hintStyle: TextStyle(
                                color: Colors.white.withAlpha(170),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Like this story',
                          icon: Icon(
                            _likedStories.contains(_index)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _likedStories.contains(_index)
                                ? Colors.red
                                : Colors.white.withAlpha(200),
                            size: 24,
                          ),
                          onPressed: _toggleLike,
                        ),
                        IconButton(
                          tooltip: 'Send reply',
                          icon: Icon(
                            Icons.send,
                            size: 20,
                            color: _reply.text.trim().isEmpty
                                ? Colors.white.withAlpha(90)
                                : gold,
                          ),
                          onPressed:
                              _reply.text.trim().isEmpty ? null : _sendReply,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Segment bars across the top: filled for stories already seen, animated
  /// for the one on screen, empty for the ones ahead.
  Widget _segments(Color gold) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return Row(
          children: [
            for (var i = 0; i < widget.users.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: i < _index
                          ? 1
                          : i == _index
                              ? _progress.value
                              : 0,
                      minHeight: 3,
                      backgroundColor: Colors.white.withAlpha(60),
                      color: i == _index ? gold : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The placeholder art one story page: gradient, icon and the poster's note.
class _PlaceholderStory extends StatelessWidget {
  const _PlaceholderStory({required this.user, required this.gold});

  final PostUser user;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gold.withAlpha(70),
            Colors.black,
            gold.withAlpha(35),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(90),
                    shape: BoxShape.circle,
                    border: Border.all(color: gold.withAlpha(150), width: 1),
                  ),
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    color: gold,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Story coming soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${user.name} hasn\'t posted a story yet — it will show up right here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withAlpha(170),
                    fontSize: 13,
                    height: 1.4,
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
