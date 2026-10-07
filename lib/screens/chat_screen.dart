import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../services/account_gate.dart';
import '../services/messages_service.dart';
import '../widgets/action_sheet.dart';
import '../widgets/image_preview.dart';
import '../widgets/share_sheet.dart';
import '../widgets/video_player.dart';
import '../services/file_store_stub.dart'
    if (dart.library.io) '../services/file_store.dart';
import '../widgets/file_image_stub.dart'
    if (dart.library.io) '../widgets/file_image.dart';
import '../services/video_thumb_stub.dart'
    if (dart.library.io) '../services/video_thumb.dart';

/// One direct message conversation: the thread, the bar to type in, and the
/// things every chat screen offers — call buttons, a conversation menu,
/// long-press on a message.
///
/// The thread itself lives in [MessagesService], so a link shared from
/// another app is waiting here, and anything sent here shows up in the
/// drawer's last line.
///
/// A message can carry a photo, a video, a file or a voice note as well as
/// words. Anything staged is copied into app storage on send, because the path
/// a picker hands back is not ours to keep.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.handle, this.name});

  /// Who the conversation is with.
  final String handle;

  /// How they are shown — falls back to the first name we know them by.
  final String? name;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// What is waiting in the composer to be sent: a picked file, or a voice note
/// that was just recorded. Copied into app storage only at send time.
class _Staged {
  const _Staged({
    required this.kind,
    required this.path,
    this.name,
    this.seconds,
  });

  final ChatAttachment kind;
  final String path;
  final String? name;
  final int? seconds;
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _canSend = false;

  /// A photo, video, file or voice note waiting to go out with the next send.
  _Staged? _staged;

  String get _name => widget.name ?? MessagesService.nameFor(widget.handle);

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final canSend = _input.text.trim().isNotEmpty || _staged != null;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
    // The conversation is open, so whatever was waiting in it is read now.
    // Loading comes first: the thread starts empty until init fills it, and
    // markRead would otherwise return early on an unread set it cannot see.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await MessagesService.instance.init();
      if (!mounted) return;
      await MessagesService.instance.markRead(widget.handle);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Words on their own, or words plus whatever is staged. Either way the
  /// email gate runs first — the composer is a posting action like any other.
  Future<void> _send() async {
    final staged = _staged;
    final text = _input.text.trim();
    if (text.isEmpty && staged == null) return;
    // Posting needs a confirmed email — and whatever was typed stays put
    // if the person comes back without one.
    if (!await mayPost(context)) return;
    if (!mounted) return;

    _input.clear();
    setState(() => _staged = null);
    _canSend = false;

    if (staged == null) {
      await MessagesService.instance.send(widget.handle, text);
      return;
    }

    try {
      // The picker's path can be revoked or cleared; this one cannot.
      final path = await persistMedia(
        staged.path,
        staged.name ?? staged.kind.name,
      );
      await MessagesService.instance.sendAttachment(
        widget.handle,
        attachment: staged.kind,
        path: path,
        name: staged.name,
        text: text,
        seconds: staged.seconds,
      );
    } catch (_) {
      if (!mounted) return;
      // Put it back rather than dropping what the person chose.
      setState(() {
        _staged = staged;
        _canSend = true;
      });
      showActionNotice(context, 'Could not attach that — try again');
    }
  }

  // ── Attaching ────────────────────────────────────────────────────────

  void _attach() {
    showActionSheet(
      context,
      title: 'Add to your message',
      icon: Icons.add_circle_outline,
      items: [
        ActionSheetItem(
          icon: Icons.image_outlined,
          title: 'Photo',
          subtitle: 'From your gallery',
          onTap: () => _pickFromGallery(video: false),
        ),
        ActionSheetItem(
          icon: Icons.videocam_outlined,
          title: 'Video',
          subtitle: 'From your gallery',
          onTap: () => _pickFromGallery(video: true),
        ),
        ActionSheetItem(
          icon: Icons.attach_file,
          title: 'File',
          subtitle: 'Any document, archive or track',
          onTap: _pickFile,
        ),
        ActionSheetItem(
          icon: Icons.mic_none_outlined,
          title: 'Voice note',
          subtitle: 'Record it instead of typing it',
          onTap: _recordVoice,
        ),
      ],
    );
  }

