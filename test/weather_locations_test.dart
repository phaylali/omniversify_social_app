import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omniversify_social_app/screens/weather_screen.dart';
import 'package:omniversify_social_app/services/weather_locations.dart';
import 'package:omniversify_social_app/services/weather_service.dart';

GeoLocation _place(String name, double lat) => GeoLocation(
      name: name,
      country: 'Morocco',
      lat: lat,
      lon: lat,
    );

/// A visit that leaves no current place behind, so opening the screen never
/// reaches for the network.
Future<void> _seedHistory(GeoLocation loc) async {
  await WeatherLocations.instance.record(loc);
  WeatherLocations.instance.current.value = null;
}

Future<void> _pumpWeather(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: WeatherScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openLocationsTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tab-Locations')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeatherLocations.instance.reset();
  });

  group('weather locations', () {
    test('a visit becomes the current place and tops the history', () async {
      final tetouan = _place('Tetouan', 35.58);
      final zenica = _place('Zenica', 39.28);

      await WeatherLocations.instance.record(tetouan);
      await WeatherLocations.instance.record(zenica);

      expect(WeatherLocations.instance.current.value?.name, 'Zenica');
      expect(
        WeatherLocations.instance.history.value.map((l) => l.name),
        ['Zenica', 'Tetouan'],
      );

      // Going back to an older place pulls it to the front, once.
      await WeatherLocations.instance.record(tetouan);
      expect(
        WeatherLocations.instance.history.value.map((l) => l.name),
        ['Tetouan', 'Zenica'],
      );
    });

    test('starring takes a place out of the history and back', () async {
      final tetouan = _place('Tetouan', 35.58);
      await _seedHistory(tetouan);
      expect(WeatherLocations.instance.isStarred(tetouan), isFalse);

      await WeatherLocations.instance.toggleStar(tetouan);
      expect(WeatherLocations.instance.isStarred(tetouan), isTrue);
      expect(WeatherLocations.instance.history.value, isEmpty);

      // A starred place stays out of the history no matter how often you go.
      await WeatherLocations.instance.record(tetouan);
      expect(WeatherLocations.instance.history.value, isEmpty);
      expect(WeatherLocations.instance.current.value?.name, 'Tetouan');

      await WeatherLocations.instance.toggleStar(tetouan);
      expect(WeatherLocations.instance.isStarred(tetouan), isFalse);
      expect(
        WeatherLocations.instance.history.value.map((l) => l.name),
        ['Tetouan'],
      );
    });

    test('the history keeps the last ten visits', () async {
      for (var i = 0; i < 13; i++) {
        await WeatherLocations.instance.record(_place('City $i', i.toDouble()));
      }

      final names = WeatherLocations.instance.history.value
          .map((l) => l.name)
          .toList();
      expect(names, hasLength(WeatherLocations.maxHistory));
      expect(names.first, 'City 12');
      expect(names, isNot(contains('City 2')));
      expect(names, contains('City 3'));
    });

    test('the three lists survive a restart', () async {
      await WeatherLocations.instance.record(_place('Tetouan', 35.58));
      await WeatherLocations.instance.toggleStar(_place('Zenica', 39.28));

      WeatherLocations.instance.reset();
      await WeatherLocations.instance.load();

      expect(WeatherLocations.instance.current.value?.name, 'Tetouan');
      expect(
        WeatherLocations.instance.starred.value.map((l) => l.name),
        ['Zenica'],
      );
      expect(
        WeatherLocations.instance.history.value.map((l) => l.name),
        ['Tetouan'],
      );
    });
  });

  group('weather screen', () {
    testWidgets('opens on Current with a search box', (tester) async {
      await _pumpWeather(tester);

      expect(find.byKey(const ValueKey('tab-Current')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-Locations')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search for a location'), findsOneWidget);
    });

    testWidgets('the Locations tab lists starred places before the rest',
        (tester) async {
      await _seedHistory(_place('Zenica', 39.28));
      await WeatherLocations.instance.toggleStar(_place('Tetouan', 35.58));

      await _pumpWeather(tester);
      await _openLocationsTab(tester);

      expect(find.text('STARRED'), findsOneWidget);
      expect(find.text('RECENT'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('weather-row-Tetouan')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('weather-row-Zenica')))
              .dy,
        ),
      );
    });

    testWidgets('starring a recent place moves it up into Starred',
        (tester) async {
      await _seedHistory(_place('Zenica', 39.28));

      await _pumpWeather(tester);
      await _openLocationsTab(tester);

      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('STARRED'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('weather-star-Zenica')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('STARRED'), findsOneWidget);
      expect(find.text('RECENT'), findsNothing);
      expect(WeatherLocations.instance.isStarred(_place('Zenica', 39.28)),
          isTrue);
      expect(WeatherLocations.instance.history.value, isEmpty);
    });

    testWidgets('the empty Locations tab invites you to star a place',
        (tester) async {
      await _pumpWeather(tester);
      await _openLocationsTab(tester);

      expect(find.text('Star a place and it waits here'), findsOneWidget);
      expect(find.text('STARRED'), findsNothing);
    });
  });
}
