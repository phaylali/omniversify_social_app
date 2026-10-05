import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Someone you can send a direct message to.
class DmPerson {
  const DmPerson({required this.name, required this.handle});

  final String name;
  final String handle;

  String get initial => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

/// One message in a thread: what was said, which way it went, and when.
class ChatMessage {
  ChatMessage({required this.text, required this.fromMe, required this.at});

  final String text;
  final bool fromMe;
  final DateTime at;

  /// Age of the message: `now` / `2m` / `1h` / `2d`.
  String get when {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'fromMe': fromMe,
        'at': at.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String? ?? '',
        fromMe: json['fromMe'] as bool? ?? false,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// The direct messages behind the drawer: who you can talk to, what has been
/// said, and who is waiting for an answer.
///
/// Everything lives in [SharedPreferences] and mirrors into [ValueNotifier]s,
/// so the drawer, the chat screen and the share sheet all read one store — a
/// link shared from another app lands in the same thread you open by tapping
/// the person.
class MessagesService {
  MessagesService._();

  static final MessagesService instance = MessagesService._();

  static const String _kStore = 'dm_threads_v1';

  /// Everyone who can be messaged — the DM drawer's crowd, plus Amina.
  static const List<DmPerson> people = [
    DmPerson(name: 'Ahmed', handle: '@ahmed_m'),
    DmPerson(name: 'Sara', handle: '@sara_dev'),
    DmPerson(name: 'Omar', handle: '@omar_92'),
    DmPerson(name: 'Fatima', handle: '@fatima_art'),
    DmPerson(name: 'Youssef', handle: '@youssef_ma'),
    DmPerson(name: 'Karim', handle: '@karim_w'),
    DmPerson(name: 'Amina', handle: '@amina_stream'),
  ];

  /// Opening line of every conversation, until the backend carries them.
  static Map<String, List<ChatMessage>> _seed() {
    DateTime ago(int minutes) =>
        DateTime.now().subtract(Duration(minutes: minutes));
    return {
      '@ahmed_m': [
        ChatMessage(
            text: 'Sure, let\'s watch it together!', fromMe: false, at: ago(2)),
      ],
      '@sara_dev': [
        ChatMessage(
            text: 'I just finished the book!', fromMe: false, at: ago(15)),
      ],
      '@omar_92': [
        ChatMessage(text: 'Check this game out', fromMe: false, at: ago(60)),
      ],
      '@fatima_art': [
        ChatMessage(
            text: 'The workout was intense 💪', fromMe: false, at: ago(180)),
      ],
      '@youssef_ma': [
        ChatMessage(text: 'See you tomorrow!', fromMe: false, at: ago(1440)),
      ],
      '@karim_w': [
        ChatMessage(
            text: 'Thanks for the recommendation', fromMe: false, at: ago(2880)),
      ],
    };
  }

  /// Thread per handle, newest last. Rebuilds the moment anything changes.
  final ValueNotifier<Map<String, List<ChatMessage>>> threads =
      ValueNotifier(const {});

  /// Handles with a message you have not opened yet.
  final ValueNotifier<Set<String>> unread = ValueNotifier(const {});

  bool _loaded = false;

  /// Reads the stored threads once. Safe to call repeatedly.
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStore);
    if (raw == null) {
      threads.value = _seed();
      unread.value = const {'@sara_dev', '@youssef_ma'};
      await _save();
    } else {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        threads.value = {
          for (final entry in (data['threads'] as Map<String, dynamic>? ?? const {})
              .entries)
            entry.key: [
              for (final item in entry.value as List<dynamic>)
                ChatMessage.fromJson(item as Map<String, dynamic>),
            ],
        };
        unread.value =
            (data['unread'] as List<dynamic>? ?? const []).cast<String>().toSet();
      } catch (_) {
        // A store we cannot read is a store we start over from.
        threads.value = _seed();
        unread.value = const {};
      }
    }
    _loaded = true;
  }

  DmPerson? personFor(String handle) {
    for (final person in people) {
      if (person.handle == handle) return person;
    }
    return null;
  }

  /// First name, or the handle without its `@` when nobody by that name is
  /// in [people] (someone you followed, say).
  static String nameFor(String handle) =>
      instance.personFor(handle)?.name ?? handle.replaceFirst('@', '');

  List<ChatMessage> thread(String handle) => threads.value[handle] ?? const [];

  ChatMessage? lastOf(String handle) {
    final messages = thread(handle);
    return messages.isEmpty ? null : messages.last;
  }

  /// Sends one message from you into [handle]'s thread.
  Future<void> send(String handle, String text) async {
    if (text.trim().isEmpty) return;
    await init();
    final next = {...threads.value};
    next[handle] = [
      ...thread(handle),
      ChatMessage(text: text.trim(), fromMe: true, at: DateTime.now()),
    ];
    threads.value = next;
    await _save();
  }

  /// The share sheet's job: the same link or caption into every conversation
  /// that was picked.
  Future<void> shareTo(Iterable<String> handles, String text) async {
    for (final handle in handles) {
      await send(handle, text);
    }
  }

  /// Opening a thread takes it off the unread list.
  Future<void> markRead(String handle) async {
    if (!unread.value.contains(handle)) return;
    final next = {...unread.value}..remove(handle);
    unread.value = next;
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStore,
      jsonEncode({
        'threads': {
          for (final entry in threads.value.entries)
            entry.key: [for (final message in entry.value) message.toJson()],
        },
        'unread': unread.value.toList(),
      }),
    );
  }

  /// Empties everything and lets [init] read again — tests start clean.
  @visibleForTesting
  void reset() {
    threads.value = const {};
    unread.value = const {};
    _loaded = false;
  }
}
