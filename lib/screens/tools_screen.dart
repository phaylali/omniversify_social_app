import 'package:flutter/material.dart';
import 'calculator_screen.dart';
import 'qr_scanner_screen.dart';
import 'timer_screen.dart';
import 'flashlight_screen.dart';
import 'weather_screen.dart';
import 'translation_screen.dart';
import 'music_player_screen.dart';
import 'tracker_screens.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    final trackers = [
      ('Series', Icons.tv_outlined, const Color(0xFF6C8CFF), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeriesTrackerScreen()));
      }),
      ('Anime', Icons.animation_outlined, const Color(0xFFFF6B9D), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnimeTrackerScreen()));
      }),
      ('Movies', Icons.movie_outlined, const Color(0xFFC2B067), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoviesTrackerScreen()));
      }),
      ('Games', Icons.sports_esports_outlined, const Color(0xFF107C10), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GamesTrackerScreen()));
      }),
      ('Books', Icons.book_outlined, const Color(0xFFB8860B), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BooksTrackerScreen()));
      }),
      ('Workout', Icons.fitness_center_outlined, const Color(0xFFFF6347), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutTrackerScreen()));
      }),
    ];

    final tools = [
      ('Calculator', Icons.calculate_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalculatorScreen()));
      }),
      ('QR Scanner', Icons.qr_code_scanner_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
      }),
      ('Timer', Icons.timer_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimerScreen()));
      }),
      ('Flashlight', Icons.flashlight_on_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FlashlightScreen()));
      }),
      ('Weather', Icons.wb_sunny_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeatherScreen()));
      }),
      ('Music', Icons.music_note_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicPlayerScreen()));
      }),
      ('Translate', Icons.translate_outlined, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TranslationScreen()));
      }),
      ('Notes', Icons.note_outlined, () {}),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text('TRACKERS', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 12)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final (label, icon, color, onTap) = trackers[index];
                return GestureDetector(
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withAlpha(40), width: 0.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: trackers.length,
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text('TOOLS', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 12)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final (label, icon, onTap) = tools[index];
                return GestureDetector(
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: gold.withAlpha(20), width: 0.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: gold, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: tools.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}
