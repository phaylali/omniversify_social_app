import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/media_api.dart';
import '../services/tracker_collection_service.dart';

/// Where a library can come from — and, honestly, what each service offers.
///
/// Steam is the only one of these that publishes an API for reading a
/// player's games, so Steam works now. Goodreads stopped issuing API keys
/// in 2020 and Letterboxd never had one; both offer an official export file
/// instead, and that import is next. Epic publishes no way at all to read a
/// library, so the entry says so rather than promising something it cannot
/// do.
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _header(context, 'GAMES'),
          _entry(
            context,
            icon: Icons.sports_esports_outlined,
            title: 'Steam',
            subtitle: 'Import the games you own, with the hours you put in',
            status: 'Works now',
            onTap: () => showSteamImportSheet(context),
          ),
          _entry(
            context,
            icon: Icons.gamepad_outlined,
            title: 'Epic Games',
            subtitle: 'Epic exposes no API for reading a library — add these by hand',
            status: 'Not available',
            muted: true,
          ),
          _header(context, 'BOOKS'),
          _entry(
            context,
            icon: Icons.menu_book_outlined,
            title: 'Goodreads',
            subtitle: 'Export your library from Goodreads, then bring the file here',
            status: 'Next',
            muted: true,
          ),
          _header(context, 'FILM'),
          _entry(
            context,
            icon: Icons.movie_outlined,
            title: 'Letterboxd',
            subtitle: 'Export your diary and watchlist, then bring the file here',
            status: 'Next',
            muted: true,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
      ),
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    bool muted = false,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: muted ? cs.onSurface.withAlpha(90) : cs.primary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          color: muted ? cs.onSurface.withAlpha(160) : null,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: _statusChip(context, status, muted: muted),
      onTap: onTap,
    );
  }

  Widget _statusChip(BuildContext context, String status, {required bool muted}) {
    final color = muted ? Colors.grey : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

/// The last profile typed in, so a re-sync later is one tap.
const String steamProfileKey = 'steam_profile_v1';

/// Paste a Steam profile and put what it owns on a shelf — `games` →
/// `owned` by default. The import writes straight to the local store, so
/// the shelf refreshes itself wherever it is on screen.
Future<void> showSteamImportSheet(
  BuildContext context, {
  Color? accent,
  String category = 'games',
  String slot = 'owned',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SteamImportSheet(
      accent: accent ?? Theme.of(sheetContext).colorScheme.primary,
      category: category,
      slot: slot,
    ),
  );
}

class _SteamImportSheet extends StatefulWidget {
  const _SteamImportSheet({
    required this.accent,
    required this.category,
    required this.slot,
  });

  final Color accent;
  final String category;
  final String slot;

  @override
  State<_SteamImportSheet> createState() => _SteamImportSheetState();
}

class _SteamImportSheetState extends State<_SteamImportSheet> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The field owns its controller, so it is only disposed here, once the
    // sheet has finished animating out with it.
    _controller = TextEditingController();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(steamProfileKey);
      if (!mounted) return;
      if (saved != null && saved.isNotEmpty) _controller.text = saved;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    final onOwned = widget.category == 'games' && widget.slot == 'owned';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_esports_outlined, size: 20, color: widget.accent),
              const SizedBox(width: 8),
              Text(
                'Import from Steam',
                style: style.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: widget.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your games, with the hours you have put in. The profile\'s '
            'game details have to be public for Steam to hand them over.',
            style: style.bodySmall,
          ),
          if (onOwned) ...[
            const SizedBox(height: 4),
            Text(
              'They land on your Owned shelf.',
              style: style.bodySmall?.copyWith(color: widget.accent),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('steam-profile'),
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Steam profile',
              hintText: 'steamcommunity.com/id/yourname',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Import'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final profile = _controller.text.trim();
    if (profile.isEmpty) {
      setState(() => _error = 'Enter a Steam profile URL or name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final payload = await MediaApi.steamLibrary(profile: profile);
      final results = (payload['results'] as List<dynamic>? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final total = payload['total'] as int? ?? results.length;
      final unmatched =
          (payload['unmatched'] as List<dynamic>? ?? const []).length;

      await TrackerCollectionService.instance
          .addAll(widget.category, results, widget.slot);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(steamProfileKey, profile);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_summary(results.length, total, unmatched))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  String _summary(int imported, int total, int unmatched) {
    if (imported == 0) return 'None of your $total games matched yet';
    if (unmatched > 0) {
      return 'Imported $imported of $total games — '
          '$unmatched not in Omniversify yet';
    }
    return 'Imported $imported games';
  }
}
