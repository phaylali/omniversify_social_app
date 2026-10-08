import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../data/dummy_data.dart';
import '../data/post_state.dart';
import '../models/post.dart';
import '../services/account_gate.dart';
import '../services/link_preview_service.dart';
import '../services/user_posts.dart';
import '../widgets/action_sheet.dart';
import '../widgets/app_logo.dart';
import '../widgets/link_preview_widget.dart';
import '../services/file_store_stub.dart'
    if (dart.library.io) '../services/file_store.dart';
import '../widgets/file_image_stub.dart'
    if (dart.library.io) '../widgets/file_image.dart';

/// What the composer is building. Three kinds, no metadata forms — a thought,
/// something from the gallery, or a link.
enum ComposerKind { thought, media, link }

/// A real post composer, replacing the old tile grid that only ever fired a
/// SnackBar.
///
/// One screen, one kind at a time: write a thought, pick a photo or a video
/// from the gallery, or paste a link and watch its preview come in. Nothing is
/// published until [mayPost] says the email is confirmed, and nothing leaves
/// the device — the post is persisted locally and prepended to the feed.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  /// Opens the composer. Returns the id of the post if one was published, so
  /// the caller can scroll to it or simply ignore the result.
  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
  }

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();

  ComposerKind _kind = ComposerKind.thought;

  /// Local path of the chosen gallery file, already copied into app storage
  /// only at publish time — until then it is whatever the picker gave us.
  String? _mediaPath;
  bool _mediaIsVideo = false;
  bool _busy = false;

  PostVisibility _visibility = PostVisibility.public;

  static const _uuid = Uuid();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canPost {
    if (_busy) return false;
    switch (_kind) {
      case ComposerKind.thought:
        return _text.text.trim().isNotEmpty;
      case ComposerKind.media:
        return _mediaPath != null;
      case ComposerKind.link:
        return _looksLikeUrl(_text.text.trim());
    }
  }

  /// A link must actually be one: `example.com` or a scheme-qualified URL, so
  /// the preview widget has something to fetch rather than a bare word.
  static bool _looksLikeUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    return uri != null &&
        uri.host.contains('.') &&
        !uri.host.endsWith('.');
  }

  /// The link worth previewing: the first real one in the box — a preview
  /// of the words around it would only ever guess.
  String? get _link {
    final urls = LinkPreviewService.extractUrls(_text.text);
    final value = urls.isNotEmpty ? urls.first : _text.text.trim();
    if (!_looksLikeUrl(value)) return null;
    return value.contains('://') ? value : 'https://$value';
  }

  String get _hint {
    switch (_kind) {
      case ComposerKind.thought:
        return "What's on your mind?";
      case ComposerKind.media:
        return 'Add a caption…';
      case ComposerKind.link:
        return 'https://';
    }
  }

  Future<void> _pickMedia(ImageSource source, {required bool video}) async {
    try {
      final picked = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _mediaPath = picked.path;
        _mediaIsVideo = video;
      });
    } catch (_) {
      // A cancelled or unsupported picker is not worth a dialog.
    }
  }

  void _chooseMedia() {
    showActionSheet(
      context,
      title: 'Add to your post',
      icon: Icons.add_photo_alternate_outlined,
      items: [
        ActionSheetItem(
          icon: Icons.image_outlined,
          title: 'Photo',
          subtitle: 'Pick one image from your gallery',
          onTap: () => _pickMedia(ImageSource.gallery, video: false),
        ),
        ActionSheetItem(
          icon: Icons.videocam_outlined,
          title: 'Video',
          subtitle: 'Pick one video from your gallery',
          onTap: () => _pickMedia(ImageSource.gallery, video: true),
        ),
      ],
    );
  }

  /// Runs the email gate, copies any media into durable storage, publishes and
  /// returns the new id.
  Future<String?> _publish() async {
    if (!_canPost) return null;

    // Browsing is open; writing is not. This may open the account screen and
    // come back signed in and confirmed.
    if (!await mayPost(context)) return null;
    if (!mounted) return null;

    setState(() => _busy = true);

    try {
      String? mediaPath = _mediaPath;
      if (mediaPath != null && _kind == ComposerKind.media) {
        // The picker's path lives in cache and can vanish; ours cannot.
        final name = mediaPath.split('/').last;
        mediaPath = await persistMedia(mediaPath, name);
      }

      final body = _text.text.trim();
      final post = Post(
        id: _uuid.v4(),
        user: currentUser,
        type: _kind == ComposerKind.media
            ? (_mediaIsVideo ? PostType.video : PostType.image)
            : PostType.text,
        text: body,
        imageUrl: _kind == ComposerKind.media && !_mediaIsVideo
            ? mediaPath
            : null,
        videoUrl: _kind == ComposerKind.media && _mediaIsVideo
            ? mediaPath
            : null,
        timestamp: DateTime.now(),
        visibility: _visibility,
      );

      await UserPosts.instance.add(post);
      ref.read(postStateProvider.notifier).register(post);

      if (mounted) Navigator.of(context).pop(post.id);
      return post.id;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not publish that post.')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          key: const ValueKey('composer-close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New post', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const ValueKey('composer-post'),
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerHighest,
                disabledForegroundColor: cs.onSurface.withAlpha(90),
              ),
              onPressed: _canPost ? _publish : null,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _identityRow(cs, gold),
          const SizedBox(height: 14),
          _kindPicker(cs, gold),
          const SizedBox(height: 18),
          if (_kind == ComposerKind.media) ...[
            _mediaTile(cs, gold),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('composer-body'),
            controller: _text,
            autofocus: _kind != ComposerKind.media,
            maxLines: _kind == ComposerKind.media ? 3 : 9,
            minLines: _kind == ComposerKind.media ? 2 : 5,
            maxLength: _kind == ComposerKind.link ? 2048 : 5000,
            keyboardType:
                _kind == ComposerKind.link ? TextInputType.url : TextInputType.multiline,
            // A link is not a sentence: nothing here should come out as
            // `Https://…`.
            textCapitalization: _kind == ComposerKind.link
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _hint,
              counterText: '',
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_kind == ComposerKind.link && _link != null) ...[
            const SizedBox(height: 4),
            LinkPreviewWidget(url: _link!),
          ],
          const Divider(height: 28),
          _visibilityRow(cs, gold),
        ],
      ),
    );
  }

  /// Who is posting, and which audience is currently selected.
  Widget _identityRow(ColorScheme cs, Color gold) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          child: const AppLogo(size: 26, fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentUser.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              Text(
                currentUser.handle,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(150)),
              ),
            ],
          ),
        ),
        Icon(Icons.public, size: 16, color: gold),
      ],
    );
  }

  /// Thought · Photo or video · Link.
  Widget _kindPicker(ColorScheme cs, Color gold) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final entry in const [
            (ComposerKind.thought, Icons.edit_outlined, 'Thought'),
            (ComposerKind.media, Icons.image_outlined, 'Media'),
            (ComposerKind.link, Icons.link, 'Link'),
          ])
            Expanded(
              child: _KindButton(
                selected: _kind == entry.$1,
                icon: entry.$2,
                label: entry.$3,
                gold: gold,
                cs: cs,
                onTap: () => setState(() {
                  if (_kind == entry.$1) return;
                  // Switching kinds drops what does not carry over: a link
                  // field has no meaning on a photo, and vice versa.
                  _kind = entry.$1;
                  _mediaPath = null;
                  _text.clear();
                }),
              ),
            ),
        ],
      ),
    );
  }

  /// Empty: two ways in. Chosen: a preview, tappable to replace, with a way
  /// to clear it.
  Widget _mediaTile(ColorScheme cs, Color gold) {
    final path = _mediaPath;
    if (path == null) {
      return InkWell(
        key: const ValueKey('composer-media'),
        borderRadius: BorderRadius.circular(12),
        onTap: _chooseMedia,
        child: Container(
          height: 168,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(110),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gold.withAlpha(90)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 40, color: gold),
              const SizedBox(height: 8),
              const Text('Choose a photo or video'),
              const SizedBox(height: 2),
              Text(
                'From your gallery',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withAlpha(150)),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _mediaIsVideo
              ? Container(
                  height: 168,
                  width: double.infinity,
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_outline,
                          size: 46, color: Colors.white70),
                      const SizedBox(height: 6),
                      Text(
                        path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                )
              : fileImage(path, height: 168, fit: BoxFit.cover, width: double.infinity),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _roundAction(
                cs,
                icon: Icons.swap_horiz,
                tooltip: 'Replace',
                onTap: _chooseMedia,
              ),
              const SizedBox(width: 8),
              _roundAction(
                cs,
                icon: Icons.close,
                tooltip: 'Remove',
                onTap: () => setState(() => _mediaPath = null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundAction(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  /// Public by default — the feed is public by design. Private is offered, and
  /// private posts are the ones that drop every share entry point.
  Widget _visibilityRow(ColorScheme cs, Color gold) {
    return Row(
      children: [
        Icon(
          _visibility == PostVisibility.public
              ? Icons.public
              : Icons.lock_outline,
          size: 18,
          color: gold,
        ),
        const SizedBox(width: 8),
        Text(
          _visibility == PostVisibility.public
              ? 'Anyone on Omniversify can see this'
              : 'Only you can see this',
          style: TextStyle(fontSize: 13.5, color: cs.onSurface.withAlpha(180)),
        ),
        const Spacer(),
        TextButton(
          key: const ValueKey('composer-visibility'),
          onPressed: () => setState(
            () => _visibility = _visibility == PostVisibility.public
                ? PostVisibility.private
                : PostVisibility.public,
          ),
          child: Text(
            _visibility == PostVisibility.public ? 'Make private' : 'Make public',
            style: TextStyle(color: gold, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.gold,
    required this.cs,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color gold;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? gold.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? gold : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? gold : cs.onSurface.withAlpha(170)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? gold : cs.onSurface.withAlpha(170),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