  Future<void> _pickFromGallery({required bool video}) async {
    try {
      final picked = video
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      setState(() {
        _staged = _Staged(
          kind: video ? ChatAttachment.video : ChatAttachment.image,
          path: picked.path,
          name: picked.name,
        );
        _canSend = true;
      });
    } catch (_) {
      // A picker that never opened is not worth a dialog.
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final file = files.first;
      final path = file.path;
      if (path == null || !mounted) return;
      setState(() {
        _staged = _Staged(
          kind: ChatAttachment.file,
          path: path,
          name: file.name,
        );
        _canSend = true;
      });
    } catch (_) {
      // Same as the gallery: no file chosen, no message.
    }
  }

  /// Stage a GIF picked off the device.
  ///
  /// Deliberately local: the GIFs already saved are the ones worth sending,
  /// and nothing is looked up on a stranger's server to send one. It goes
  /// out as a picture — which is what a GIF is — and keeps its extension
  /// through app storage, so it still moves for whoever receives it.
  Future<void> _pickGif() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gif'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final path = file.path;
      if (path == null || !mounted) return;
      setState(() {
        _staged = _Staged(
          kind: ChatAttachment.image,
          path: path,
          name: file.name,
        );
        _canSend = true;
      });
    } catch (_) {
      // No picker, no GIF — and no error dialog in the middle of a chat.
    }
  }

  Future<void> _recordVoice() async {
    final recorded = await showModalBottomSheet<_Recorded>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _VoiceNoteSheet(),
    );
    if (recorded == null || !mounted) return;
    setState(() {
      _staged = _Staged(
        kind: ChatAttachment.audio,
        path: recorded.path,
        name: null,
        seconds: recorded.seconds,
      );
      _canSend = true;
    });
  }

  void _clearStaged() => setState(() {
        _staged = null;
        _canSend = _input.text.trim().isNotEmpty;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: gold.withAlpha(30),
              child: Text(
                _name.isEmpty ? '?' : _name[0],
                style: TextStyle(
                  color: gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.handle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(150),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => showActionNotice(context, 'Calls are coming soon'),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Call',
            onPressed: () => showActionNotice(context, 'Calls are coming soon'),
          ),
          IconButton(
            key: const ValueKey('chat-menu'),
            icon: const Icon(Icons.more_vert),
            tooltip: 'Conversation menu',
            onPressed: _showMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _thread(cs, gold)),
          _composer(cs, gold),
        ],
      ),
    );
  }

  // ── The thread ───────────────────────────────────────────────────────

  Widget _thread(ColorScheme cs, Color gold) {
    return ValueListenableBuilder<Map<String, List<ChatMessage>>>(
      valueListenable: MessagesService.instance.threads,
      builder: (context, threads, _) {
        final messages = threads[widget.handle] ?? const <ChatMessage>[];
        final rows = _rows(messages);
        if (rows.isEmpty) return _emptyState(cs, gold);

        // Reversed, so the newest line sits at offset 0 and typing never
        // pushes the conversation out from under the composer.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final message = row.message;
            if (message == null) return _dayChip(cs, row.day!);
            return GestureDetector(
              onLongPress: () => _showMessageMenu(message),
              child: _bubble(message, cs, gold),
            );
          },
        );
      },
    );
  }

  /// A chip before each day's group, then the whole thing reversed: the list
  /// runs newest-first so [ListView.reverse] can scroll from the bottom, and
  /// reversing turns "chip first" into "chip above", which is where a day
  /// divider belongs.
  static List<_Row> _rows(List<ChatMessage> messages) {
    final rows = <_Row>[];
    DateTime? seen;
    for (final message in messages) {
      final day =
          DateTime(message.at.year, message.at.month, message.at.day);
      if (day != seen) {
        rows.add(_Row.day(day));
        seen = day;
      }
      rows.add(_Row.message(message));
    }
    return rows.reversed.toList();
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(day.year, day.month, day.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) {
      return const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][day.weekday - 1];
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]} ${day.year}';
  }

  Widget _dayChip(ColorScheme cs, DateTime day) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _dayLabel(day),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withAlpha(160),
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage message, ColorScheme cs, Color gold) {
    final mine = message.fromMe;
    // A photo and a video are the picture: nothing behind them. Everything
    // else is gold — dimmed, because at full strength it shouts over the
    // thread, but not so far that the dark words on it lose their footing.
    final media = message.attachment == ChatAttachment.image ||
        message.attachment == ChatAttachment.video;
    final fill = media
        ? Colors.transparent
        : mine
            ? gold.withAlpha(179)
            : cs.surfaceContainerHighest;
    // Light words once the gold is gone, dark words while it is there.
    final ink = mine && !media ? cs.onPrimary : cs.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(mine ? 56 : 0, 3, mine ? 0 : 56, 3),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.hasAttachment)
              _attachment(message, cs, gold, ink),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(fontSize: 15, height: 1.35, color: ink),
              ),
            const SizedBox(height: 2),
            Text(
              message.clock,
              style: TextStyle(fontSize: 10, color: ink.withAlpha(170)),
            ),
          ],
        ),
      ),
    );
  }

  /// The payload itself: a photo to tap open, a video that plays in place, a
  /// voice note with its own controls, or a file with a name.
  Widget _attachment(
    ChatMessage message,
    ColorScheme cs,
    Color gold,
    Color ink,
  ) {
    final path = message.path ?? '';
    switch (message.attachment) {
      case ChatAttachment.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              key: const ValueKey('bubble-image'),
              onTap: () => ImagePreview.showFile(context, path),
              child: fileImage(
                path,
                width: 220,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _broken(cs, gold),
              ),
            ),
          ),
        );
      case ChatAttachment.video:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _VideoBubble(path: path, name: message.name),
        );
      case ChatAttachment.audio:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _AudioBubble(path: path, seconds: message.seconds, ink: ink),
        );
      case ChatAttachment.file:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            key: const ValueKey('bubble-file'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => ShareSheet.show(
              context,
              shareText: message.name ?? 'File',
              files: [XFile(path)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 26, color: ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.name ?? 'File',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      Text(
                        'Sent a file · tap to open',
                        style: TextStyle(
                          fontSize: 11,
                          color: ink.withAlpha(170),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case null:
        return const SizedBox.shrink();
    }
  }

  Widget _broken(ColorScheme cs, Color gold) {
    return Container(
      width: 220,
      height: 200,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, size: 40, color: gold),
    );
  }

  Widget _emptyState(ColorScheme cs, Color gold) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: gold.withAlpha(30),
              child: Text(
                _name.isEmpty ? '?' : _name[0],
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: gold,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Say hi to $_name 👋', style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'This conversation starts with your first message.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── The composer ─────────────────────────────────────────────────────

  Widget _composer(ColorScheme cs, Color gold) {
    final staged = _staged;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (staged != null) _stagedRow(staged, cs, gold),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('chat-gif'),
                  icon: const Icon(Icons.gif),
                  tooltip: 'GIF',
                  style: IconButton.styleFrom(
                    foregroundColor: gold,
                    disabledForegroundColor: cs.onSurface.withAlpha(70),
                  ),
                  onPressed: _pickGif,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message $_name…',
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('chat-attach'),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Attach',
                  style: IconButton.styleFrom(
                    foregroundColor: gold,
                    disabledForegroundColor: cs.onSurface.withAlpha(70),
                  ),
                  onPressed: _attach,
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('chat-send'),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: cs.onPrimary,
                    disabledBackgroundColor: gold.withAlpha(40),
                    disabledForegroundColor: cs.onSurface.withAlpha(80),
                  ),
                  onPressed: _canSend ? _send : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// What is about to go out, with a way to change their mind before it does.
  Widget _stagedRow(_Staged staged, ColorScheme cs, Color gold) {
    return StagedAttachmentBar(
      kind: staged.kind,
      path: staged.path,
      name: staged.name,
      seconds: staged.seconds,
      cs: cs,
      gold: gold,
      onRemove: _clearStaged,
    );
  }

  // ── Long-press on the message ────────────────────────────────────────

  void _showMessageMenu(ChatMessage message) {
    showActionSheet(
      context,
      title: 'Message',
      subtitle: message.clock,
      items: [
        if (message.text.isNotEmpty)
          ActionSheetItem(
            icon: Icons.copy_outlined,
            title: 'Copy text',
            subtitle: 'Paste it somewhere else',
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.text));
              showActionNotice(context, 'Copied to clipboard');
            },
          ),
        ActionSheetItem(
          icon: Icons.delete_outline,
          title: 'Delete for me',
          subtitle: 'Take it out of this conversation',
          tone: ActionSheetTone.destructive,
          onTap: () async {
            await MessagesService.instance.remove(widget.handle, message);
            if (!mounted) return;
            showActionNotice(context, 'Message deleted');
          },
        ),
      ],
    );
  }

  // ── The conversation menu ────────────────────────────────────────────

  void _showMenu() {
    final handle = widget.handle;
    showActionSheet(
      context,
      title: _name,
      subtitle: handle,
      items: [
        ActionSheetItem(
          icon: Icons.delete_outline,
          title: 'Clear conversation',
          subtitle: 'Remove every message here',
          tone: ActionSheetTone.destructive,
          onTap: () async {
            await MessagesService.instance.clear(handle);
            if (!mounted) return;
            showActionNotice(context, 'Conversation cleared');
          },
        ),
        ActionSheetItem(
          icon: Icons.block,
          title: 'Block',
          subtitle: 'Stop messaging $handle',
          tone: ActionSheetTone.destructive,
          onTap: () => showActionNotice(context, '$handle blocked'),
        ),
        ActionSheetItem(
          icon: Icons.flag_outlined,
          title: 'Report user',
          subtitle: 'Tell us about $handle',
          onTap: () => showActionNotice(
            context,
            'Thanks — your report about $handle is in review',
          ),
        ),
      ],
    );
  }
}

