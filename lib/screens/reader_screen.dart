import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../services/activity_service.dart';
import '../services/book_loader.dart';
import '../services/discover_source.dart';
import '../services/local_books.dart';
import '../services/privacy_service.dart';
import '../services/reader_library.dart';
import '../widgets/action_sheet.dart';
import '../widgets/sliding_tabs.dart';
import 'folder_picker_screen.dart';
import 'privacy_screen.dart';

/// The books & comics tool, in three tabs:
///
/// * **Local** — files on this phone: open one directly, watch folders, or
///   scan the whole device.
/// * **Discover** — books fetched from an open source (the Internet Archive
///   today), downloaded and opened here.
/// * **Library** — everything recently opened with a progress bar under each
///   title; tapping one resumes on exactly the page you left.
///
/// Whatever book is open is reported to [ActivityService], so the
/// Acquaintances tab can show it — exactly as far as the Privacy setting
/// allows.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderTab {
  static const local = 'Local';
  static const discover = 'Discover';
  static const library = 'Library';

  static const all = [local, discover, library];
}

class _ReaderScreenState extends State<ReaderScreen>
    with TickerProviderStateMixin {
  // ── Tabs ──────────────────────────────────────────────────────────────
  int _tab = 0;

  /// Fades the tab's content in when the tab changes.
  late final AnimationController _veil = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..value = 1;

  // ── The open book ─────────────────────────────────────────────────────
  BookDocument? _doc;
  bool _loading = false;
  String? _openingPath;

  /// Tap the page to hide/show the bars.
  bool _chrome = true;

  int _index = 0;
  PageController? _controller;

  /// Rendered PDF pages: the future once (so rebuilds don't re-render) and
  /// the finished bitmap for a small LRU of recent pages.
  final Map<int, Future<Uint8List?>> _pageFutures = {};
  final Map<int, Uint8List> _pageCache = {};

  /// Where the open book lives, so the Library can find it again.
  String _openPath = '';
  String _openSource = 'local';

  /// Page turns land in the Library after a short pause rather than on
  /// every flick of the thumb.
  Timer? _recordTimer;
  int? _pendingPage;

  // ── Discover ──────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final List<DiscoverItem> _results = [];
  bool _searching = false;
  String? _searchError;
  String _query = '';
  DiscoverItem? _downloading;
  double _downloadProgress = -1;

  static const DiscoverSource _source = InternetArchiveSource();

  @override
  void initState() {
    super.initState();
    ReaderLibrary.instance.load();
    LocalBooksService.instance.load();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _flushProgress();
    final doc = _doc;
    if (doc != null) doc.close();
    _controller?.dispose();
    _veil.dispose();
    _searchController.dispose();
    ActivityService.instance.reading.value = null;
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    _veil.forward(from: 0);
  }

  // ── Opening ───────────────────────────────────────────────────────────

  Future<void> _pick() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final file = files.first;
      if (BookLoader.formatOf(file.name) == null) {
        throw const BookOpenException(
          'That file type isn\'t supported — try a PDF, EPUB, CBZ or CBR.',
        );
      }
      final bytes = await file.readAsBytes();
      await _open(
        bytes,
        file.name,
        path: file.path ?? file.name,
        source: 'local',
      );
    } on BookOpenException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        showActionNotice(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        showActionNotice(context, 'That file couldn\'t be opened.');
      }
    }
  }

  /// Opens a book from a path — a watched folder, a scan, or the Library.
  Future<void> _openFromPath(
    String path, {
    String source = 'local',
    int startPage = 0,
    String? title,
  }) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _openingPath = path;
    });
    try {
      final file = File(path);
      if (!file.existsSync()) {
        throw const BookOpenException('That file is no longer on this phone.');
      }
      final bytes = await file.readAsBytes();
      await _open(
        bytes,
        path,
        path: path,
        source: source,
        startPage: startPage,
        title: title,
      );
    } on BookOpenException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _openingPath = null;
        });
        showActionNotice(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _openingPath = null;
        });
        showActionNotice(context, 'That file couldn\'t be opened.');
      }
    }
  }

  /// Everything that opens a book ends here: decode, then land on
  /// [startPage] and tell the Library where it stopped.
  Future<void> _open(
    Uint8List bytes,
    String name, {
    required String path,
    String source = 'local',
    int startPage = 0,
    String? title,
  }) async {
    final doc = await BookLoader.open(bytes, name, title: title);
    await _closeDocument();
    _controller?.dispose();

    final last = doc.pageCount > 0 ? doc.pageCount - 1 : 0;
    final resume = startPage < 0 ? 0 : (startPage > last ? last : startPage);

    _controller = PageController(initialPage: resume);
    _pageFutures.clear();
    _pageCache.clear();
    ActivityService.instance.reading.value = doc.title;
    if (!mounted) {
      doc.close();
      return;
    }
    setState(() {
      _doc = doc;
      _index = resume;
      _loading = false;
      _openingPath = null;
      _chrome = true;
      _openPath = path;
      _openSource = source;
    });
    ReaderLibrary.instance.record(
      path: path,
      title: doc.title,
      format: doc.format.name,
      page: resume + 1,
      pages: doc.pageCount,
      source: source,
    );
    showActionNotice(context, 'Opened "${doc.title}"');
  }

  /// Back to the landing page — the book stops being shared too.
  Future<void> _closeDocument() async {
    _flushProgress();
    final doc = _doc;
    ActivityService.instance.reading.value = null;
    _doc = null;
    if (doc != null) await doc.close();
  }

  Future<void> _closeAndReset() async {
    await _closeDocument();
    _controller?.dispose();
    _controller = null;
    _pageFutures.clear();
    _pageCache.clear();
    if (mounted) {
      setState(() {
        _index = 0;
        _chrome = true;
        _openPath = '';
        _openSource = 'local';
      });
    }
  }

  // ── Library progress ──────────────────────────────────────────────────

  void _recordSoon(int page) {
    _pendingPage = page;
    _recordTimer?.cancel();
    _recordTimer = Timer(const Duration(milliseconds: 400), _flushProgress);
  }

  /// Writes the current position to the Library — synchronously enough for
  /// dispose(), which can't await anything.
  void _flushProgress() {
    _recordTimer?.cancel();
    _recordTimer = null;
    final page = _pendingPage;
    final doc = _doc;
    _pendingPage = null;
    if (page == null || doc == null || _openPath.isEmpty) return;
    ReaderLibrary.instance.record(
      path: _openPath,
      title: doc.title,
      format: doc.format.name,
      page: page,
      pages: doc.pageCount,
      source: _openSource,
    );
  }

  // ── Discover ──────────────────────────────────────────────────────────

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _query = query;
      _searching = true;
      _searchError = null;
      _results.clear();
    });
    try {
      final found = await _source.search(query);
      if (!mounted) return;
      setState(() {
        _results.addAll(found);
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'Couldn\'t reach the Archive — check your connection.';
      });
    }
  }

  Future<Directory> _downloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/discover');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _safeName(String text) => text
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  Future<void> _openFromDiscover(DiscoverItem item) async {
    if (_downloading != null || _loading) return;
    setState(() {
      _downloading = item;
      _downloadProgress = -1;
    });
    try {
      final file = await _source.resolve(item);
      if (file == null) {
        if (mounted) {
          showActionNotice(
            context,
            'That item holds nothing this reader can open.',
          );
        }
        return;
      }

      final dir = await _downloadDir();
      final path = '${dir.path}/${_safeName(item.id)}.${file.extension}';
      final saved = File(path);
      if (!saved.existsSync() || saved.lengthSync() == 0) {
        await _source.download(
          file,
          path,
          onProgress: (progress) {
            if (mounted) setState(() => _downloadProgress = progress);
          },
        );
      }

      final bytes = await saved.readAsBytes();
      if (!mounted) return;
      await _open(
        bytes,
        '${item.title}.${file.extension}',
        path: path,
        source: 'discover',
      );
    } catch (_) {
      if (mounted) {
        showActionNotice(context, 'That download didn\'t work — try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = null;
          _downloadProgress = -1;
        });
      }
    }
  }

  // ── Rendering ─────────────────────────────────────────────────────────

  Future<Uint8List?> _renderPage(int index) async {
    final pdf = _doc?.pdf;
    if (pdf == null) return null;
    try {
      final page = await pdf.getPage(index + 1);
      const width = 1300.0;
      final height = width * page.height / page.width;
      final image = await page.render(
        width: width,
        height: height,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 85,
      );
      await page.close();
      final bytes = image?.bytes;
      if (bytes != null) {
        _pageCache[index] = bytes;
        while (_pageCache.length > 8 && _pageCache.length > 1) {
          final oldest = _pageCache.keys.first;
          if (oldest == index) break;
          _pageCache.remove(oldest);
        }
      }
      return bytes;
    } catch (_) {
      // The document closed underneath us, or the page failed to rasterise.
      return null;
    }
  }

  Widget _pdfPage(int index) {
    final cached = _pageCache[index];
    if (cached != null) return _imagePage(cached);
    final future = _pageFutures.putIfAbsent(index, () => _renderPage(index));
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFC2B067)),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: Text(
              'Page ${index + 1} couldn\'t be rendered',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
        }
        return _imagePage(data);
      },
    );
  }

  Widget _imagePage(Uint8List bytes) => Container(
    color: const Color(0xFF0B0B0E),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white38,
          size: 40,
        ),
      ),
    ),
  );

  Widget _chapterPage(BookChapter chapter) => Container(
    color: const Color(0xFF0B0B0E),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: const TextStyle(
              color: Color(0xFFF2E9DC),
              fontSize: 21,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            chapter.body,
            style: const TextStyle(
              color: Color(0xFFDED7CB),
              fontSize: 16.5,
              height: 1.75,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _readerBody() {
    final doc = _doc;
    if (doc == null) return const SizedBox.shrink();
    if (doc.format == BookFormat.epub) {
      return PageView.builder(
        controller: _controller,
        itemCount: doc.chapters.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) => _chapterPage(doc.chapters[i]),
      );
    }
    return PageView.builder(
      controller: _controller,
      itemCount: doc.pageCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) => doc.format == BookFormat.pdf
          ? _pdfPage(i)
          : _imagePage(doc.images[i]),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _recordSoon(index + 1);
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc != null) return _viewer(doc);
    return _landing();
  }

  Widget _landing() {
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: Column(
        children: [
          SlidingTabs(
            labels: _ReaderTab.all,
            index: _tab,
            onSelect: _selectTab,
          ),
          Expanded(
            child: FadeTransition(
              opacity: _veil,
              child: IndexedStack(
                index: _tab,
                children: [_localTab(), _discoverTab(), _libraryTab()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1 · local ─────────────────────────────────────────────────────

  Widget _localTab() {
    final service = LocalBooksService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        service.folders,
        service.byFolder,
        service.scanned,
        service.busy,
        service.notice,
      ]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _pick,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(_loading ? 'Opening…' : 'Open a book'),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _outlineButton(
                  label: 'Add a folder',
                  icon: Icons.create_new_folder_outlined,
                  onPressed: _addFolder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _outlineButton(
                  label: service.busy.value ? 'Scanning…' : 'Scan this phone',
                  icon: Icons.search,
                  onPressed: service.busy.value ? null : _scanPhone,
                ),
              ),
            ],
          ),
          if (service.notice.value != null) ...[
            const SizedBox(height: 10),
            Text(
              service.notice.value!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ..._folderSections(),
          const SizedBox(height: 20),
          ..._formatBlurbs(),
          const SizedBox(height: 16),
          _sharingCard(),
        ],
      ),
    );
  }

  Future<void> _addFolder() async {
    final granted = await LocalBooksService.instance.ensureAccess();
    if (!granted || !mounted) return;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const FolderPickerScreen()),
    );
    if (picked == null || !mounted) return;
    await LocalBooksService.instance.addFolder(picked);
    if (mounted) setState(() {});
  }

  Future<void> _scanPhone() async {
    await LocalBooksService.instance.scanPhone();
    if (mounted) setState(() {});
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: gold,
        side: BorderSide(color: gold.withAlpha(90)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// One block per watched folder, then whatever a full scan turned up.
  List<Widget> _folderSections() {
    final service = LocalBooksService.instance;
    final rows = <Widget>[];
    final folders = service.folders.value;

    for (final folder in folders) {
      final books = service.byFolder.value[folder] ?? const <FoundBook>[];
      final name = folder.split('/').last;
      rows.add(
        _sectionLabel(
          '${books.length} in $name',
          trailing: () async {
            await service.removeFolder(folder);
            if (mounted) setState(() {});
          },
        ),
      );
      if (books.isEmpty) {
        rows.add(_hint('No supported books in this folder yet.'));
      }
      rows.addAll([
        for (final book in books) _bookRow(book),
        const SizedBox(height: 14),
      ]);
    }

    final scanned = service.scanned.value;
    if (scanned.isNotEmpty) {
      rows.add(_sectionLabel('${scanned.length} found on this phone'));
      rows.addAll([
        for (final book in scanned.take(60)) _bookRow(book),
        if (scanned.length > 60)
          _hint('Showing the first 60 — add a folder to narrow it down.'),
        const SizedBox(height: 14),
      ]);
    }

    if (rows.isEmpty) {
      rows.addAll([
        _sectionLabel('On this phone'),
        _hint(
          'Add a folder to keep an eye on, or scan the whole phone once — '
          'the books you already own show up right here.',
        ),
        const SizedBox(height: 14),
      ]);
    }
    return rows;
  }

  Widget _sectionLabel(String text, {VoidCallback? trailing}) {
    final gold = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ),
          if (trailing != null)
            GestureDetector(
              onTap: trailing,
              child: Icon(Icons.close, size: 14, color: gold.withAlpha(160)),
            ),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.5,
        color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
      ),
    ),
  );

  Widget _bookRow(FoundBook book) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final opening = _openingPath == book.path;

    return InkWell(
      onTap: opening || _loading
          ? null
          : () => _openFromPath(book.path, title: book.title),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            _formatChip(book.format.label),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${book.format.label} · ${book.size}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurface.withAlpha(150),
                    ),
                  ),
                ],
              ),
            ),
            if (opening)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFC2B067),
                ),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: gold.withAlpha(140)),
          ],
        ),
      ),
    );
  }

  Widget _formatChip(String label) {
    final gold = Theme.of(context).colorScheme.primary;
    return Container(
      width: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: gold.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: gold.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
          color: gold,
        ),
      ),
    );
  }

  List<Widget> _formatBlurbs() => [
    for (final format in BookFormat.values)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _formatChip(format.label),
            const SizedBox(width: 12),
            Text(
              format.blurb,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(170),
              ),
            ),
          ],
        ),
      ),
  ];

  Widget _sharingCard() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return ValueListenableBuilder<ShareAudience>(
      valueListenable: PrivacyService.instance.audience,
      builder: (context, audience, _) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: gold.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: gold.withAlpha(60)),
          ),
          child: Row(
            children: [
              Icon(audience.icon, size: 18, color: gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sharing: ${audience.label}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'What you read is shown to ${audience.blurb.toLowerCase()}.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: cs.onSurface.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 2 · discover ──────────────────────────────────────────────────

  Widget _discoverTab() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: gold.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 13, color: gold),
                  const SizedBox(width: 6),
                  Text(
                    _source.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: gold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 13, color: cs.outline),
                  const SizedBox(width: 4),
                  Text(
                    'ADD SOURCE · SOON',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Search comics and books…',
            hintStyle: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withAlpha(120),
            ),
            prefixIcon: Icon(Icons.search, size: 20, color: gold),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFC2B067),
                      ),
                    ),
                  )
                : null,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withAlpha(70),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: gold.withAlpha(70)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: gold.withAlpha(70)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: gold, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_downloading != null) ...[
          _downloadRow(gold),
          const SizedBox(height: 16),
        ],
        if (_searchError != null) ...[
          _hint(_searchError!),
          OutlinedButton(onPressed: _search, child: const Text('Try again')),
        ] else if (_results.isEmpty && !_searching && _searchError == null) ...[
          _hint(
            _query.isEmpty
                ? 'Search the Archive for anything you want to read — free, '
                      'open, no sign-in.'
                : 'Nothing found for "$_query".',
          ),
        ] else
          _resultGrid(),
      ],
    );
  }

  Widget _downloadRow(Color gold) {
    final item = _downloading!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Downloading ${item.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: _downloadProgress < 0 ? null : _downloadProgress,
            minHeight: 6,
            backgroundColor: gold.withAlpha(30),
            valueColor: AlwaysStoppedAnimation(gold),
          ),
        ),
      ],
    );
  }

  Widget _resultGrid() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.66,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        final busy = _downloading?.id == item.id;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy || _downloading != null
              ? null
              : () => _openFromDiscover(item),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(60),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gold.withAlpha(50)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: busy
                        ? Center(
                            child: CircularProgressIndicator(
                              value: _downloadProgress < 0
                                  ? null
                                  : _downloadProgress,
                              strokeWidth: 2,
                              color: gold,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Center(
                              child: Icon(
                                Icons.menu_book_outlined,
                                size: 26,
                                color: gold.withAlpha(90),
                              ),
                            ),
                            errorWidget: (_, _, _) => Center(
                              child: Icon(
                                Icons.menu_book_outlined,
                                size: 26,
                                color: gold.withAlpha(90),
                              ),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (item.meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: cs.onSurface.withAlpha(140),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3 · library ───────────────────────────────────────────────────

  Widget _libraryTab() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return ValueListenableBuilder<List<LibraryEntry>>(
      valueListenable: ReaderLibrary.instance.entries,
      builder: (context, entries, _) {
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 38,
                  color: gold.withAlpha(120),
                ),
                const SizedBox(height: 14),
                Text(
                  'Nothing here yet',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Books you open — from this phone or from Discover — show '
                  'up here with a bar for how far you got.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: cs.onSurface.withAlpha(160),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          itemCount: entries.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: cs.outlineVariant),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final opening = _openingPath == entry.path;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: opening || _loading
                  ? null
                  : () => _openFromPath(
                      entry.path,
                      source: entry.source,
                      startPage: entry.resumeIndex,
                      title: entry.title,
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _formatChip(entry.format.toUpperCase()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: entry.progress,
                              minHeight: 6,
                              backgroundColor: gold.withAlpha(30),
                              valueColor: AlwaysStoppedAnimation(gold),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                entry.label,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: gold,
                                ),
                              ),
                              if (entry.source == 'discover') ...[
                                const SizedBox(width: 8),
                                Text(
                                  'DOWNLOADED',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface.withAlpha(130),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (opening)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFC2B067),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: 'Remove from library',
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: cs.onSurface.withAlpha(120),
                        ),
                        onPressed: () =>
                            ReaderLibrary.instance.remove(entry.path),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Viewer ────────────────────────────────────────────────────────────

  Widget _viewer(BookDocument doc) {
    final count = doc.pageCount;
    final position = '${doc.unit} ${_index + 1} of ${count < 1 ? 1 : count}';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0E),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _chrome = !_chrome),
            child: _readerBody(),
          ),
          if (_chrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white70,
                            size: 20,
                          ),
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            doc.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 20,
                          ),
                          tooltip: 'Close book',
                          onPressed: _closeAndReset,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_chrome)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _privacyChip(),
                        const Spacer(),
                        if (doc.format == BookFormat.epub)
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white70,
                              size: 22,
                            ),
                            tooltip: 'Previous chapter',
                            onPressed: _index <= 0
                                ? null
                                : () => _controller!.previousPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          ),
                        Text(
                          position,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (doc.format == BookFormat.epub)
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white70,
                              size: 22,
                            ),
                            tooltip: 'Next chapter',
                            onPressed: _index >= count - 1
                                ? null
                                : () => _controller!.nextPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _privacyChip() {
    return ValueListenableBuilder<ShareAudience>(
      valueListenable: PrivacyService.instance.audience,
      builder: (context, audience, _) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(audience.icon, size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                audience.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
