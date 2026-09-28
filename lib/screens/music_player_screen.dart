import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song_item.dart';
import '../services/audio_actions.dart';
import '../services/audio_scanner.dart';
import '../services/audio_metadata_extractor_stub.dart'
    if (dart.library.io) '../services/audio_metadata_extractor.dart';
import '../services/audio_player_service.dart';
import '../services/artwork_loader_stub.dart'
    if (dart.library.io) '../services/artwork_loader.dart';
import '../services/music_library_service.dart';
import '../services/song_metadata_overrides.dart';
import '../services/taglib_audio_service_stub.dart'
    if (dart.library.io) '../services/taglib_audio_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/share_sheet.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with WidgetsBindingObserver {
  final AudioPlayerService _service = AudioPlayerService.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  List<SongItem> _allSongs = [];
  List<SongItem> _filtered = [];
  Set<String> _allowedFolders = {};
  bool _loading = true;
  bool _hasPermission = false;
  // Indexing progress: cached files skip parsing, only new ones cost time.
  int _scanDone = 0;
  int _scanTotal = 0;
  bool _enriching = false;

  String _sortBy = 'title';
  bool _sortAsc = true;

  // Pending action waiting for the user to return from a settings screen.
  // Permission prompts are lazy: set only when an action needs them.
  String? _pendingAction; // 'ringtone' | 'delete'
  SongItem? _pendingDeleteSong;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.init().then((_) => _service.connectAudioService());
    _requestPermission();

    _service.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Retries a permission-gated action once the user returns from the
  /// matching system settings screen. Silently gives up if access was
  /// not actually granted (user backed out).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final action = _pendingAction;
    if (action == null) return;
    _pendingAction = null;
    if (action == 'ringtone') {
      AudioActions.canWriteSettings().then((ok) {
        if (ok && mounted) _setRingtone();
      });
    } else if (action == 'delete') {
      final song = _pendingDeleteSong;
      _pendingDeleteSong = null;
      AudioActions.canManageAllFiles().then((ok) {
        if (ok && song != null && mounted) _deleteSong(song);
      });
    }
  }

  Future<void> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      // Media notification controls need POST_NOTIFICATIONS on Android 13+.
      try {
        final notif = await Permission.notification.status;
        if (!notif.isGranted && !notif.isPermanentlyDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}

      var status = await Permission.audio.status;
      if (!status.isGranted) status = await Permission.audio.request();
      if (!status.isGranted) {
        status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        if (mounted) setState(() => _hasPermission = false);
        return;
      }
    }
    if (mounted) setState(() => _hasPermission = true);
    await _loadSongs();
  }

  Future<void> _loadSongs({bool force = false}) async {
    final memory = MusicLibraryService.instance;
    // Return visit: show remembered library instantly, no spinner.
    if (!force && memory.hasData) {
      final cached = memory.songs;
      if (!mounted) return;
      setState(() {
        _allSongs = cached;
        if (_allowedFolders.isEmpty) {
          _allowedFolders = cached.map((s) => s.folder).toSet();
        }
        _filtered = List.from(cached);
        _loading = false;
        _enriching = false;
      });
      await _service.setPlaylist(_filtered);
      // Silently pick up new files in the background.
      _refreshInBackground();
      return;
    }
    try {
      // Phase 1: instant file list, no metadata — UI shows at once.
      final quick = await SongMetadataOverrides.apply(await scanAudioFilesQuick());
      if (!mounted) return;
      setState(() {
        _allSongs = quick;
        _allowedFolders = quick.map((s) => s.folder).toSet();
        _filtered = List.from(quick);
        _loading = false;
        _enriching = quick.isNotEmpty;
        _scanDone = 0;
        _scanTotal = quick.length;
      });
      await _service.setPlaylist(_filtered);

      // Phase 2: cached index + live counter. Only new/changed files parse.
      final enriched = await AudioMetadataExtractor.extractAll(
        quick,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _scanDone = done;
            _scanTotal = total;
          });
        },
      );
      if (!mounted) return;
      // Preserve search query.
      final q = _searchCtrl.text.toLowerCase();
      final overridable = await SongMetadataOverrides.apply(enriched);
      final folders = overridable.map((s) => s.folder).toSet();
      List<SongItem> filtered = overridable
          .where((s) => _allowedFolders.contains(s.folder) || _allowedFolders.isEmpty)
          .where((s) =>
              q.isEmpty ||
              s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q) ||
              (s.album ?? '').toLowerCase().contains(q))
          .toList();
      setState(() {
        _allSongs = overridable;
        _allowedFolders = folders.isEmpty ? _allowedFolders : folders;
        _filtered = filtered;
        _enriching = false;
      });
      memory.store(overridable);
      await _service.setPlaylist(_filtered);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _enriching = false;
        });
      }
    }
  }

  /// Silent background refresh for return visits.
  /// Skips work entirely when the file set is unchanged.
  Future<void> _refreshInBackground() async {
    try {
      final quick = await scanAudioFilesQuick();
      if (!mounted) return;
      final known = _allSongs.map((s) => s.path).toSet();
      final found = quick.map((s) => s.path).toSet();
      if (known.length == found.length && known.containsAll(found)) return;
      if (!mounted) return;
      setState(() {
        _enriching = true;
        _scanDone = 0;
        _scanTotal = quick.length;
      });
      final enriched = await AudioMetadataExtractor.extractAll(
        quick,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _scanDone = done;
            _scanTotal = total;
          });
        },
      );
      if (!mounted) return;
      final withOverrides = await SongMetadataOverrides.apply(enriched);
      setState(() {
        _allSongs = withOverrides;
        _allowedFolders = withOverrides.map((s) => s.folder).toSet();
        _filtered = List.from(withOverrides);
        _enriching = false;
      });
      MusicLibraryService.instance.store(withOverrides);
      await _service.setPlaylist(_filtered);
    } catch (_) {
      if (mounted) setState(() => _enriching = false);
    }
  }

  void _filterSongs(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _allSongs
          .where((s) => _allowedFolders.contains(s.folder))
          .where((s) =>
              s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q) ||
              (s.album ?? '').toLowerCase().contains(q))
          .toList();
      _sortSongs();
    });
    // Rebuild playlist in service
    _service.setPlaylist(_filtered);
  }

  void _sortSongs() {
    setState(() {
      _filtered.sort((a, b) {
        int cmp;
        switch (_sortBy) {
          case 'artist':
            cmp = (a.artist ?? '').compareTo(b.artist ?? '');
            break;
          case 'album':
            cmp = (a.album ?? '').compareTo(b.album ?? '');
            break;
          case 'duration':
            cmp = (a.duration ?? 0).compareTo(b.duration ?? 0);
            break;
          default:
            cmp = a.title.compareTo(b.title);
        }
        return _sortAsc ? cmp : -cmp;
      });
    });
    _service.setPlaylist(_filtered);
  }

  Future<void> _play(int index) async {
    await _service.setPlaylist(_filtered);
    await _service.play(index);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    // Do NOT dispose the service — it persists across navigation
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentSong = _service.currentSong;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 22),
            onSelected: (v) {
              if (v.startsWith('sort_')) {
                final field = v.replaceFirst('sort_', '');
                setState(() {
                  _sortBy = field;
                  _sortAsc = _sortBy == field ? !_sortAsc : true;
                });
                _sortSongs();
              } else if (v == 'folders') {
                _showFolderPicker(cs);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'sort_title', child: Text('Sort by Title')),
              const PopupMenuItem(value: 'sort_artist', child: Text('Sort by Artist')),
              const PopupMenuItem(value: 'sort_album', child: Text('Sort by Album')),
              const PopupMenuItem(value: 'sort_duration', child: Text('Sort by Duration')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'folders', child: Text('Manage Folders')),
            ],
          ),
        ],
      ),
      body: !_hasPermission
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off, size: 64, color: cs.onSurface.withAlpha(80)),
                  const SizedBox(height: 16),
                  Text('Audio permission required',
                      style: TextStyle(color: cs.onSurface.withAlpha(150))),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => openAppSettings(),
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _filterSongs,
                        decoration: InputDecoration(
                          hintText: 'Search songs...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _filterSongs('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withAlpha(80),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Row(children: [
                        Text('${_filtered.length} songs',
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(100))),
                        const Spacer(),
                        if (_enriching && _scanTotal > 0)
                          Text('Indexing $_scanDone / $_scanTotal',
                              style: TextStyle(
                                  fontSize: 11, color: cs.primary.withAlpha(200))),
                        if (_enriching && _scanTotal > 0) const SizedBox(width: 8),
                        Text('${_allowedFolders.length} folders',
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(100))),
                      ]),
                    ),
                    if (_enriching && _scanTotal > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: LinearProgressIndicator(
                          value: _scanTotal == 0
                              ? null
                              : (_scanDone / _scanTotal).clamp(0.0, 1.0),
                          minHeight: 2,
                        ),
                      ),
                    Expanded(
                      child: _filtered.isEmpty && !_enriching
                          ? Center(
                              child: Text('No songs found',
                                  style: TextStyle(color: cs.onSurface.withAlpha(100))))
                          : RefreshIndicator(
                              onRefresh: () => _loadSongs(force: true),
                              child: ListView.builder(
                                padding: EdgeInsets.only(
                                    bottom: currentSong != null
                                        ? 140 +
                                            MediaQuery.of(context)
                                                .viewPadding
                                                .bottom +
                                            12
                                        : 12),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _songTile(_filtered[i], i, cs),
                              ),
                            ),
                    ),
                    if (currentSong != null) _playerBar(cs),
                  ],
                ),
    );
  }

  Widget _songTile(SongItem song, int index, ColorScheme cs) {
    final isPlaying = _service.currentIndex == index;
    return ListTile(
      leading: ArtworkThumb(song: song, size: 44, isPlaying: isPlaying),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isPlaying ? cs.primary : cs.onSurface,
        ),
      ),
      subtitle: Text(
        [song.artist, song.album].whereType<String>().isNotEmpty
            ? [song.artist, song.album].whereType<String>().join(' • ')
            : song.folder.split('/').last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(120)),
      ),
      trailing: Text(
        _formatMs(song.duration),
        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(100)),
      ),
      onTap: () => _play(index),
    );
  }

  Widget _playerBar(ColorScheme cs) {
    final song = _service.currentSong!;
    final duration = _service.duration;
    final position = _service.position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    // Keep controls clear of gesture nav / curved-screen safe areas.
    final safeBottom = MediaQuery.of(context).viewPadding.bottom + 12;

    return Container(
      padding: EdgeInsets.only(bottom: safeBottom),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(40), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (v) {
              final pos = Duration(milliseconds: (v * duration.inMilliseconds).round());
              _service.seek(pos);
            },
            activeColor: cs.primary,
            inactiveColor: cs.primary.withAlpha(40),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              // Artwork thumbnail in player bar
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ArtworkThumb(
                  song: song,
                  size: 36,
                  radius: BorderRadius.circular(6),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                    Text(song.artist ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120))),
                  ],
                ),
              ),
              Text(_formatMs(position.inMilliseconds),
                  style: TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(100))),
              Text(' / ',
                  style: TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(60))),
              Text(_formatMs(duration.inMilliseconds),
                  style: TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(100))),
            ]),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shuffle toggle
              IconButton(
                tooltip: _service.shuffleOn ? 'Shuffle on' : 'Shuffle off',
                icon: Icon(Icons.shuffle,
                    color: _service.shuffleOn
                        ? cs.primary
                        : cs.onSurface.withAlpha(180),
                    size: 20),
                onPressed: () {
                  _service.toggleShuffle();
                  setState(() {});
                },
              ),
              // Repeat toggle (cycles: off → all → one)
              IconButton(
                tooltip: _service.repeatMode == MusicRepeatMode.off
                    ? 'Repeat off'
                    : _service.repeatMode == MusicRepeatMode.all
                        ? 'Repeat all'
                        : 'Repeat one',
                icon: Icon(
                  _service.repeatMode == MusicRepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  color: _service.repeatMode == MusicRepeatMode.off
                      ? cs.onSurface.withAlpha(180)
                      : cs.primary,
                  size: 20,
                ),
                onPressed: () {
                  _service.cycleRepeat();
                  setState(() {});
                },
              ),
              IconButton(
                  icon: Icon(Icons.skip_previous, color: cs.onSurface.withAlpha(180)),
                  onPressed: _service.previous),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
                child: IconButton(
                  icon: Icon(_service.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: cs.onPrimary, size: 28),
                  onPressed: _service.togglePlay,
                ),
              ),
              IconButton(
                  icon: Icon(Icons.skip_next, color: cs.onSurface.withAlpha(180)),
                  onPressed: _service.next),
              IconButton(
                  tooltip: 'Volume',
                  icon: Icon(
                    _service.volume == 0
                        ? Icons.volume_off
                        : _service.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color: cs.onSurface.withAlpha(180),
                  ),
                  onPressed: () => _showVolumeSheet(cs)),
              // 3-dot menu: share / ringtone / edit / delete
              PopupMenuButton<String>(
                tooltip: 'More options',
                icon: Icon(Icons.more_vert,
                    color: cs.onSurface.withAlpha(180), size: 22),
                onSelected: (v) {
                  final song = _service.currentSong;
                  if (song == null) return;
                  switch (v) {
                    case 'share':
                      _shareCurrentSong();
                      break;
                    case 'ringtone':
                      _setRingtone();
                      break;
                    case 'edit':
                      _showEditMetadataDialog(song);
                      break;
                    case 'delete':
                      _confirmDelete(song);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Share file'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'ringtone',
                    child: Row(children: [
                      Icon(Icons.notifications_active_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Set as ringtone'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Edit metadata'),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 10),
                      Text('Delete file',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _shareCurrentSong() async {
    final song = _service.currentSong;
    if (song == null) return;
    await ShareSheet.show(
      context,
      shareText: '${song.title} ${song.artist ?? ''}'.trim(),
      files: [XFile(song.path)],
    );
  }

  // ── Ringtone ────────────────────────────────────────────────────────

  Future<void> _setRingtone() async {
    final song = _service.currentSong;
    if (song == null) return;
    if (!await AudioActions.canWriteSettings()) {
      _pendingAction = 'ringtone';
      await _askSettings(
        'Allow setting ringtones',
        'To set this song as your ringtone, Omniversify needs the '
            '"Modify system settings" permission. Nothing else in the app '
            'asks for it.',
        'Open settings',
        AudioActions.openWriteSettings,
      );
      return;
    }
    final res = await AudioActions.setRingtone(song.path);
    if (!mounted) return;
    if (res.ok) {
      _snack('Ringtone set');
    } else if (res.needsWriteSettings) {
      _pendingAction = 'ringtone';
      await _askSettings(
        'Allow setting ringtones',
        'To set this song as your ringtone, Omniversify needs the '
            '"Modify system settings" permission. Nothing else in the app '
            'asks for it.',
        'Open settings',
        AudioActions.openWriteSettings,
      );
    } else {
      _snack(res.message ?? 'Could not set ringtone');
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────

  Future<void> _confirmDelete(SongItem song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final error = Theme.of(ctx).colorScheme.error;
        return AlertDialog(
          title: const Text('Delete file?'),
          content: Text(
              '"${song.title}" will be permanently removed from this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _deleteSong(song);
  }

  Future<void> _deleteSong(SongItem song) async {
    final res = await AudioActions.deleteFile(song.path);
    if (!mounted) return;
    if (res.ok) {
      _pendingAction = null;
      _pendingDeleteSong = null;
      await _removeSongFromLibrary(song);
      _snack('File deleted');
    } else if (res.needsAllFiles) {
      // Only reason we ever ask for "All files access" — and only now.
      _pendingAction = 'delete';
      _pendingDeleteSong = song;
      await _askSettings(
        'All files access needed',
        'Deleting a music file needs "All files access". The app never '
            'asks for it otherwise.',
        'Open settings',
        AudioActions.openAllFilesAccessSettings,
      );
    } else {
      _snack(res.message ?? 'Could not delete file');
    }
  }

  Future<void> _removeSongFromLibrary(SongItem song) async {
    if (_service.currentSong?.path == song.path) _service.clearCurrent();
    setState(() {
      _allSongs = _allSongs.where((s) => s.path != song.path).toList();
      _filtered = _filtered.where((s) => s.path != song.path).toList();
    });
    await _service.setPlaylist(_filtered);
    await SongMetadataOverrides.remove(song.path);
    MusicLibraryService.instance.store(_allSongs);
    if (mounted) setState(() {});
  }

  // ── Edit metadata ───────────────────────────────────────────────────

  Future<void> _showEditMetadataDialog(SongItem song) async {
    final titleCtrl = TextEditingController(text: song.title);
    final artistCtrl = TextEditingController(text: song.artist ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit metadata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // TODO(omniversify): fetch artwork + extra details from the
            // omniversify music API using song.dbId once wired up.
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Song title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: artistCtrl,
              decoration: const InputDecoration(labelText: 'Singer (artist)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newTitle = titleCtrl.text.trim();
    final newArtist = artistCtrl.text.trim();
    titleCtrl.dispose();
    artistCtrl.dispose();
    if (confirmed != true || !mounted) return;
    if (newTitle.isEmpty && newArtist.isEmpty) return;

    final title = newTitle.isEmpty ? song.title : newTitle;
    final updated = SongItem(
      id: song.id,
      title: title,
      artist: newArtist.isEmpty ? null : newArtist,
      album: song.album,
      duration: song.duration,
      path: song.path,
      folder: song.folder,
      artworkBytes: song.artworkBytes,
      dbId: song.dbId,
    );

    await SongMetadataOverrides.set(song.path, title: title, artist: newArtist);
    setState(() {
      _allSongs =
          _allSongs.map((s) => s.path == song.path ? updated : s).toList();
      _filtered =
          _filtered.map((s) => s.path == song.path ? updated : s).toList();
    });
    _sortSongs(); // re-sorts + pushes the playlist into the service
    MusicLibraryService.instance.store(_allSongs);
    _service.refresh(); // notification / widget pick up the new title
    _snack('Metadata updated');
    _writeTags(updated);
  }

  /// Best-effort: bake the edit into the file's own tags so other players
  /// see it too. Only attempted when "All files access" already happens to
  /// be granted, so this can never trigger a permission prompt — the in-app
  /// edit above is saved either way.
  Future<void> _writeTags(SongItem song) async {
    try {
      if (!await AudioActions.canManageAllFiles()) return;
      await TaglibAudioService.writeTags(song.path,
          title: song.title, artist: song.artist);
    } catch (_) {}
  }

  // ── Shared helpers ──────────────────────────────────────────────────

  /// Explain-before-settings dialog for a lazy permission ask.
  /// Keeps the pending action alive when opening (retries on resume),
  /// clears it when the user cancels.
  Future<void> _askSettings(
    String title,
    String body,
    String buttonLabel,
    Future<void> Function() open,
  ) async {
    if (!mounted) return;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == true) {
      await open();
    } else {
      _pendingAction = null;
      _pendingDeleteSong = null;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _showVolumeSheet(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.volume_up, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Volume',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${(_service.volume * 100).round()}%',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withAlpha(120))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.volume_mute_outlined, size: 20),
                  onPressed: () {
                    _service.setVolume(0);
                    setSheetState(() {});
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _service.volume.clamp(0.0, 1.0),
                    onChanged: (v) {
                      _service.setVolume(v);
                      setSheetState(() {});
                    },
                    activeColor: cs.primary,
                    inactiveColor: cs.primary.withAlpha(40),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up_outlined, size: 20),
                  onPressed: () {
                    _service.setVolume(1);
                    setSheetState(() {});
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolderPicker(ColorScheme cs) {
    final allFolders = _allSongs.map((s) => s.folder).toSet();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, ctrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Text('Folders', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        if (_allowedFolders.length == allFolders.length) {
                          _allowedFolders = {};
                        } else {
                          _allowedFolders = Set.from(allFolders);
                        }
                      });
                      _filterSongs(_searchCtrl.text);
                      setState(() {});
                    },
                    child: Text(
                        _allowedFolders.length == allFolders.length
                            ? 'Deselect All'
                            : 'Select All'),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  controller: ctrl,
                  itemCount: allFolders.length,
                  itemBuilder: (_, i) {
                    final folder = allFolders.elementAt(i);
                    final count = _allSongs.where((s) => s.folder == folder).length;
                    final enabled = _allowedFolders.contains(folder);
                    final folderName = folder.split('/').last;
                    return CheckboxListTile(
                      value: enabled,
                      onChanged: (v) {
                        setModalState(() {
                          if (v == true) {
                            _allowedFolders.add(folder);
                          } else {
                            _allowedFolders.remove(folder);
                          }
                        });
                        _filterSongs(_searchCtrl.text);
                        setState(() {});
                      },
                      title: Text(folderName, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('$count songs',
                          style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(100))),
                      secondary: Icon(Icons.folder_outlined,
                          color: enabled ? cs.primary : cs.onSurface.withAlpha(80)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMs(int? ms) {
    if (ms == null || ms < 0) return '00:00';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Lazy album-art thumbnail.
///
/// Instant if [ArtworkLoader] already has the bytes in memory;
/// otherwise loads disk → DB → file extract without blocking the list.
class ArtworkThumb extends StatefulWidget {
  const ArtworkThumb({
    super.key,
    required this.song,
    this.size = 44,
    this.radius,
    this.isPlaying = false,
  });

  final SongItem song;
  final double size;
  final BorderRadius? radius;
  final bool isPlaying;

  @override
  State<ArtworkThumb> createState() => _ArtworkThumbState();
}

class _ArtworkThumbState extends State<ArtworkThumb> {
  List<int>? _bytes;
  Uint8List? _image;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _setBytes(ArtworkLoader.instance.peek(widget.song) ?? widget.song.artworkBytes);
    if (_bytes == null) {
      _load();
    }
  }

  void _setBytes(List<int>? bytes) {
    if (bytes != null && bytes.isEmpty) bytes = null;
    _bytes = bytes;
    // Keep one Uint8List instance so Image.memory does not re-decode every rebuild.
    _image = bytes != null ? Uint8List.fromList(bytes) : null;
  }

  @override
  void didUpdateWidget(covariant ArtworkThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.path != widget.song.path ||
        oldWidget.song.dbId != widget.song.dbId) {
      _setBytes(ArtworkLoader.instance.peek(widget.song) ?? widget.song.artworkBytes);
      if (_bytes == null) {
        _load();
      } else {
        setState(() {});
      }
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final bytes = await ArtworkLoader.instance.load(widget.song);
      if (!mounted) return;
      setState(() => _setBytes(bytes));
    } catch (_) {
      if (!mounted) setState(() => _setBytes(null));
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final image = _image;
    if (image != null) {
      return ClipRRect(
        borderRadius: widget.radius ?? BorderRadius.circular(8),
        child: Image.memory(
          image,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, __, ___) => _fallback(cs),
        ),
      );
    }
    return _fallback(cs);
  }

  Widget _fallback(ColorScheme cs) {
    return AppLogo(
      size: widget.size,
      fit: BoxFit.cover,
      radius: widget.radius ?? BorderRadius.circular(8),
      backgroundColor: widget.isPlaying
          ? cs.primary.withAlpha(30)
          : cs.surfaceContainerHighest,
    );
  }
}
