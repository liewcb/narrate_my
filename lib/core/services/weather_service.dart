import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../model/entities/weather.dart';

class WeatherService {
  Future<WeatherForecast> getDailyForecast({
    required double latitude,
    required double longitude,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = _formatDate(startDate);
    final end = _formatDate(endDate);

    final url = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'daily': 'temperature_2m_max,temperature_2m_min,weathercode',
        'timezone': 'Asia/Kuala_Lumpur',
        'start_date': start,
        'end_date': end,
      },
    );

    try {
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('HTTP error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final daily = data['daily'];
      if (daily == null) throw Exception('Missing "daily" in response');

      final dates = daily['time'] as List? ?? [];
      final maxTemps = daily['temperature_2m_max'] as List? ?? [];
      final minTemps = daily['temperature_2m_min'] as List? ?? [];
      final weatherCodes = daily['weathercode'] as List? ?? [];

      final List<DailyWeather> dailyWeather = [];
      for (int i = 0; i < dates.length; i++) {
        final date = DateTime.parse(dates[i]);
        final condition = _mapWeatherCode(weatherCodes[i] as int?);
        final maxTemp = maxTemps[i] as num?;
        final minTemp = minTemps[i] as num?;

        dailyWeather.add(DailyWeather(
          date: date,
          condition: condition,
          maxTemperature: maxTemp?.toDouble() ?? 0.0,
          minTemperature: minTemp?.toDouble() ?? 0.0,
        ));
      }

      return WeatherForecast(daily: dailyWeather);
    } catch (e) {
      throw Exception('Failed to load weather data: $e');
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _mapWeatherCode(int? code) {
    if (code == null) return '🌤️ Data unavailable';
    switch (code) {
      case 0: return '☀️ Clear sky';
      case 1: case 2: case 3: return '⛅ Partly cloudy';
      case 45: case 48: return '🌫️ Fog';
      case 51: case 53: case 55: return '🌧️ Light drizzle';
      case 61: case 63: case 65: return '🌧️ Rain';
      case 71: case 73: case 75: return '❄️ Snow';
      case 80: case 81: case 82: return '🌧️ Rain showers';
      case 95: case 96: case 99: return '⛈️ Thunderstorm';
      default: return '🌤️ Mixed';
    }
  }
}