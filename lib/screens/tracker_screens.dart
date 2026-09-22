import 'package:flutter/material.dart';
import 'tracker_screen.dart';

/// Individual tracker screens — each wraps [TrackerScreen] with category config
/// and maps to the corresponding backend API category.

class MoviesTrackerScreen extends StatelessWidget {
  const MoviesTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Movies',
      icon: Icons.movie_outlined,
      accentColor: Color(0xFFC2B067),
      apiCategory: 'movies',
    );
  }
}

class SeriesTrackerScreen extends StatelessWidget {
  const SeriesTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Series',
      icon: Icons.tv_outlined,
      accentColor: Color(0xFF6C8CFF),
      apiCategory: 'tv',
    );
  }
}

class AnimeTrackerScreen extends StatelessWidget {
  const AnimeTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Anime',
      icon: Icons.animation_outlined,
      accentColor: Color(0xFFFF6B9D),
      apiCategory: 'anime',
    );
  }
}

class GamesTrackerScreen extends StatelessWidget {
  const GamesTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Games',
      icon: Icons.sports_esports_outlined,
      accentColor: Color(0xFF107C10),
      apiCategory: 'games',
    );
  }
}

class BooksTrackerScreen extends StatelessWidget {
  const BooksTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Books',
      icon: Icons.book_outlined,
      accentColor: Color(0xFFB8860B),
      apiCategory: 'books',
    );
  }
}

class WorkoutTrackerScreen extends StatelessWidget {
  const WorkoutTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TrackerScreen(
      title: 'Workout',
      icon: Icons.fitness_center_outlined,
      accentColor: Color(0xFFFF6347),
      // No API — workout is local-only
    );
  }
}
