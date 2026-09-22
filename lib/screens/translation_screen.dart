import 'package:flutter/material.dart';
import '../services/translation_service.dart';

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final _inputCtrl = TextEditingController();
  final _outputCtrl = TextEditingController();

  String _fromScript = 'latin';
  String _toScript = 'tifinagh';
  bool _loading = false;
  bool _isWordLookup = false;

  final _scripts = [
    ('latin', 'Latin', Icons.abc),
    ('tifinagh', 'Tifinagh', Icons.g_translate_outlined),
    ('arabic', 'Arabic', Icons.translate),
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    super.dispose();
  }

  void _swap() {
    setState(() {
      final temp = _fromScript;
      _fromScript = _toScript;
      _toScript = temp;
      _outputCtrl.clear();
    });
    if (_inputCtrl.text.isNotEmpty) _doTranslate();
  }

  Future<void> _doTranslate() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() { _loading = true; _outputCtrl.clear(); });

    String result;
    if (_isWordLookup) {
      final entries = await TranslationService.lookupWord(text, from: _fromScript);
      if (entries.isNotEmpty) {
        result = entries.map((e) {
          final parts = <String>[];
          if (e.word.isNotEmpty) parts.add('Tifinagh: ${e.word}');
          if (e.pronunciation.isNotEmpty) parts.add('(${e.pronunciation})');
          if (e.arabic.isNotEmpty) parts.add('Arabic: ${e.arabic}');
          if (e.english.isNotEmpty) parts.add('English: ${e.english}');
          return parts.join('\n');
        }).join('\n\n');
      } else {
        result = 'No results found for "$text"';
      }
    } else if (_fromScript == 'tifinagh' || _toScript == 'tifinagh') {
      result = await TranslationService.transliterate(text, from: _fromScript, to: _toScript);
    } else {
      result = await TranslationService.translateGoogle(text, from: _fromScript == 'arabic' ? 'ar' : 'en', to: _toScript == 'arabic' ? 'ar' : 'en');
    }

    if (mounted) setState(() { _outputCtrl.text = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tamazight Translator'),
        actions: [
          IconButton(
            icon: Icon(_isWordLookup ? Icons.menu_book : Icons.swap_horiz, size: 22),
            tooltip: _isWordLookup ? 'Transliterate' : 'Dictionary lookup',
            onPressed: () => setState(() {
              _isWordLookup = !_isWordLookup;
              _outputCtrl.clear();
            }),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _scriptSelector(_fromScript, cs, isFrom: true),
                IconButton(
                  onPressed: _swap,
                  icon: Icon(Icons.swap_horiz, color: cs.primary, size: 24),
                ),
                _scriptSelector(_toScript, cs, isFrom: false),
              ],
            ),
            const SizedBox(height: 12),
            if (_isWordLookup)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Dictionary lookup mode', style: TextStyle(fontSize: 11, color: cs.primary)),
                ]),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: _fromScript == 'tifinagh'
                            ? 'Type in Tifinagh...'
                            : _fromScript == 'arabic'
                                ? 'اكتب بالعربية...'
                                : 'Type in English...',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withAlpha(60),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      style: TextStyle(fontSize: 16, color: cs.onSurface),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _doTranslate,
                      icon: _loading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                          : const Icon(Icons.translate, size: 18),
                      label: Text(_isWordLookup ? 'Look Up' : 'Translate'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _loading
                          ? Center(child: CircularProgressIndicator(color: cs.primary))
                          : SelectableText(
                              _outputCtrl.text.isEmpty ? 'Translation will appear here...' : _outputCtrl.text,
                              style: TextStyle(
                                fontSize: 16,
                                color: _outputCtrl.text.isEmpty ? cs.onSurface.withAlpha(80) : cs.onSurface,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scriptSelector(String current, ColorScheme cs, {required bool isFrom}) {
    return Expanded(
      child: PopupMenuButton<String>(
        onSelected: (v) => setState(() {
          if (isFrom) { _fromScript = v; } else { _toScript = v; }
          _outputCtrl.clear();
        }),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(100),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_scripts.firstWhere((s) => s.$1 == current).$3, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Flexible(child: Text(_scripts.firstWhere((s) => s.$1 == current).$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        itemBuilder: (_) => _scripts
            .where((s) => s.$1 != (isFrom ? _toScript : _fromScript))
            .map((s) => PopupMenuItem(value: s.$1, child: Row(children: [Icon(s.$3, size: 18), const SizedBox(width: 10), Text(s.$2)])))
            .toList(),
      ),
    );
  }
}
