import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One book the Discover tab found.
class DiscoverItem {
  const DiscoverItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.meta = '',
  });

  /// The source's own identifier for the item.
  final String id;
  final String title;
  final String coverUrl;

  /// Small line under the title — a year, a collection, whatever the source
  /// can offer without a second request.
  final String meta;
}

/// The specific file inside an item that is worth downloading.
class DiscoverFile {
  const DiscoverFile({
    required this.url,
    required this.name,
    required this.format,
    required this.sizeBytes,
    required this.extension,
  });

  final String url;
  final String name;
  final String format;
  final int sizeBytes;

  /// What we save it as: `cbr`, `epub`, `pdf`…
  final String extension;
}

/// Where Discover looks for books.
///
/// Everything the reader needs from a source is expressed here, so another
/// source is one class + one line in the registry — the tabs don't change.
abstract class DiscoverSource {
  /// Stable id, used in storage and keys.
  String get id;

  /// Shown on the source chip.
  String get name;

  /// The source's best page of results for [query].
  Future<List<DiscoverItem>> search(String query, {int page = 1});

  /// Which file inside [item] a reader should open, or null when the item
  /// holds nothing our formats can read.
  Future<DiscoverFile?> resolve(DiscoverItem item);

  /// Downloads [file] to [destination], reporting 0..1 (or -1 when the
  /// server won't say how big it is). Returns the saved path.
  Future<String> download(
    DiscoverFile file,
    String destination, {
    void Function(double progress)? onProgress,
  });
}

/// Books and comics from the Internet Archive's open search API.
///
/// Search is its `advancedsearch` endpoint, covers come from
/// `/services/img/`, and the file itself from `/download/` — no key, no
/// tracking, no third-party shim.
class InternetArchiveSource implements DiscoverSource {
  const InternetArchiveSource();

  static const String baseUrl = 'https://archive.org';

  @override
  String get id => 'internet_archive';

  @override
  String get name => 'Internet Archive';

  /// Formats our reader opens, best first.
  ///
  /// Comic archives come before the PDF of the same scan because they are
  /// the comic as it was issued; the PDF is the fallback when there is no
  /// archive at all.
  static const List<String> formatPreference = [
    'Comic Book RAR',
    'Zip',
    'Single Page Processed ZIP',
    'Image Container PDF',
    'Text PDF',
    'PDF',
    'EPUB',
  ];

  @override
  Future<List<DiscoverItem>> search(String query, {int page = 1}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.parse(
      '$baseUrl/advancedsearch.php'
      '?q=${Uri.encodeQueryComponent(searchQuery(trimmed))}'
      '&fl[]=identifier&fl[]=title&fl[]=year'
      '&sort[]=downloads desc'
      '&rows=24&page=$page'
      '&output=json',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw const FormatException('search failed');
    }
    return parseSearch(response.body);
  }

  /// The Archive's query language: a title match, restricted to items that
  /// are documents — its image collections are mostly loose GIFs and photos.
  static String searchQuery(String query) =>
      'title:($query) AND mediatype:(texts)';

  /// Pure parsing of an `advancedsearch` response — tested offline.
  static List<DiscoverItem> parseSearch(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) return const [];
    final response = decoded['response'];
    if (response is! Map<String, Object?>) return const [];
    final docs = response['docs'];
    if (docs is! List) return const [];

    final items = <DiscoverItem>[];
    for (final doc in docs) {
      if (doc is! Map) continue;
      final id = doc['identifier'];
      if (id is! String || id.isEmpty) continue;
      final rawTitle = doc['title'];
      final title = switch (rawTitle) {
        String value when value.trim().isNotEmpty => value.trim(),
        List value when value.isNotEmpty && value.first is String =>
          (value.first as String).trim(),
        _ => id,
      };
      final year = doc['year'];
      items.add(
        DiscoverItem(
          id: id,
          title: title,
          coverUrl: coverUrlFor(id),
          meta: switch (year) {
            String value => value,
            num value => value.toInt().toString(),
            _ => '',
          },
        ),
      );
    }
    return items;
  }

  /// The Archive's built-in thumbnail for an item.
  static String coverUrlFor(String id) => '$baseUrl/services/img/$id';

  @override
  Future<DiscoverFile?> resolve(DiscoverItem item) async {
    final uri = Uri.parse('$baseUrl/metadata/${item.id}');
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) return null;
    return pickFile(response.body, item.id);
  }

  /// Pure choice of file from an `/metadata/` response — tested offline.
  ///
  /// Returns null when the item holds no format the reader can open, which
  /// is a real answer ("that one is just text files"), not an error.
  static DiscoverFile? pickFile(String body, String id) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) return null;
    final server = decoded['server'];
    final dir = decoded['dir'];
    final files = decoded['files'];
    if (files is! List) return null;

    final candidates = <int, List<Map<String, Object?>>>{};
    for (final file in files) {
      if (file is! Map) continue;
      final map = Map<String, Object?>.from(file);
      final format = map['format'];
      if (format is! String) continue;
      final name = map['name'];
      if (name is! String || name.isEmpty) continue;
      final rank = formatPreference.indexOf(format);
      if (rank < 0) continue;
      candidates.putIfAbsent(rank, () => []).add(map);
    }
    if (candidates.isEmpty) return null;

    final best = candidates.keys.reduce((a, b) => a < b ? a : b);
    final chosen = candidates[best]!.first;
    final name = chosen['name'] as String;
    final format = chosen['format'] as String;
    final size = int.tryParse('${chosen['size'] ?? 0}') ?? 0;

    // The Archive hands out every file from its own node, so the plain
    // download URL is enough — it redirects to whichever node has it. The
    // name keeps any folders it came in, encoded one segment at a time.
    final path = name
        .split('/')
        .map((segment) => Uri.encodeComponent(segment))
        .join('/');
    final url = (server is String && server.isNotEmpty && dir is String)
        ? 'https://$server$dir/$path'
        : '$baseUrl/download/$id/$path';

    return DiscoverFile(
      url: url,
      name: name.split('/').last,
      format: format,
      sizeBytes: size,
      extension: extensionFor(name, format),
    );
  }

  /// The file extension we save under — from the name when it has one,
  /// otherwise from the format label.
  static String extensionFor(String name, String format) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      final ext = name.substring(dot + 1).toLowerCase();
      if (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return ext;
    }
    return switch (format) {
      'Comic Book RAR' => 'cbr',
      'Zip' || 'Single Page Processed ZIP' => 'cbz',
      'EPUB' => 'epub',
      _ => 'pdf',
    };
  }

  @override
  Future<String> download(
    DiscoverFile file,
    String destination, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(file.url));
      request.followRedirects = true;
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw FormatException('download failed (${response.statusCode})');
      }

      final total = response.contentLength ?? -1;
      var received = 0;
      final sink = File(destination).openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(total > 0 ? received / total : -1);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return destination;
    } finally {
      client.close();
    }
  }
}
