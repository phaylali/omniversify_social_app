import 'dart:io';
import '../models/song_item.dart';
import 'audio_metadata_extractor.dart';

/// Quick scan only — filenames, no metadata. Returns instantly for UI.
Future<List<SongItem>> scanAudioFilesQuick() async {
  return _collectFiles();
}

/// Full scan with pure-Dart metadata (fast, batched, no player).
Future<List<SongItem>> scanAudioFiles() async {
  final songs = await _collectFiles();
  if (songs.isEmpty) return songs;
  // Enrich in background-friendly batches (extractor already batches 8).
  final enriched = await AudioMetadataExtractor.extractAll(songs);
  enriched.sort((a, b) => a.title.compareTo(b.title));
  return enriched;
}

Future<List<SongItem>> _collectFiles() async {
  final audioExts = {'.mp3', '.flac', '.wav', '.ogg', '.m4a', '.aac', '.wma', '.opus'};
  final songs = <SongItem>[];
  int id = 0;

  final home = Platform.environment['HOME'] ?? '';
  final dirs = <String>[
    '$home/Music',
    '$home/Downloads',
    '$home/Videos',
    '$home/.local/share/Music',
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes',
  ];

  for (final dirPath in dirs) {
    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final p = entity.path;
        // Skip caches, hidden noise, and temp files for speed.
        if (p.contains('/.cache/') ||
            p.contains('/.thumbnails/') ||
            p.contains('/.Trash')) {
          continue;
        }
        final path = p.toLowerCase();
        if (!audioExts.any((e) => path.endsWith(e))) continue;
        final name = p.split(Platform.pathSeparator).last;
        // Skip hidden dotfiles.
        if (name.startsWith('.')) continue;
        final dotIdx = name.lastIndexOf('.');
        final title = dotIdx > 0 ? name.substring(0, dotIdx) : name;
        final folder = p.substring(0, p.lastIndexOf(Platform.pathSeparator));
        songs.add(SongItem(
          id: id++,
          title: title,
          path: p,
          folder: folder,
        ));
        // Safety cap so Downloads/Videos with thousands of files stay fast.
        if (songs.length >= 2000) break;
      }
    } catch (_) {}
  }

  songs.sort((a, b) => a.title.compareTo(b.title));
  return songs;
}
