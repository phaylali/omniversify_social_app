import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../models/song_item.dart';
import '../services/audio_scanner.dart';
import '../services/audio_metadata_extractor.dart';
import '../services/audio_player_service.dart';
import '../services/music_library_service.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
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

  @override
  void initState() {
    super.initState();
    _service.init();
    _service.connectAudioService();
    _requestPermission();

    _service.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
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
      final quick = await scanAudioFilesQuick();
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
      final folders = enriched.map((s) => s.folder).toSet();
      List<SongItem> filtered = enriched
          .where((s) => _allowedFolders.contains(s.folder) || _allowedFolders.isEmpty)
          .where((s) =>
              q.isEmpty ||
              s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q) ||
              (s.album ?? '').toLowerCase().contains(q))
          .toList();
      setState(() {
        _allSongs = enriched;
        _allowedFolders = folders.isEmpty ? _allowedFolders : folders;
        _filtered = filtered;
        _enriching = false;
      });
      memory.store(enriched);
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
      setState(() {
        _allSongs = enriched;
        _allowedFolders = enriched.map((s) => s.folder).toSet();
        _filtered = List.from(enriched);
        _enriching = false;
      });
      MusicLibraryService.instance.store(enriched);
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
                                    bottom: currentSong != null ? 140 : 12),
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
      leading: _artworkThumb(song.artworkBytes, cs, isPlaying),
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

  Widget _artworkThumb(List<int>? bytes, ColorScheme cs, bool isPlaying) {
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          Uint8List.fromList(bytes),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultArt(cs, isPlaying),
        ),
      );
    }
    return _defaultArt(cs, isPlaying);
  }

  Widget _defaultArt(ColorScheme cs, bool isPlaying) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isPlaying ? cs.primary.withAlpha(30) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isPlaying ? Icons.equalizer : Icons.music_note,
        color: isPlaying ? cs.primary : cs.onSurface.withAlpha(80),
        size: 22,
      ),
    );
  }

  Widget _playerBar(ColorScheme cs) {
    final song = _service.currentSong!;
    final duration = _service.duration;
    final position = _service.position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Container(
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
              if (song.artworkBytes != null && song.artworkBytes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      Uint8List.fromList(song.artworkBytes!),
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
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
              IconButton(
                  tooltip: 'Share file',
                  icon: Icon(Icons.share_outlined,
                      color: cs.onSurface.withAlpha(180), size: 20),
                  onPressed: () => _shareCurrentSong()),
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
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(song.path)],
          text: '${song.title} ${song.artist ?? ''}'.trim(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this file')),
      );
    }
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
