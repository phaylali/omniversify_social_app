import 'dart:io';

import 'package:flutter/material.dart';

import '../services/local_books.dart';

/// Picks one folder to add to the reader's Local tab.
///
/// Its own browser rather than a system picker for two reasons: the reader
/// needs a real path it can scan with `dart:io`, which only works once "All
/// files access" is granted, and the screen can say so in plain words before
/// anything is listed.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key, this.startPath});

  /// Where the browser opens — defaults to shared storage.
  final String? startPath;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  static const String _root = '/storage/emulated/0';

  late String _path;
  List<String> _children = const [];
  bool _loading = true;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _path = widget.startPath ?? _root;
    _list();
  }

  Future<void> _list() async {
    setState(() {
      _loading = true;
      _blocked = false;
    });
    final entries = <String>[];
    var denied = false;
    try {
      final listing = Directory(_path).listSync(followLinks: false);
      for (final entry in listing) {
        if (entry is! Directory) continue;
        // The path, not the URI: a directory URI ends in "/", so its last
        // path segment is always empty and every folder would be skipped.
        final name = _nameOf(entry.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        entries.add('${_path == '/' ? '' : _path}/$name');
      }
    } on FileSystemException {
      denied = true;
    } catch (_) {
      denied = true;
    }
    entries.sort(
      (a, b) => _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _children = entries;
      _blocked = denied && entries.isEmpty;
      _loading = false;
    });
  }

  static String _nameOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  void _up() {
    if (_path == _root) return;
    final slash = _path.lastIndexOf('/');
    setState(() => _path = slash <= 0 ? _root : _path.substring(0, slash));
    _list();
  }

  Future<void> _grantAccess() async {
    final granted = await LocalBooksService.instance.ensureAccess();
    if (granted) _list();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final title = _path == _root ? 'This phone' : _nameOf(_path);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Up one level',
            onPressed: _path == _root ? null : _up,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
        ],
      ),
      body: _blocked ? _blockedNotice(cs, gold) : _listing(cs, gold),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_path),
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Add this folder'),
          ),
        ),
      ),
    );
  }

  Widget _blockedNotice(ColorScheme cs, Color gold) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 36, color: gold),
          const SizedBox(height: 14),
          Text(
            'This folder can\'t be read yet',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Turn on "All files access" for Omniversify and the folders on '
            'this phone will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onSurface.withAlpha(170),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonal(
            onPressed: _grantAccess,
            child: const Text('Grant access'),
          ),
        ],
      ),
    ),
  );

  Widget _listing(ColorScheme cs, Color gold) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFC2B067)),
      );
    }
    if (_children.isEmpty) {
      return Center(
        child: Text(
          'No folders inside.',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(150)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _children.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (context, index) {
        final path = _children[index];
        return ListTile(
          dense: true,
          leading: Icon(Icons.folder_outlined, color: gold, size: 20),
          title: Text(
            _nameOf(path),
            style: TextStyle(fontSize: 13.5, color: cs.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(Icons.chevron_right, size: 18, color: cs.outline),
          onTap: () {
            setState(() => _path = path);
            _list();
          },
        );
      },
    );
  }
}
