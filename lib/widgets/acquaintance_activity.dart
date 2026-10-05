import 'dart:async';

import 'package:flutter/material.dart';

import '../services/activity_service.dart';
import '../services/audio_player_service.dart';
import '../services/privacy_service.dart';

/// What music activity wears: the headphones avatar and its act.
const _listeningAccent = Color(0xFFB15CFF);

/// The "right now" strip at the top of the Acquaintances tab: what you're
/// playing or reading (gated by the Privacy setting) followed by what your
/// acquaintances are up to.
///
/// Reads the music service live rather than storing a copy of now-playing,
/// so the row flips the instant a song starts or stops.
class AcquaintanceActivity extends StatefulWidget {
  const AcquaintanceActivity({super.key});

  @override
  State<AcquaintanceActivity> createState() => _AcquaintanceActivityState();
}

class _AcquaintanceActivityState extends State<AcquaintanceActivity> {
  StreamSubscription<void>? _audioSub;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _signature = _signatureOf();
    ActivityService.instance.reading.addListener(_onChanged);
    PrivacyService.instance.audience.addListener(_onChanged);
    // Only listen once the player actually exists — the strip still renders
    // (with the reader's activity) where audio was never started.
    final audio = AudioPlayerService.maybeInstance;
    if (audio != null) {
      _audioSub = audio.stateStream.listen((_) => _onChanged());
    }
  }

  @override
  void dispose() {
    ActivityService.instance.reading.removeListener(_onChanged);
    PrivacyService.instance.audience.removeListener(_onChanged);
    _audioSub?.cancel();
    super.dispose();
  }

  /// Cheap stand-in for "would the rows look different?" so the audio
  /// position ticker never rebuilds this list for no reason.
  String _signatureOf() =>
      '${PrivacyService.instance.audience.value.name}|'
      '${ActivityService.instance.own()?.line}';

  void _onChanged() {
    if (!mounted) return;
    final next = _signatureOf();
    if (next != _signature) setState(() => _signature = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final audience = PrivacyService.instance.audience.value;
    final shared = audience != ShareAudience.private;
    final own = ActivityService.instance.own();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('RIGHT NOW'),
        ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: gold.withAlpha(30),
            child: Text(
              'P',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'You',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _chip(context, audience),
            ],
          ),
          subtitle: own == null || !shared
              ? Text(
                  'Nothing shared right now',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(150),
                  ),
                )
              : _activityLine(
                  own,
                  actColor: gold,
                  subjectColor: cs.onSurface.withAlpha(180),
                ),
          trailing: Icon(
            shared ? Icons.radio_button_checked : Icons.visibility_off_outlined,
            size: 15,
            color: shared ? gold : cs.onSurface.withAlpha(130),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        for (final entry in ActivityService.acquaintances)
          _activityRow(context, entry, gold, cs),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _activityRow(
    BuildContext context,
    ActivityEntry entry,
    Color gold,
    ColorScheme cs,
  ) {
    final listening = entry.kind == ActivityKind.listening;
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: listening
            ? _listeningAccent.withAlpha(30)
            : gold.withAlpha(30),
        child: Icon(
          listening ? Icons.headphones_outlined : Icons.menu_book_outlined,
          size: 18,
          color: listening ? _listeningAccent : gold,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            entry.handle,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(150)),
          ),
        ],
      ),
      subtitle: _activityLine(
        entry,
        actColor: listening ? _listeningAccent : gold,
        subjectColor: cs.onSurface.withAlpha(180),
      ),
      trailing: Text(
        entry.when,
        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(130)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  /// The row's activity as two colours: the act (`Reading`, `Listening to`)
  /// in [actColor] and what it is about in [subjectColor], so the verb never
  /// blends into the title beside it.
  Widget _activityLine(
    ActivityEntry entry, {
    required Color actColor,
    required Color subjectColor,
  }) {
    return Text.rich(
      TextSpan(
        text: entry.act,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: actColor,
        ),
        children: [
          TextSpan(
            text: ' ${entry.subject}',
            style: TextStyle(fontSize: 12, color: subjectColor),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ShareAudience audience) {
    final gold = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: gold.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gold.withAlpha(110)),
      ),
      child: Text(
        audience.label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
          color: gold,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: cs.onSurface.withAlpha(150),
        ),
      ),
    );
  }
}
