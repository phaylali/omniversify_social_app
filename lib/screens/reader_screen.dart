import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../services/activity_service.dart';
import '../services/book_loader.dart';
import '../services/privacy_service.dart';
import '../widgets/action_sheet.dart';
import 'privacy_screen.dart';

/// The books & comics tool: open a local PDF, EPUB, CBZ or CBR and read it
/// here.
///
/// Whatever book is open is reported to [ActivityService], so the
/// Acquaintances tab can show it — exactly as far as the Privacy setting
/// allows.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  BookDocument? _doc;
  bool _loading = false;

  /// Tap the page to hide/show the bars.
  bool _chrome = true;

  int _index = 0;
  PageController? _controller;

  /// Rendered PDF pages: the future once (so rebuilds don't re-render) and
  /// the finished bitmap for a small LRU of recent pages.
  final Map<int, Future<Uint8List?>> _pageFutures = {};
  final Map<int, Uint8List> _pageCache = {};

  @override
  void dispose() {
    final doc = _doc;
    if (doc != null) doc.close();
    _controller?.dispose();
    ActivityService.instance.reading.value = null;
    super.dispose();
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

      final doc = await BookLoader.open(bytes, file.name);
      await _closeDocument();
      _controller?.dispose();
      _controller = PageController();
      _pageFutures.clear();
      _pageCache.clear();
      ActivityService.instance.reading.value = doc.title;
      if (!mounted) {
        doc.close();
        return;
      }
      setState(() {
        _doc = doc;
        _index = 0;
        _loading = false;
        _chrome = true;
      });
      showActionNotice(context, 'Opened "${doc.title}"');
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

  /// Back to the landing page — the book stops being shared too.
  Future<void> _closeDocument() async {
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
      });
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
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _chapterPage(doc.chapters[i]),
      );
    }
    return PageView.builder(
      controller: _controller,
      itemCount: doc.pageCount,
      onPageChanged: (i) => setState(() => _index = i),
      itemBuilder: (context, i) => doc.format == BookFormat.pdf
          ? _pdfPage(i)
          : _imagePage(doc.images[i]),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) return _landing();
    return _viewer(doc);
  }

  Widget _landing() {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withAlpha(25),
                border: Border.all(color: gold.withAlpha(90)),
              ),
              child: Icon(Icons.menu_book_outlined, size: 42, color: gold),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Read something',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Open a book or comic straight from your device — nothing '
            'leaves your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onSurface.withAlpha(170),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _pick,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: cs.onPrimary,
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
          const SizedBox(height: 26),
          for (final format in BookFormat.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: gold.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: gold.withAlpha(70)),
                    ),
                    child: Text(
                      format.label,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    format.blurb,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withAlpha(170),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          ValueListenableBuilder<ShareAudience>(
            valueListenable: PrivacyService.instance.audience,
            builder: (context, audience, _) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
              ),
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
          ),
        ],
      ),
    );
  }

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
