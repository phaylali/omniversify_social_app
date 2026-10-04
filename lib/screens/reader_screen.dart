import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../services/activity_service.dart';
import '../services/book_loader.dart';
import '../services/discover_source.dart';
import '../services/local_books.dart';
import '../services/open_file_service.dart';
import '../services/privacy_service.dart';
import '../services/reader_library.dart';
import '../widgets/action_sheet.dart';
import '../widgets/share_sheet.dart';
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

/// What the Local shelf is showing: every book, or one kind of file.
enum _LocalFilter { all, pdf, epub, comics }

extension on _LocalFilter {
  String get label => switch (this) {
    _LocalFilter.all => 'ALL',
    _LocalFilter.pdf => 'PDF',
    _LocalFilter.epub => 'EPUB',
    _LocalFilter.comics => 'COMICS',
  };

  /// `ALL` accepts anything; the others take the formats a reader opens
  /// straight from disk — comics are one bucket because CBZ and CBR are
  /// the same thing wrapped twice.
  bool accepts(FoundBook book) => switch (this) {
    _LocalFilter.all => true,
    _LocalFilter.pdf => book.format == BookFormat.pdf,
    _LocalFilter.epub => book.format == BookFormat.epub,
    _LocalFilter.comics =>
      book.format == BookFormat.cbz || book.format == BookFormat.cbr,
  };
}

