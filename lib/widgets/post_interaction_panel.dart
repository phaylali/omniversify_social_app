import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:omniversify_widget/omniversify_widget.dart';
import '../data/post_state.dart';
import '../models/post.dart';
import 'file_image_stub.dart'
    if (dart.library.io) 'file_image.dart';
import 'image_preview.dart';
import 'post_components.dart';
import 'share_sheet.dart';

class PostInteractionPanel extends ConsumerStatefulWidget {
  final String postId;
  final int initialTab;

  /// Comment to scroll to and flash when opened from a shared link.
  final String? initialCommentId;

  const PostInteractionPanel({
    super.key,
    required this.postId,
    this.initialTab = 0,
    this.initialCommentId,
  });

  static void show(
    BuildContext context,
    String postId, {
    int initialTab = 0,
    String? initialCommentId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostInteractionPanel(
        postId: postId,
        initialTab: initialTab,
        initialCommentId: initialCommentId,
      ),
    );
  }

  @override
  ConsumerState<PostInteractionPanel> createState() => _PostInteractionPanelState();
}

class _PostInteractionPanelState extends ConsumerState<PostInteractionPanel> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final postState = ref.watch(postStateProvider)[widget.postId];

    if (postState == null) {
      // Deep link to a post we don't have — say so instead of an empty sheet.
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(32),
        child: const Center(child: Text('Post not found')),
      );
    }

    final tabs = ['Likes (${postState.likes})', 'Comments (${postState.comments})', 'Shares (${postState.shares})'];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Handle ──
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Tab Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(3, (i) {
                    final isSelected = _selectedTab == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isSelected ? gold : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            tabs[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected ? gold : Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),

              // ── Content ──
              Expanded(
                child: _selectedTab == 0
                    ? _LikersList(likers: postState.likers)
                    : _selectedTab == 1
                        ? _CommentsList(
                            postId: widget.postId,
                            highlightId: widget.initialCommentId,
                          )
                        : _SharersList(sharers: postState.sharers),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Likers List ──────────────────────────────────────────────
class _LikersList extends StatelessWidget {
  final List<PostUser> likers;

  const _LikersList({required this.likers});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    if (likers.isEmpty) {
      return Center(
        child: Text('No likes yet', style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: likers.length,
      itemBuilder: (context, index) {
        final user = likers[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: gold.withAlpha(40),
            child: Text(
              user.name[0].toUpperCase(),
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
          ),
          title: Row(
            children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (user.verified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 14, color: gold),
              ],
            ],
          ),
          subtitle: Text(user.handle, style: Theme.of(context).textTheme.bodySmall),
          onTap: () {
            // Tap the row or avatar → this person's profile.
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileViewScreen(user: user),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Comments List ─────────────────────────────────────────────
class _CommentsList extends ConsumerStatefulWidget {
  final String postId;

  /// When opened from a shared comment link, scroll to and flash this comment.
  final String? highlightId;

  const _CommentsList({required this.postId, this.highlightId});

  @override
  ConsumerState<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends ConsumerState<_CommentsList> {
  Comment? _replyingTo;
  final _highlightKey = GlobalKey();
  bool _highlightOn = false;

  @override
  void initState() {
    super.initState();
    if (widget.highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToHighlight());
    }
  }

  Future<void> _jumpToHighlight() async {
    final ctx = _highlightKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450));
    }
    if (!mounted || widget.highlightId == null) return;
    setState(() => _highlightOn = true);
    await Future.delayed(const Duration(milliseconds: 2200));
    if (mounted) setState(() => _highlightOn = false);
  }

  void _startReply(Comment comment) {
    setState(() => _replyingTo = comment);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final postState = ref.watch(postStateProvider)[widget.postId];
    if (postState == null) return const SizedBox.shrink();
    final gold = Theme.of(context).colorScheme.primary;

    final list = postState.commentList;
    if (list.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Text('No comments yet. Be the first!', style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          _CommentInput(postId: widget.postId, replyingTo: null, onCancelReply: _cancelReply),
        ],
      );
    }

    // Top-level comments first, each followed by its one level of replies.
    // A reply to a reply attaches to the top-level ancestor so nothing is lost.
    final byId = {for (final c in list) c.id: c};
    final roots = list.where((c) => c.replyTo == null || !byId.containsKey(c.replyTo)).toList();
    final entries = <(Comment, bool)>[];
    for (final root in roots) {
      entries.add((root, false));
      for (final c in list) {
        var parentId = c.replyTo;
        if (parentId == null) continue;
        while (byId[parentId]?.replyTo != null) {
          parentId = byId[parentId]!.replyTo!;
        }
        if (parentId == root.id) entries.add((c, true));
      }
    }

    return Column(
      children: [
        // ── Comments list ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final (comment, isReply) in entries)
                Padding(
                  padding: EdgeInsets.only(bottom: 12, left: isReply ? 28 : 0),
                  child: Container(
                    key: comment.id == widget.highlightId ? _highlightKey : null,
                    decoration: BoxDecoration(
                      color: (comment.id == widget.highlightId && _highlightOn)
                          ? gold.withAlpha(35)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: isReply
                        ? Container(
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: Theme.of(context).dividerColor.withAlpha(120),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: _CommentTile(
                              postId: widget.postId,
                              comment: comment,
                              onReply: _startReply,
                            ),
                          )
                        : _CommentTile(
                            postId: widget.postId,
                            comment: comment,
                            onReply: _startReply,
                          ),
                  ),
                ),
            ],
          ),
        ),

        // ── Comment input ──
        _CommentInput(
          postId: widget.postId,
          replyingTo: _replyingTo,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final String postId;
  final Comment comment;
  final ValueChanged<Comment> onReply;

  const _CommentTile({
    required this.postId,
    required this.comment,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gold = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              // Commenter's avatar → their profile.
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileViewScreen(user: comment.user),
                ),
              );
            },
            child: CircleAvatar(
              radius: 16,
              backgroundColor: gold.withAlpha(40),
              child: Text(
                comment.user.name[0].toUpperCase(),
                style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.user.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (comment.user.verified) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.verified, size: 12, color: gold),
                    ],
                    const SizedBox(width: 6),
                    Text(comment.user.handle, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
                    const SizedBox(width: 5),
                    Text('· ${compactAgo(comment.timestamp)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                if (comment.text.isNotEmpty)
                  Text(comment.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14)),
                if (comment.imagePath != null || comment.imageBytes != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      if (comment.imageBytes != null) {
                        ImagePreview.showMemory(context, comment.imageBytes!);
                      } else {
                        ImagePreview.showFile(context, comment.imagePath!);
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: comment.imageBytes != null
                            ? Image.memory(
                                comment.imageBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, _, _) => Container(
                                  height: 120,
                                  alignment: Alignment.center,
                                  child: Text('Image unavailable', style: Theme.of(context).textTheme.bodySmall),
                                ),
                              )
                            : fileImage(
                                comment.imagePath!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, _, _) => Container(
                                  height: 120,
                                  alignment: Alignment.center,
                                  child: Text('Image unavailable', style: Theme.of(context).textTheme.bodySmall),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Like / reply / share as one compact row on the right ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => ref.read(postStateProvider.notifier).toggleCommentLike(postId, comment.id),
                child: Icon(
                  comment.likedByMe ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: comment.likedByMe ? Colors.redAccent : muted,
                ),
              ),
              if (comment.likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text('${comment.likeCount}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => onReply(comment),
                child: Icon(Icons.reply, size: 16, color: muted),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  ShareSheet.show(
                    context,
                    shareText: commentShareText(postId, comment.id, comment.user.handle, comment.text),
                    onShared: () => ref.read(postStateProvider.notifier).share(postId),
                  );
                },
                child: Icon(Icons.share_outlined, size: 15, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentInput extends ConsumerStatefulWidget {
  final String postId;

  /// Non-null while replying — shows the chip and attaches `replyTo`.
  final Comment? replyingTo;
  final VoidCallback onCancelReply;

  const _CommentInput({
    required this.postId,
    required this.replyingTo,
    required this.onCancelReply,
  });

  @override
  ConsumerState<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<_CommentInput> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();

  /// Extensions allowed for comment images (jpeg, jpg, png, webp, gif).
  static const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

  String? _imagePath;
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final fileName = picked.path.split('/').last;
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1) {
        final ext = fileName.substring(dotIndex + 1).toLowerCase();
        if (!_allowedExtensions.contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unsupported format — use jpeg, jpg, png, webp or gif'),
              ),
            );
          }
          return;
        }
      }

      if (kIsWeb) {
        // No real file paths on web — keep the bytes instead.
        final bytes = await picked.readAsBytes();
        if (mounted) setState(() { _imageBytes = bytes; _imagePath = null; });
      } else if (mounted) {
        setState(() { _imagePath = picked.path; _imageBytes = null; });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the gallery')),
        );
      }
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    final imagePath = _imagePath;
    final imageBytes = _imageBytes;
    if (text.isEmpty && imagePath == null && imageBytes == null) return;
    ref.read(postStateProvider.notifier).addComment(
      widget.postId,
      text,
      const PostUser(name: 'Youssef', handle: '@youssef_ma', verified: true),
      imagePath: imagePath,
      imageBytes: imageBytes,
      replyTo: widget.replyingTo?.id,
    );
    _controller.clear();
    setState(() { _imagePath = null; _imageBytes = null; });
    if (widget.replyingTo != null) widget.onCancelReply();
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final replyingTo = widget.replyingTo;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Replying-to chip ──
            if (replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.reply, size: 14, color: gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to ${replyingTo.user.handle}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onCancelReply,
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),

            // ── Attachment preview ──
            if (_imagePath != null || _imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _imageBytes != null
                          ? Image.memory(
                              _imageBytes!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 72,
                                height: 72,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.broken_image_outlined, color: gold),
                              ),
                            )
                          : fileImage(
                              _imagePath!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 72,
                                height: 72,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.broken_image_outlined, color: gold),
                              ),
                            ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() { _imagePath = null; _imageBytes = null; }),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                // Media buttons
                IconButton(
                  icon: Icon(Icons.image_outlined, size: 22, color: gold),
                  onPressed: _pickImage,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                IconButton(
                  icon: Icon(Icons.gif_box_outlined, size: 22, color: gold),
                  onPressed: _pickImage,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
                // Input
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _controller,
                      autofocus: replyingTo != null,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: replyingTo != null
                            ? 'Write a reply…'
                            : (_imagePath != null || _imageBytes != null)
                                ? 'Add a caption…'
                                : 'Write a comment...',
                        hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                // Send
                GestureDetector(
                  onTap: _submit,
                  child: Icon(Icons.send, size: 20, color: gold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sharers List ─────────────────────────────────────────────
class _SharersList extends StatelessWidget {
  final List<PostUser> sharers;

  const _SharersList({required this.sharers});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    if (sharers.isEmpty) {
      return Center(
        child: Text('No shares yet', style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sharers.length,
      itemBuilder: (context, index) {
        final user = sharers[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: gold.withAlpha(40),
            child: Text(
              user.name[0].toUpperCase(),
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
          ),
          title: Row(
            children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (user.verified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 14, color: gold),
              ],
            ],
          ),
          subtitle: Text(user.handle, style: Theme.of(context).textTheme.bodySmall),
          onTap: () {
            // Tap the row or avatar → this person's profile.
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileViewScreen(user: user),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Profile View Screen (dynamic) ─────────────────────────────
class ProfileViewScreen extends StatelessWidget {
  final PostUser user;

  const ProfileViewScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: OmniversifyAppBar(title: user.name),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: gold.withAlpha(40),
            child: Text(
              user.name[0].toUpperCase(),
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: gold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(user.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (user.verified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 20, color: gold),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(user.handle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat(context, 'Posts', '12'),
              _stat(context, 'Following', '89'),
              _stat(context, 'Followers', '456'),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: OmniFilledButton(
              label: 'Follow',
              icon: Icons.person_add_outlined,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
