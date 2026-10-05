import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/messages_service.dart';
import '../widgets/action_sheet.dart';

/// One direct message conversation: the thread, the bar to type in, and the
/// things every chat screen offers — call buttons, a conversation menu,
/// long-press on a message.
///
/// The thread itself lives in [MessagesService], so a link shared from
/// another app is waiting here, and anything sent here shows up in the
/// drawer's last line.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.handle, this.name});

  /// Who the conversation is with.
  final String handle;

  /// How they are shown — falls back to the first name we know them by.
  final String? name;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  bool _canSend = false;

  String get _name => widget.name ?? MessagesService.nameFor(widget.handle);

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final canSend = _input.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
    // The conversation is open, so whatever was waiting in it is read now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MessagesService.instance.markRead(widget.handle);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await MessagesService.instance.send(widget.handle, text);
  }

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

  /// Newest first: a day chip above each group, ready for a reversed list.
  static List<_Row> _rows(List<ChatMessage> messages) {
    final rows = <_Row>[];
    DateTime? seen;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final day =
          DateTime(message.at.year, message.at.month, message.at.day);
      if (day != seen) {
        rows.add(_Row.day(day));
        seen = day;
      }
      rows.add(_Row.message(message));
    }
    return rows;
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
    final ink = mine ? cs.onPrimary : cs.onSurface;
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
          color: mine ? gold : cs.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
      ),
    );
  }

  // ── Long-press on a message ──────────────────────────────────────────

  void _showMessageMenu(ChatMessage message) {
    showActionSheet(
      context,
      title: 'Message',
      subtitle: message.clock,
      items: [
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

/// One line of the thread: either a message or the day it belongs to.
class _Row {
  const _Row.message(this.message) : day = null;
  const _Row.day(this.day) : message = null;

  final ChatMessage? message;
  final DateTime? day;
}
