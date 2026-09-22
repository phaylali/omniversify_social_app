import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omniversify_widget/omniversify_widget.dart';
import '../data/post_state.dart';
import '../models/post.dart';

class PostInteractionPanel extends ConsumerStatefulWidget {
  final String postId;
  final int initialTab;

  const PostInteractionPanel({
    super.key,
    required this.postId,
    this.initialTab = 0,
  });

  static void show(BuildContext context, String postId, {int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostInteractionPanel(postId: postId, initialTab: initialTab),
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
    if (postState == null) return const SizedBox.shrink();

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
                        ? _CommentsList(postId: widget.postId)
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
          trailing: OmniOutlinedButton(
            label: 'View',
            fullWidth: false,
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileViewScreen(user: user),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Comments List ─────────────────────────────────────────────
class _CommentsList extends ConsumerWidget {
  final String postId;

  const _CommentsList({required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postState = ref.watch(postStateProvider)[postId];
    if (postState == null) return const SizedBox.shrink();

    return Column(
      children: [
        // ── Comments list ──
        Expanded(
          child: postState.commentList.isEmpty
              ? Center(
                  child: Text('No comments yet. Be the first!', style: Theme.of(context).textTheme.bodySmall),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: postState.commentList.length,
                  itemBuilder: (context, index) {
                    final comment = postState.commentList[index];
                    return _CommentTile(comment: comment);
                  },
                ),
        ),

        // ── Comment input ──
        _CommentInput(postId: postId),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: gold.withAlpha(40),
            child: Text(
              comment.user.name[0].toUpperCase(),
              style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.bold),
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
                  ],
                ),
                const SizedBox(height: 3),
                Text(comment.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentInput extends ConsumerStatefulWidget {
  final String postId;

  const _CommentInput({required this.postId});

  @override
  ConsumerState<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<_CommentInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(postStateProvider.notifier).addComment(
      widget.postId,
      text,
      const PostUser(name: 'Youssef', handle: '@youssef_ma', verified: true),
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Media buttons
            IconButton(
              icon: Icon(Icons.image_outlined, size: 22, color: gold),
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
            IconButton(
              icon: Icon(Icons.gif_box_outlined, size: 22, color: gold),
              onPressed: () {},
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
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
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
