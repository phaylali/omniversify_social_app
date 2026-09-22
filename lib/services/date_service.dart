import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';

class DateService {
  DateService._();

  static final _base = ApiConfig.moroccoDateApiUrl;

  static Future<TripleDate> fetchToday() async {
    final resp = await http.get(Uri.parse('$_base/date'));
    if (resp.statusCode != 200) throw Exception('Failed to fetch date');
    return TripleDate.fromJson(jsonDecode(resp.body));
  }
}

class TripleDate {
  final CalendarDate gregorian;
  final CalendarDate islamic;
  final CalendarDate amazigh;

  const TripleDate({required this.gregorian, required this.islamic, required this.amazigh});

  factory TripleDate.fromJson(Map<String, dynamic> json) => TripleDate(
        gregorian: CalendarDate.fromJson(json['gregorian']),
        islamic: CalendarDate.fromJson(json['islamic']),
        amazigh: CalendarDate.fromJson(json['amazigh']),
      );
}

class CalendarDate {
  final int year;
  final int day;
  final MonthMonth month;

  const CalendarDate({required this.year, required this.month, required this.day});

  factory CalendarDate.fromJson(Map<String, dynamic> json) => CalendarDate(
        year: json['year'],
        day: json['day'],
        month: MonthMonth.fromJson(json['month']),
      );

  String get display => '$day ${month.latin} $year';
}

class MonthMonth {
  final int order;
  final String latin;
  final String tifinagh;
  final String arabic;

  const MonthMonth({required this.order, required this.latin, required this.tifinagh, required this.arabic});

  factory MonthMonth.fromJson(Map<String, dynamic> json) => MonthMonth(
        order: json['order'],
        latin: json['latin'],
        tifinagh: json['tifinagh'],
        arabic: json['arabic'],
      );
}