/// A finished recording, handed back from the sheet that made it.
class _Recorded {
  const _Recorded({required this.path, required this.seconds});

  final String path;
  final int seconds;
}

/// Records one voice note: a button to begin, a red dot and a running clock
/// while it runs, then send it or throw it away.
///
/// Nothing here can assume the microphone works — permission can be refused
/// and the platform can be missing — so every way out says what happened
/// rather than spinning. And nothing is *asked* until the button is pressed:
/// a sheet that prompts for the microphone the moment it opens is a prompt
/// nobody read.
class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet();

  @override
  State<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

enum _VoiceStage { idle, starting, recording, finished, blocked }

class _VoiceNoteSheetState extends State<_VoiceNoteSheet> {
  /// Created on the first attempt rather than in the field: the recorder
  /// talks to the platform from its own constructor, and a future nobody
  /// awaits is an error nobody sees.
  AudioRecorder? _recorder;
  Timer? _ticker;

  _VoiceStage _stage = _VoiceStage.idle;

  /// Set when the microphone could not be used at all.
  String? _blocked;

  String? _path;
  int _seconds = 0;

  /// Flipped once the recording has been handed back, so [dispose] knows to
  /// leave the file alone.
  bool _sent = false;

  @override
  void dispose() {
    _ticker?.cancel();
    final recorder = _recorder;
    // Nobody is left to report to once this sheet is gone, so a platform
    // that refuses to let go is swallowed here instead of thrown on the floor.
    if (recorder != null) recorder.dispose().catchError((_) {});
    // A recording nobody sent is a file nobody needs. One that was sent has
    // to survive this — the composer copies it into app storage on its way
    // out, which happens after this sheet is already gone.
    if (!_sent && _path != null) _discard(_path);
    super.dispose();
  }

