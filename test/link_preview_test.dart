import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:omniversify_social_app/services/link_preview_service.dart';
import 'package:omniversify_social_app/widgets/link_preview_widget.dart';

const _youtubeOembed =
    '{"title":"A quiet room, no talking","author_name":"Field Notes"}';

const _instagramHtml = '<html><head>'
    '<meta property="og:title" content="Reel of the green lanterns">'
    '<meta property="og:description" content="From last night">'
    '<meta property="og:image" content="https://cdn.example.com/reel.jpg">'
    '</head><body>log in to see more</body></html>';

Future<http.Response> _fake(http.Request request) async {
  final url = request.url.toString();
  if (url.contains('youtube.com/oembed')) {
    return http.Response(
      _youtubeOembed,
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  if (url.contains('instagram.com')) return http.Response(_instagramHtml, 200);
  return http.Response('nothing here', 404);
}

/// The picture currently on show in the preview.
NetworkImage _picture(WidgetTester tester) {
  final image = tester.widget<Image>(find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url.contains('default.jpg'),
  ));
  return image.image as NetworkImage;
}

void main() {
  late http.Client original;

  setUp(() {
    original = LinkPreviewService.client;
    LinkPreviewService.client = MockClient(_fake);
  });

  tearDown(() => LinkPreviewService.client = original);

  test('a YouTube link keeps its frame, and a smaller one to fall back on',
      () async {
    final data = await LinkPreviewService.fetchPreview(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ');

    expect(data, isNotNull);
    expect(data!.title, 'A quiet room, no talking');
    expect(data.imageUrl, contains('maxresdefault.jpg'));
    expect(data.fallbackImageUrl, contains('hqdefault.jpg'));
  });

  test('a link with words around it still previews the link', () async {
    final urls = LinkPreviewService.extractUrls(
        'look at this https://www.instagram.com/reel/AbCdEf12345/ please');
    final data = await LinkPreviewService.fetchPreview(urls.single);

    expect(data, isNotNull);
    expect(data!.title, 'Reel of the green lanterns');
    expect(data.platform, 'instagram');
  });

  testWidgets('a link swapped for another wears the other one’s metadata',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LinkPreviewWidget(
            url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('A quiet room, no talking'), findsOneWidget);

    // The composer keeps its state while the text under it changes — which
    // is how an Instagram reel once ended up wearing YouTube's title.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LinkPreviewWidget(
            url: 'https://www.instagram.com/reel/AbCdEf12345/'),
      ),
    ));
    await tester.pump();
    expect(find.text('A quiet room, no talking'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Reel of the green lanterns'), findsOneWidget);
    expect(find.text('A quiet room, no talking'), findsNothing);
  });

  testWidgets('the big frame turns up missing, so the small one takes over',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LinkPreviewWidget(
            url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_picture(tester).url, contains('maxresdefault.jpg'));

    // The test harness refuses every network image, so the error path runs
    // and the fallback is asked for instead.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_picture(tester).url, contains('hqdefault.jpg'));
  });
}
