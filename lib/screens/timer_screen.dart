import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _timer;
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  bool _isRunning = false;
  bool _isSet = false;
  double _volume = 0.7;
  String _selectedTone = '';
  final TextEditingController _customController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<String> _toneFiles = [];
  bool _loadingTones = true;

  final List<(String, int)> _presets = [
    ('1 min', 60),
    ('3 min', 180),
    ('5 min', 300),
    ('10 min', 600),
    ('15 min', 900),
    ('25 min', 1500),
    ('30 min', 1800),
    ('60 min', 3600),
  ];

  static const _prefKey = 'timer_selected_tone';
  static const _prefVolume = 'timer_volume';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadTones();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTone = prefs.getString(_prefKey) ?? '';
      _volume = prefs.getDouble(_prefVolume) ?? 0.7;
    });
    _audioPlayer.setVolume(_volume);
  }

  Future<void> _saveTonePreference(String tone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, tone);
  }

  Future<void> _saveVolumePreference(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefVolume, volume);
  }

  Future<void> _loadTones() async {
    try {
      // Try both old and new manifest formats
      List<String> tones = [];

      try {
        // New format (Flutter 3.x+)
        final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        tones = assetManifest.listAssets()
            .where((key) => key.startsWith('assets/tones/') && key.endsWith('.mp3'))
            .map((key) => key.replaceFirst('assets/tones/', ''))
            .toList();
      } catch (_) {
        // Fallback to old JSON format
        try {
          final manifestContent = await rootBundle.loadString('AssetManifest.json');
          final Map<String, dynamic> manifest = json.decode(manifestContent);
          tones = manifest.keys
              .where((key) => key.startsWith('assets/tones/') && key.endsWith('.mp3'))
              .map((key) => key.replaceFirst('assets/tones/', ''))
              .toList();
        } catch (_) {}
      }

      tones.sort();

      if (tones.isEmpty) {
        setState(() {
          _toneFiles = [];
          _loadingTones = false;
        });
        return;
      }

      // Find longest duration tone as default
      String longestTone = tones.first;
      int longestDurationMs = 0;

      for (final tone in tones) {
        try {
          final player = AudioPlayer();
          await player.setSource(AssetSource('tones/$tone'));
          // Wait briefly for duration to be determined
          await Future.delayed(const Duration(milliseconds: 200));
          final duration = await player.getDuration();
          if (duration != null && duration.inMilliseconds > longestDurationMs) {
            longestDurationMs = duration.inMilliseconds;
            longestTone = tone;
          }
          await player.dispose();
        } catch (_) {}
      }

      if (mounted) {
        // Only auto-select longest if user has no saved preference
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(_prefKey);

        setState(() {
          _toneFiles = tones;
          if (saved != null && tones.contains(saved)) {
            _selectedTone = saved;
          } else if (_selectedTone.isEmpty || !tones.contains(_selectedTone)) {
            _selectedTone = longestTone;
          }
          _loadingTones = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _toneFiles = [];
          _loadingTones = false;
        });
      }
    }
  }

  String _toneDisplayName(String filename) {
    // Remove extension and clean up filename
    return filename
        .replaceAll('.mp3', '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  Future<void> _playTone() async {
    if (_selectedTone.isEmpty) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('tones/$_selectedTone'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _startTimer() {
    if (_remainingSeconds <= 0) return;
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _isRunning = false;
          _timer?.cancel();
          _playTone();
        }
      });
    });
  }

  void _pauseTimer() {
    setState(() => _isRunning = false);
    _timer?.cancel();
    _timer = null;
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _isRunning = false;
      _isSet = false;
      _totalSeconds = 0;
      _remainingSeconds = 0;
    });
  }

  void _setPreset(int seconds) {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _totalSeconds = seconds;
      _remainingSeconds = seconds;
      _isSet = true;
      _isRunning = false;
    });
  }

  void _setCustomTime() {
    final text = _customController.text.trim();
    if (text.isEmpty) return;

    final parts = text.split(':');
    int seconds = 0;

    try {
      if (parts.length == 3) {
        seconds = int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2]);
      } else if (parts.length == 2) {
        seconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else {
        seconds = int.parse(parts[0]);
      }
    } catch (_) {
      return;
    }

    if (seconds > 0 && seconds <= 86400) {
      _setPreset(seconds);
      _customController.clear();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    _customController.dispose();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress => _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timer'),
        actions: [
          IconButton(
            icon: Icon(
              _volume == 0 ? Icons.volume_off : _volume < 0.5 ? Icons.volume_down : Icons.volume_up,
              size: 22,
            ),
            onPressed: _showVolumeSlider,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height - AppBar().preferredSize.height - MediaQuery.of(context).padding.top,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Timer display
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _progress,
                          strokeWidth: 6,
                          backgroundColor: surface,
                          color: _remainingSeconds <= 10 && _isRunning ? Colors.red : gold,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isSet ? _formatTime(_remainingSeconds) : '00:00',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w200,
                              color: _remainingSeconds <= 10 && _isRunning ? Colors.red : gold,
                            ),
                          ),
                          if (_isSet && _isRunning)
                            Text('remaining', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                          if (_isSet && !_isRunning && _remainingSeconds > 0 && _remainingSeconds < _totalSeconds)
                            Text('paused', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                          if (_isSet && _remainingSeconds == 0 && _totalSeconds > 0)
                            Text('done!', style: TextStyle(fontSize: 13, color: gold)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Controls
                if (_isSet)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _controlButton(context, icon: Icons.replay, onTap: _resetTimer),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: _remainingSeconds > 0 ? (_isRunning ? _pauseTimer : _startTimer) : null,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(color: gold, shape: BoxShape.circle),
                          child: Icon(
                            _isRunning ? Icons.pause : Icons.play_arrow,
                            color: Theme.of(context).colorScheme.surface,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      _controlButton(
                        context,
                        icon: Icons.stop,
                        onTap: () {
                          _timer?.cancel();
                          _timer = null;
                          setState(() {
                            _isRunning = false;
                            _remainingSeconds = _totalSeconds;
                          });
                        },
                      ),
                    ],
                  )
                else
                  Text('Choose a preset or enter custom time', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14)),

                const SizedBox(height: 32),

                // Custom input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        keyboardType: TextInputType.datetime,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'MM:SS or HH:MM:SS',
                          hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(120)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: surface),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: surface),
                          ),
                        ),
                        onSubmitted: (_) => _setCustomTime(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _setCustomTime,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.surface, size: 20),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Ringtone selector
                if (_loadingTones)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: gold)),
                        const SizedBox(width: 8),
                        Text('Loading tones...', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                      ],
                    ),
                  )
                else if (_toneFiles.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.music_note_outlined, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(width: 8),
                      Text('Tone:', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedTone.isNotEmpty && _toneFiles.contains(_selectedTone) ? _selectedTone : null,
                              isDense: true,
                              isExpanded: true,
                              hint: Text('Select tone', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                              style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                              items: _toneFiles.map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(_toneDisplayName(f), overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedTone = v);
                                  _saveTonePreference(v);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 22),
                        onPressed: _playTone,
                        tooltip: 'Preview',
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _presets.map((p) {
                    final (label, seconds) = p;
                    final isSelected = _totalSeconds == seconds;
                    return GestureDetector(
                      onTap: () => _setPreset(seconds),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? gold.withAlpha(30) : surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? gold.withAlpha(80) : Colors.transparent, width: 0.5),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? gold : Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVolumeSlider() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_volume == 0 ? Icons.volume_off : _volume < 0.5 ? Icons.volume_down : Icons.volume_up, size: 20),
                const SizedBox(width: 8),
                Text('Volume', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Slider(
              value: _volume,
              onChanged: (v) {
                setState(() => _volume = v);
                _audioPlayer.setVolume(v);
                _saveVolumePreference(v);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _controlButton(BuildContext context, {required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: Theme.of(context).textTheme.bodySmall?.color),
      ),
    );
  }
}