  Future<void> _discard(String? path) {
    if (path == null || path.isEmpty) return Future.value();
    return deleteMedia(path);
  }

  void _block(String why) {
    if (!mounted) return;
    setState(() {
      _stage = _VoiceStage.blocked;
      _blocked = why;
    });
  }

  Future<void> _begin() async {
    // A take being replaced is a file nobody will hear.
    final previous = _path;
    if (previous != null) _discard(previous);

    setState(() {
      _stage = _VoiceStage.starting;
      _blocked = null;
      _seconds = 0;
      _path = null;
    });

    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) status = await Permission.microphone.request();
      if (!status.isGranted) {
        _block('Microphone access is off, so a voice note cannot be recorded.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      final recorder = _recorder ??= AudioRecorder();
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _path = path;
        _stage = _VoiceStage.recording;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _stage == _VoiceStage.recording) {
          setState(() => _seconds++);
        }
      });
    } catch (_) {
      _block('Recording could not start on this device.');
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    try {
      final recorder = _recorder;
      final path = recorder == null ? _path : await recorder.stop();
      if (!mounted) return;
      setState(() {
        _stage = _VoiceStage.finished;
        _path = path ?? _path;
      });
    } catch (_) {
      _block('Recording could not be saved.');
    }
  }

  void _cancel() {
    _ticker?.cancel();
    Navigator.of(context).pop();
  }

  void _send() {
    final path = _path;
    if (path == null) return;
    _sent = true;
    Navigator.of(context).pop(_Recorded(path: path, seconds: _seconds));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Voice note',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _body(cs, gold),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs, Color gold) {
    switch (_stage) {
      case _VoiceStage.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_outlined, size: 44, color: gold),
            const SizedBox(height: 10),
            Text(
              'Say it instead of typing it.',
              style: TextStyle(
                fontSize: 13.5,
                color: cs.onSurface.withAlpha(190),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You will be asked for the microphone first.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('voice-cancel'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('voice-start'),
                  style: FilledButton.styleFrom(backgroundColor: gold),
                  onPressed: _begin,
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('Start recording'),
                ),
              ],
            ),
          ],
        );

      case _VoiceStage.starting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Getting the microphone ready…',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withAlpha(170),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('voice-cancel'),
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
          ],
        );

      case _VoiceStage.blocked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_off_outlined,
              size: 38,
              color: cs.onSurface.withAlpha(140),
            ),
            const SizedBox(height: 10),
            Text(
              _blocked ?? 'The microphone could not be used.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: cs.onSurface.withAlpha(190),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('voice-cancel'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('voice-settings'),
                  style: FilledButton.styleFrom(backgroundColor: gold),
                  onPressed: openAppSettings,
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ],
        );

      case _VoiceStage.recording:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ChatMessage.clockDuration(_seconds),
                  key: const ValueKey('voice-timer'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Recording',
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurface.withAlpha(160),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('voice-cancel'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const ValueKey('voice-stop'),
                  style: FilledButton.styleFrom(backgroundColor: gold),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ],
        );

      case _VoiceStage.finished:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ChatMessage.clockDuration(_seconds),
              key: const ValueKey('voice-timer'),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _seconds == 0 ? 'Nothing was recorded.' : 'Recorded',
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurface.withAlpha(160),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('voice-cancel'),
                  onPressed: _cancel,
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('voice-again'),
                  onPressed: _begin,
                  child: const Text('Record again'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('voice-send'),
                  style: FilledButton.styleFrom(backgroundColor: gold),
                  // Nothing to send if the recorder came back empty.
                  onPressed: _seconds > 0 && _path != null ? _send : null,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        );
    }
  }
}

