import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  WeatherService._();

  static const _forecastBase = 'https://api.open-meteo.com/v1/forecast';
  static const _geoBase = 'https://geocoding-api.open-meteo.com/v1/search';

  static Future<List<GeoLocation>> searchLocation(String query) async {
    final resp = await http.get(Uri.parse('$_geoBase?name=${Uri.encodeComponent(query)}&count=5&language=en'));
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body);
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => GeoLocation.fromJson(e)).toList();
  }

  static Future<WeatherData> fetchWeather(double lat, double lon) async {
    final params = [
      'latitude=$lat',
      'longitude=$lon',
      'current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m',
      'daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone=auto',
      'forecast_days=7',
    ].join('&');

    final resp = await http.get(Uri.parse('$_forecastBase?$params'));
    if (resp.statusCode != 200) throw Exception('Weather fetch failed');
    return WeatherData.fromJson(jsonDecode(resp.body));
  }
}

class GeoLocation {
  final String name;
  final String country;
  final String? admin1;
  final double lat;
  final double lon;

  const GeoLocation({required this.name, required this.country, this.admin1, required this.lat, required this.lon});

  factory GeoLocation.fromJson(Map<String, dynamic> json) => GeoLocation(
        name: json['name'] ?? '',
        country: json['country'] ?? '',
        admin1: json['admin1'],
        lat: (json['latitude'] as num).toDouble(),
        lon: (json['longitude'] as num).toDouble(),
      );

  String get displayName => admin1 != null ? '$name, $admin1' : '$name, $country';
}

class WeatherData {
  final CurrentWeather current;
  final List<DailyForecast> daily;

  const WeatherData({required this.current, required this.daily});

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;
    final length = (daily['time'] as List).length;
    final forecasts = List.generate(length, (i) => DailyForecast(
          date: daily['time'][i],
          code: daily['weather_code'][i],
          maxTemp: (daily['temperature_2m_max'][i] as num).toDouble(),
          minTemp: (daily['temperature_2m_min'][i] as num).toDouble(),
          precipProb: daily['precipitation_probability_max'][i] ?? 0,
        ));
    return WeatherData(
      current: CurrentWeather(
        temp: (current['temperature_2m'] as num).toDouble(),
        feelsLike: (current['apparent_temperature'] as num).toDouble(),
        humidity: current['relative_humidity_2m'],
        code: current['weather_code'],
        windSpeed: (current['wind_speed_10m'] as num).toDouble(),
        windDir: (current['wind_direction_10m'] as num).toDouble(),
      ),
      daily: forecasts,
    );
  }
}

class CurrentWeather {
  final double temp;
  final double feelsLike;
  final int humidity;
  final int code;
  final double windSpeed;
  final double windDir;

  const CurrentWeather({required this.temp, required this.feelsLike, required this.humidity, required this.code, required this.windSpeed, required this.windDir});

  String get description => _weatherDescription(code);
  String get icon => _weatherIcon(code);
}

class DailyForecast {
  final String date;
  final int code;
  final double maxTemp;
  final double minTemp;
  final int precipProb;

  const DailyForecast({required this.date, required this.code, required this.maxTemp, required this.minTemp, required this.precipProb});

  String get dayName {
    final d = DateTime.parse(date);
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[d.weekday % 7];
  }

  String get icon => _weatherIcon(code);
  String get description => _weatherDescription(code);
}

String _weatherIcon(int code) {
  if (code <= 1) return '☀️';
  if (code <= 3) return '⛅';
  if (code <= 49) return '🌫️';
  if (code <= 59) return '🌧️';
  if (code <= 69) return '🌨️';
  if (code <= 79) return '❄️';
  if (code <= 82) return '🌧️';
  if (code <= 86) return '🌨️';
  if (code <= 99) return '⛈️';
  return '🌤️';
}

String _weatherDescription(int code) {
  const descriptions = {
    0: 'Clear sky', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast',
    45: 'Fog', 48: 'Rime fog',
    51: 'Light drizzle', 53: 'Moderate drizzle', 55: 'Dense drizzle',
    56: 'Freezing drizzle', 57: 'Dense freezing drizzle',
    61: 'Slight rain', 63: 'Moderate rain', 65: 'Heavy rain',
    66: 'Freezing rain', 67: 'Heavy freezing rain',
    71: 'Slight snow', 73: 'Moderate snow', 75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Slight rain showers', 81: 'Moderate rain showers', 82: 'Violent rain showers',
    85: 'Slight snow showers', 86: 'Heavy snow showers',
    95: 'Thunderstorm', 96: 'Thunderstorm with hail', 99: 'Severe thunderstorm',
  };
  return descriptions[code] ?? 'Unknown';
}
