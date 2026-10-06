import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/config/api_config.dart';
import '../services/account_gate.dart';
import '../services/messages_service.dart';

/// Instagram-style share sheet:
///  - "Other apps" row on top → native OS share dialog
///  - people list below → multi-select and send in-app
///
/// Sending does not just play a snackbar: the words are written into each
/// picked conversation, so they are waiting in the thread — and the same
/// sheet is what opens when another app shares *into* Omniversify.
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.shareText,
    this.files,
    this.onShared,
  });

  /// Text passed to other apps (and shown in the preview line).
  final String shareText;

  /// Optional files (music player passes the song file).
  final List<XFile>? files;

  /// Called after the user shares via other apps or sends to people
  /// (used to bump the post share count, etc).
  final VoidCallback? onShared;

  /// Opens the sheet. Returns when dismissed.
  static Future<void> show(
    BuildContext context, {
    required String shareText,
    List<XFile>? files,
    VoidCallback? onShared,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(
        shareText: shareText,
        files: files,
        onShared: onShared,
      ),
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final Set<String> _selected = {};

  Future<void> _shareToOtherApps() async {
    Navigator.of(context).pop();
    try {
      await SharePlus.instance.share(
        ShareParams(
          // An empty list makes share_plus' Android side throw "No files
          // found"; null takes its text-only path instead.
          files: (widget.files == null || widget.files!.isEmpty)
              ? null
              : widget.files,
          text: widget.shareText,
        ),
      );
      widget.onShared?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share')),
      );
    }
  }

  Future<void> _send() async {
    final handles = MessagesService.people
        .where((p) => _selected.contains(p.handle))
        .map((p) => p.handle)
        .toList(growable: false);
    if (handles.isEmpty) return;
    // Sending is a message, so it waits for a confirmed email.
    if (!await mayPost(context)) return;
    if (!mounted) return;
    final names =
        handles.map(MessagesService.nameFor).toList(growable: false);
    // Written into every picked conversation first, so the words are there
    // by the time the confirmation appears.
    await MessagesService.instance.shareTo(handles, widget.shareText);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onShared?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sent to ${names.join(', ')}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return Material(
      // The ListTiles paint their ink on the nearest Material: with the
      // sheet's own coloured background in between, those splashes would
      // land behind it and never be seen.
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Title ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Text(
                    'Share',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    Text(
                      '${_selected.length} selected',
                      style: bodySmall?.copyWith(color: gold),
                    ),
                ],
              ),
            ),

            // ── Share preview ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.link, size: 14, color: bodySmall?.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.shareText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Other apps (on top) ──
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: gold.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.apps, color: gold, size: 22),
              ),
              title: const Text('Other apps'),
              subtitle: Text('Open the system share dialog',
                  style: bodySmall?.copyWith(fontSize: 11)),
              trailing: Icon(Icons.chevron_right, color: bodySmall?.color),
              onTap: _shareToOtherApps,
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text('Send to',
                      style: bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Divider(
                          height: 1, color: cs.onSurface.withAlpha(30))),
                ],
              ),
            ),

            // ── People (multi-select) ──
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.38,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: MessagesService.people.length,
                itemBuilder: (context, index) {
                  final person = MessagesService.people[index];
                  final selected = _selected.contains(person.handle);
                  return ListTile(
                    key: ValueKey('share-person-${person.handle}'),
                    dense: true,
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: gold.withAlpha(30),
                      child: Text(
                        person.name[0].toUpperCase(),
                        style: TextStyle(
                            color: gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                    title: Text(person.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(person.handle,
                        style: bodySmall?.copyWith(fontSize: 11)),
                    trailing: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selected.remove(person.handle);
                          } else {
                            _selected.add(person.handle);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? gold : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? gold
                                : cs.onSurface.withAlpha(90),
                            width: 1.5,
                          ),
                        ),
                        child: selected
                            ? Icon(Icons.check,
                                size: 16, color: cs.surface)
                            : null,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selected.remove(person.handle);
                        } else {
                          _selected.add(person.handle);
                        }
                      });
                    },
                  );
                },
              ),
            ),

            // ── Send button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  key: const ValueKey('share-send'),
                  onPressed: _selected.isEmpty ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: cs.surface,
                    disabledBackgroundColor: gold.withAlpha(40),
                    disabledForegroundColor: cs.onSurface.withAlpha(80),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Send',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Share-link for a post, matching the "Copy link" menu item.
String postShareText(String name, String handle, String text) {
  final snippet = text.length > 80 ? '${text.substring(0, 80)}…' : text;
  return '$snippet\n${ApiConfig.omniversifyAppUrl}/post/${handle.replaceAll('@', '')}';
}

/// Share-link for one comment, nested under its post's URL so the receiver
/// lands on that exact comment: `…/post/<handle>/comment/1-c5` or
/// `…/scroll/3/comment/scroll_3-c0`.
String commentShareText(String postId, String commentId, String handle, String text) {
  final base = ApiConfig.omniversifyAppUrl;
  final postUrl = postId.startsWith('scroll_')
      ? '$base/scroll/${postId.substring('scroll_'.length)}'
      : '$base/post/${handle.replaceAll('@', '')}';
  final label = text.isEmpty ? 'Comment by $handle' : (text.length > 80 ? '${text.substring(0, 80)}…' : text);
  return '$label\n$postUrl/comment/$commentId';
}
