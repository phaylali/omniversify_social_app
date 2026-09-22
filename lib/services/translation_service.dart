import 'dart:convert';
import 'package:http/http.dart' as http;

class TranslationService {
  TranslationService._();

  static const _tifinaghBase = 'https://omniversify-tifinagh-dictionary-api.omniversify.com';
  static const _googleBase = 'https://translate.googleapis.com/translate_a/single';

  static Future<String> transliterate(String text, {required String from, required String to}) async {
    if (text.trim().isEmpty) return text;
    try {
      final resp = await http.post(
        Uri.parse('$_tifinaghBase/retype'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'from': from, 'to': to}),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['output']['text'] ?? text;
      }
    } catch (_) {}
    return text;
  }

  static Future<List<TifinaghEntry>> lookupWord(String word, {String? from}) async {
    if (word.trim().isEmpty) return [];
    try {
      final body = <String, dynamic>{'text': word};
      if (from != null) body['from'] = from;
      final resp = await http.post(
        Uri.parse('$_tifinaghBase/translate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final results = data['results'] as List<dynamic>? ?? [];
        return results.map((e) => TifinaghEntry.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<String> translateGoogle(String text, {required String from, required String to}) async {
    if (text.trim().isEmpty) return text;
    try {
      final resp = await http.get(Uri.parse(
        '$_googleBase?client=gtx&sl=$from&tl=$to&dt=t&q=${Uri.encodeComponent(text)}',
      )).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final sentences = data[0] as List<dynamic>? ?? [];
        return sentences.map((s) => s[0] ?? '').join('');
      }
    } catch (_) {}
    return text;
  }
}

class TifinaghEntry {
  final String word;
  final String pronunciation;
  final String arabic;
  final String english;

  const TifinaghEntry({required this.word, required this.pronunciation, required this.arabic, required this.english});

  factory TifinaghEntry.fromJson(Map<String, dynamic> json) => TifinaghEntry(
        word: json['word'] ?? '',
        pronunciation: json['pronunciation'] ?? '',
        arabic: json['arabic'] ?? '',
        english: json['english'] ?? '',
      );
}