/// How the Local shelf is ordered: A→Z, or biggest file first.
enum _LocalSort { name, size }

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

  /// Whether the open page is pinched in. While it is, the page view hands
  /// its swipes over to the page so a thumb can pan the zoom instead.
  bool _zoomed = false;

  /// Bumped to snap every page back to 1:1.
  int _zoomToken = 0;

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

  // ── Local ─────────────────────────────────────────────────────────────
  final TextEditingController _localSearchController = TextEditingController();
  String _localQuery = '';

  /// Which kind of book the shelf is showing, if not all of them.
  _LocalFilter _localFilter = _LocalFilter.all;

  /// How the shelf is ordered.
  _LocalSort _localSort = _LocalSort.name;

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
    // Books another app opens with us arrive here — whether or not one of
    // our own is already open. One frame late, so the reader is built first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OpenFileService.instance.attach(_openSharedFile);
    });
  }

  @override
  void dispose() {
    OpenFileService.instance.detach(_openSharedFile);
    _recordTimer?.cancel();
    _flushProgress();
    final doc = _doc;
    if (doc != null) doc.close();
    _controller?.dispose();
    _veil.dispose();
    _searchController.dispose();
    _localSearchController.dispose();
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

  /// Takes a book another app handed us and opens it in place — the same
  /// road a shelf row or a Library row takes, so it records progress and
  /// shows up in the Library like any other open.
  Future<void> _openSharedFile(String path, {String? title}) =>
      _openFromPath(path, title: title);

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
      _zoomed = false;
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
        _zoomed = false;
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
    // A zoomed page is panned with a thumb, so the page view must stop
    // listening for swipes of its own.
    final physics = _zoomed ? const NeverScrollableScrollPhysics() : null;
    if (doc.format == BookFormat.epub) {
      return PageView.builder(
        controller: _controller,
        physics: physics,
        itemCount: doc.chapters.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) => _zoomedPage(
          _chapterPage(doc.chapters[i]),
          i,
        ),
      );
    }
    return PageView.builder(
      controller: _controller,
      physics: physics,
      itemCount: doc.pageCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) => _zoomedPage(
        doc.format == BookFormat.pdf ? _pdfPage(i) : _imagePage(doc.images[i]),
        i,
      ),
    );
  }

  /// One pinchable page. The key carries the page's own index so the zoom
  /// belongs to that page alone, and the token snaps it back to 1:1 on demand.
  Widget _zoomedPage(Widget page, int index) => _PageZoom(
    key: ValueKey('page-zoom-$index-$_zoomToken'),
    onZoomed: (zoomed) {
      if (!mounted || zoomed == _zoomed) return;
      setState(() => _zoomed = zoomed);
    },
    child: page,
  );

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _zoomed = false;
    });
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
          if (service.allBooks.isNotEmpty || _localQuery.isNotEmpty) ...[
            const SizedBox(height: 16),
            _localSearchField(),
            const SizedBox(height: 12),
            _localControls(),
          ],
          const SizedBox(height: 24),
          if (_localQuery.trim().isEmpty)
            ..._folderSections()
          else
            ..._localMatches(),
          const SizedBox(height: 20),
          ..._formatBlurbs(),
          const SizedBox(height: 16),
          _sharingCard(),
        ],
      ),
    );
  }

  /// Filters the books already found — folders and scan alike — by title or
  /// by path, so a shelf of hundreds stays reachable.
  Widget _localSearchField() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    return TextField(
      key: const ValueKey('local-book-search'),
      controller: _localSearchController,
      onChanged: (value) => setState(() => _localQuery = value),
      style: TextStyle(fontSize: 14, color: cs.onSurface),
      decoration: InputDecoration(
        hintText: 'Search your books…',
        hintStyle: TextStyle(
          fontSize: 14,
          color: cs.onSurface.withAlpha(120),
        ),
        prefixIcon: Icon(Icons.search, size: 20, color: gold),
        suffixIcon: _localQuery.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('local-book-search-clear'),
                icon: Icon(Icons.close, size: 18, color: cs.outline),
                onPressed: () {
                  _localSearchController.clear();
                  setState(() => _localQuery = '');
                },
              ),
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
    );
  }

  /// What the shelf actually renders: the search, the format filter and the
  /// sort order applied to whichever list is on screen.
  List<FoundBook> _localShown(Iterable<FoundBook> books) {
    final query = _localQuery.trim().toLowerCase();
    final shown = [
      for (final book in books)
        if (_localFilter.accepts(book) &&
            (query.isEmpty ||
                book.title.toLowerCase().contains(query) ||
                book.path.toLowerCase().contains(query)))
          book,
    ];
    shown.sort(
      _localSort == _LocalSort.size
          ? (a, b) {
              // Biggest first — that's the question size sorting answers.
              final bySize = b.sizeBytes.compareTo(a.sizeBytes);
              return bySize != 0
                  ? bySize
                  : a.title.toLowerCase().compareTo(b.title.toLowerCase());
            }
          : (a, b) {
              final byName = a.title
                  .toLowerCase()
                  .compareTo(b.title.toLowerCase());
              return byName != 0 ? byName : a.path.compareTo(b.path);
            },
    );
    return shown;
  }

  /// The filter chips and the sort toggle, sitting under the search field.
  Widget _localControls() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in _LocalFilter.values) ...[
                  _filterChip(filter),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          height: 22,
          color: cs.onSurface.withAlpha(40),
        ),
        _sortToggle(_LocalSort.name, 'NAME'),
        const SizedBox(width: 4),
        _sortToggle(_LocalSort.size, 'SIZE'),
      ],
    );
  }

  Widget _filterChip(_LocalFilter filter) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final selected = _localFilter == filter;
    return InkWell(
      key: ValueKey('local-filter-${filter.name}'),
      onTap: () => setState(() => _localFilter = filter),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? gold.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? gold : gold.withAlpha(60)),
        ),
        child: Text(
          filter.label,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w800,
            color: selected ? gold : cs.onSurface.withAlpha(150),
          ),
        ),
      ),
    );
  }

  /// Plain bold text with a gold underline when live — the same language the
  /// tabs speak, so "which order am I in?" reads at a glance.
  Widget _sortToggle(_LocalSort sort, String label) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;
    final active = _localSort == sort;
    return InkWell(
      key: ValueKey('local-sort-${sort.name}'),
      onTap: () => setState(() => _localSort = sort),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: active ? gold : cs.onSurface.withAlpha(140),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 3),
                  Icon(
                    sort == _LocalSort.name
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 10,
                    color: gold,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 34,
              decoration: BoxDecoration(
                color: active ? gold : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hands the open book to the system share dialog — the same sheet the
  /// music player uses, so a book travels the way a song does. The button
  /// only exists inside the viewer, next to who may see it.
  Future<void> _shareOpenBook() async {
    final path = _openPath;
    final title = _doc?.title ?? '';
    if (path.isEmpty || !File(path).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file is no longer on this phone.')),
      );
      return;
    }
    await ShareSheet.show(context, shareText: title, files: [XFile(path)]);
  }

  /// One flat list of matches — grouping by folder stops helping the moment
  /// the question is "which of my books mentions batman?".
  List<Widget> _localMatches() {
    final q = _localQuery.trim().toLowerCase();
    final matches = _localShown(LocalBooksService.instance.allBooks);
    if (matches.isEmpty) {
      final kind = _localFilter == _LocalFilter.all
          ? 'local'
          : _localFilter.label;
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No $kind books match "$q".',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
        ),
      ];
    }
    return [
      _sectionLabel('${matches.length} match${matches.length == 1 ? '' : 'es'}'),
      const SizedBox(height: 6),
      for (final book in matches.take(100)) ...[
        _bookRow(book),
        Divider(
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(30),
        ),
      ],
      if (matches.length > 100)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'Showing 100 of ${matches.length} — keep typing to narrow it down.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
        ),
    ];
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
      final raw = service.byFolder.value[folder] ?? const <FoundBook>[];
      final books = _localShown(raw);
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
        rows.add(
          _hint(
            raw.isEmpty
                ? 'No supported books in this folder yet.'
                : 'No ${_localFilter.label} books in $name.',
          ),
        );
      }
      rows.addAll([
        for (final book in books) _bookRow(book),
        const SizedBox(height: 14),
      ]);
    }

    final scanned = _localShown(service.scanned.value);
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
          service.allBooks.isEmpty
              ? 'Add a folder to keep an eye on, or scan the whole phone once — '
                    'the books you already own show up right here.'
              : 'No ${_localFilter.label} books here yet.',
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
                  const SizedBox(height: 2),
                  Text(
                    book.displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurface.withAlpha(110),
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
                        if (_openPath.isNotEmpty)
                          IconButton(
                            key: const ValueKey('viewer-share'),
                            tooltip: 'Share',
                            icon: const Icon(
                              Icons.ios_share,
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: _shareOpenBook,
                          ),
                        if (_zoomed)
                          IconButton(
                            key: const ValueKey('viewer-zoom-reset'),
                            tooltip: 'Back to 1:1',
                            icon: const Icon(
                              Icons.zoom_out_map,
                              color: Colors.white70,
                              size: 19,
                            ),
                            onPressed: () => setState(() {
                              _zoomToken++;
                              _zoomed = false;
                            }),
                          ),
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
        key: const ValueKey('viewer-privacy'),
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

/// A reader page you can pinch open and drag around once it's bigger than
/// the screen.
///
/// This is [InteractiveViewer]'s job done by hand, because a stock one eats
/// every one-finger flick: its scale recognizer sits nearer the page than the
/// page view's own, and in a gesture arena the first recognizer to accept
/// wins — so a fast swipe would silently stop turning pages. Here the
/// recognizer claims nothing until either two fingers are down (a pinch) or
/// the page is already zoomed (a drag to look around), and every ordinary
/// flick is left to the page view.
class _PageZoom extends StatefulWidget {
  const _PageZoom({super.key, required this.onZoomed, required this.child});

  /// Reports the moment the page leaves 1:1 — or snaps back to it.
  final ValueChanged<bool> onZoomed;

  final Widget child;

  @override
  State<_PageZoom> createState() => _PageZoomState();
}

class _PageZoomState extends State<_PageZoom> {
  /// Drawn as `offset + scale * scene`: a point `scene` into the page lands
  /// on `offset + scale * scene` inside the page box. The offset is then
  /// clamped to `[box * (1 - scale), 0]`, which keeps the page covering the
  /// box exactly at 1:1 and never leaves a gap at any other size.
  double _scale = 1;
  Offset _offset = Offset.zero;

  /// The pinch under way, re-captured whenever a finger joins or leaves:
  /// the recognizer re-anchors then, so its reported scale starts over at 1.
  double _scaleStart = 1;
  Offset _offsetStart = Offset.zero;
  Offset _focalStart = Offset.zero;

  Size _box = Size.zero;
  _ZoomRecognizer? _recognizer;

  late final Map<Type, GestureRecognizerFactory> _gestures =
      <Type, GestureRecognizerFactory>{
        _ZoomRecognizer: GestureRecognizerFactoryWithHandlers<_ZoomRecognizer>(
          () {
            final recognizer = _ZoomRecognizer(_claims);
            _recognizer = recognizer;
            return recognizer;
          },
          (recognizer) => recognizer
            ..onStart = _onStart
            ..onUpdate = _onUpdate,
        ),
      };

  /// Two fingers always mean pinch; one finger is only ours once zoomed, so
  /// every ordinary flick keeps going to the page view.
  bool _claims() => _scale > 1 || (_recognizer?.pointerCount ?? 0) > 1;

  void _onStart(ScaleStartDetails details) {
    _scaleStart = _scale;
    _offsetStart = _offset;
    _focalStart = details.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails details) {
    if (!mounted) return;
    // Only a pinch changes the size; a lone finger just drags it about.
    double scale = (_recognizer?.pointerCount ?? 1) > 1
        ? (_scaleStart * details.scale).clamp(1.0, 5.0).toDouble()
        : _scaleStart;
    // Anything barely off 1:1 is 1:1 — otherwise a slow pinch-out could park
    // just above the line and leave the page view unable to take a swipe.
    if (scale < 1.01) scale = 1;

    // The point on the page that sat under the pinch when it began.
    final Offset scene = Offset(
      (_focalStart.dx - _offsetStart.dx) / _scaleStart,
      (_focalStart.dy - _offsetStart.dy) / _scaleStart,
    );
    // Keep that point under the moving fingers, inside the box.
    final Offset focal = details.localFocalPoint;
    final Offset offset = Offset(
      (focal.dx - scale * scene.dx)
          .clamp(_box.width * (1 - scale), 0.0)
          .toDouble(),
      (focal.dy - scale * scene.dy)
          .clamp(_box.height * (1 - scale), 0.0)
          .toDouble(),
    );
    final bool zoomed = scale > 1;
    setState(() {
      _scale = scale;
      _offset = offset;
    });
    widget.onZoomed(zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _box = constraints.biggest;
        return ClipRect(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: _gestures,
            child: Transform(
              alignment: Alignment.topLeft,
              transform: Matrix4.identity()
                ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                ..scaleByDouble(_scale, _scale, _scale, 1),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// A [ScaleGestureRecognizer] that sits out the gesture arena until
/// [canClaim] says a pinch — or a drag on an already zoomed page — is its
/// own, and otherwise lets the page view have it.
///
/// While it is not claiming, it ignores move events entirely rather than
/// accepting and swallowing them: that way it never wins a flick it would
/// only hold on to, and on pointer-up it still rejects itself cleanly, so
/// taps keep reaching the page.
class _ZoomRecognizer extends ScaleGestureRecognizer {
  _ZoomRecognizer(this.canClaim);

  final bool Function() canClaim;

  @override
  void handleEvent(PointerEvent event) {
    final bool move =
        event is PointerMoveEvent || event is PointerPanZoomUpdateEvent;
    if (move && !canClaim()) return;
    super.handleEvent(event);
    // Two moving fingers mean pinch, and they mean it sooner than the
    // recognizer's own thresholds allow. The page view's drag only needs one
    // thumb's 18 pixels, while the pinch's span shows half of each finger's
    // travel — so without this the drag would take the page mid-pinch.
    if (move && pointerCount > 1) resolve(GestureDisposition.accepted);
  }
}