/// A video that stays a thumbnail until it is tapped, so a thread full of
/// them does not spin up a player per bubble.
class _VideoBubble extends StatefulWidget {
  const _VideoBubble({required this.path, this.name});

  final String path;
  final String? name;

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool _playing = false;

  /// The opening frame, once one has been cut. Stays null while it decodes,
  /// and for good if the file will not give one up — the tile then keeps the
  /// placeholder it had before frames existed.
  Uint8List? _frame;

  @override
  void initState() {
    super.initState();
    _loadFrame();
  }

  Future<void> _loadFrame() async {
    final frame = await videoThumb(widget.path);
    if (!mounted) return;
    setState(() => _frame = frame);
  }

  @override
  Widget build(BuildContext context) {
    if (_playing) {
      // The player sizes itself to the clip, so a vertical video gets a
      // vertical window instead of a strip of picture in a landscape box.
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AppVideoPlayer(
          url: widget.path,
          autoPlay: true,
          hugVideo: true,
        ),
      );
    }

    return VideoTile(
      path: widget.path,
      name: widget.name,
      frame: _frame,
      onPlay: () => setState(() => _playing = true),
    );
  }
}

/// The 220×150 tile a video sits in: its first frame once one could be
/// decoded, and a black card with the file's name when it could not.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.path,
    required this.onPlay,
    this.name,
    this.frame,
  });

  final String path;
  final String? name;

  /// JPEG bytes of the opening frame, or null when it is still being cut or
  /// the platform produced none.
  final Uint8List? frame;

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final decoded = frame;
    return InkWell(
      key: const ValueKey('bubble-video'),
      borderRadius: BorderRadius.circular(10),
      onTap: onPlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 220,
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The frame is the picture, and it is left alone: no name
              // laid over it, no control parked in the middle of it. With
              // nothing decoded — still cutting, an undecodable file, a
              // browser that cannot cut one at all — the tile falls back to
              // a black card that still says which file it is.
              if (decoded == null)
                Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Text(
                    name ?? 'Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5),
                  ),
                )
              else
                // The decoder hands back the frame at whatever size the
                // video is, so the decode is capped here: a 4K video
                // would otherwise cost ~33MB of bitmap per bubble, and
                // 440 pixels is all the 220-point tile can show.
                Image.memory(decoded,
                    width: 220,
                    height: 150,
                    fit: BoxFit.cover,
                    cacheWidth: 440),
              // The control keeps to the corner so the frame underneath it
              // stays readable, with a shadow to hold it over a bright one.
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.play_arrow,
                  size: 40,
                  color: Colors.white70,
                  shadows: [
                    Shadow(blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A voice note: play or pause, a waveform, and how long it runs.
/// The attachment waiting in the composer, with a way to change your mind
/// before it goes: drop it, or — for a voice note — listen to it first.
class StagedAttachmentBar extends StatelessWidget {
  const StagedAttachmentBar({
    super.key,
    required this.kind,
    required this.path,
    required this.cs,
    required this.gold,
    required this.onRemove,
    this.name,
    this.seconds,
  });

  final ChatAttachment kind;
  final String path;
  final String? name;
  final int? seconds;
  final ColorScheme cs;
  final Color gold;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: kind == ChatAttachment.image
                  ? fileImage(
                      path,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.image_outlined, color: gold),
                    )
                  : kind == ChatAttachment.audio
                      // Play rather than a microphone: this one is already
                      // recorded, and it may not be what you wanted to send.
                      ? AudioPreviewButton(
                          key: const ValueKey('chat-attach-preview'),
                          path: path,
                          color: gold,
                          size: 40,
                        )
                      : Icon(_stagedIcon(kind), color: gold, size: 26),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _stagedTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  kind == ChatAttachment.audio
                      ? 'Tap to listen before sending'
                      : 'Ready to send',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('chat-attach-remove'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove attachment',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  static IconData _stagedIcon(ChatAttachment kind) {
    switch (kind) {
      case ChatAttachment.image:
        return Icons.image_outlined;
      case ChatAttachment.video:
        return Icons.videocam_outlined;
      case ChatAttachment.audio:
        return Icons.mic_none_outlined;
      case ChatAttachment.file:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _stagedTitle() {
    switch (kind) {
      case ChatAttachment.audio:
        return 'Voice note · ${ChatMessage.clockDuration(seconds)}';
      case ChatAttachment.file:
      case ChatAttachment.image:
      case ChatAttachment.video:
        return name ?? kind.label;
    }
  }
}

/// Plays a local audio file: the sent bubble uses it, and so does the
/// composer, so a voice note can be listened to before it is sent — the words
/// may not be the ones you meant, or the room may have been too loud.
class AudioPreviewButton extends StatefulWidget {
  const AudioPreviewButton({
    super.key,
    required this.path,
    required this.color,
    this.size = 34,
    this.onPlayingChanged,
  });

  final String path;
  final Color color;
  final double size;

  /// Lets whatever holds this button mirror the state, as the wave does.
  final ValueChanged<bool>? onPlayingChanged;

  @override
  State<AudioPreviewButton> createState() => AudioPreviewButtonState();
}

class AudioPreviewButtonState extends State<AudioPreviewButton> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    // Stops anything still running: a preview that outlives its row would be
    // sound with nowhere to look.
    _player?.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    if (_playing) {
      await _player?.stop();
      if (!mounted) return;
      setState(() => _playing = false);
      widget.onPlayingChanged?.call(false);
      return;
    }

    final player = AudioPlayer();
    _player?.dispose();
    _player = player;
    player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playing = false);
      widget.onPlayingChanged?.call(false);
    });

    try {
      await player.play(DeviceFileSource(widget.path));
      if (!mounted) return;
      setState(() => _playing = true);
      widget.onPlayingChanged?.call(true);
    } catch (_) {
      // A file that went missing plays nothing rather than throwing.
      if (!mounted) return;
      setState(() => _playing = false);
      widget.onPlayingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: toggle,
      child: Icon(
        _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  const _AudioBubble({
    required this.path,
    required this.seconds,
    required this.ink,
  });

  final String path;
  final int? seconds;
  final Color ink;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  /// The button owns the player; the bubble only borrows it, so tapping the
  /// wave does the same thing as tapping the icon.
  final GlobalKey<AudioPreviewButtonState> _play =
      GlobalKey<AudioPreviewButtonState>();
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink;
    return InkWell(
      key: const ValueKey('bubble-audio'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _play.currentState?.toggle(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AudioPreviewButton(
            key: _play,
            path: widget.path,
            color: ink,
            onPlayingChanged: (playing) {
              if (mounted) setState(() => _playing = playing);
            },
          ),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: _wave(ink)),
          const SizedBox(width: 8),
          Text(
            ChatMessage.clockDuration(widget.seconds),
            style: TextStyle(fontSize: 12, color: ink.withAlpha(190)),
          ),
        ],
      ),
    );
  }

  /// A fixed shape rather than a measured one: the wave is decoration, and
  /// the length is what the clock above it already says.
  Widget _wave(Color ink) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 24; i++)
          Container(
            width: 2,
            height: 4 + ((i * 5 + 3) % 13).toDouble(),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: ink.withAlpha(_playing ? 230 : 140),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// One line of the thread: either a message or the day it belongs to.
class _Row {
  const _Row.message(this.message) : day = null;
  const _Row.day(this.day) : message = null;

  final ChatMessage? message;
  final DateTime? day;
}
