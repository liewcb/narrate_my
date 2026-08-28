import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../model/entities/weather.dart';

class WeatherService {
  /// Fetches daily forecast.
  /// Tier 1: Open-Meteo (free, 16 days) → Tier 2: yr.no/MET Norway (free, 9 days)
  Future<WeatherForecast> getDailyForecast({
    required double latitude,
    required double longitude,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // ━━━ Tier 1: Open-Meteo (FREE, 16 days, global) ━━━
    try {
      final openMeteoResult = await _getOpenMeteoForecast(
        latitude: latitude,
        longitude: longitude,
        startDate: startDate,
        endDate: endDate,
      );

      if (openMeteoResult.daily.isNotEmpty) {
        debugPrint(
          '☀️ [WeatherService] Open-Meteo OK — '
              '${openMeteoResult.daily.length} days loaded',
        );
        return openMeteoResult;
      }
    } catch (e) {
      debugPrint('⚠️ [WeatherService] Open-Meteo failed: $e');
    }

    // ━━━ Tier 2: yr.no / MET Norway (FREE, 9 days, no key) ━━━
    try {
      final yrResult = await _getYrForecast(
        latitude: latitude,
        longitude: longitude,
        startDate: startDate,
        endDate: endDate,
      );

      if (yrResult.daily.isNotEmpty) {
        debugPrint(
          '☀️ [WeatherService] yr.no OK — '
              '${yrResult.daily.length} days loaded',
        );
        return yrResult;
      }
    } catch (e) {
      debugPrint('⚠️ [WeatherService] yr.no failed: $e');
    }

    // ━━━ Tier 3: No data ━━━
    debugPrint('❌ [WeatherService] All providers failed — returning empty forecast');
    return WeatherForecast(daily: []);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  OPEN-METEO  —  Primary source
  //  • Free forever, no API key
  //  • 16-day forecast
  //  • Global coverage (Malaysia ✅)
  //  • https://open-meteo.com/en/docs
  // ═══════════════════════════════════════════════════════════════════════

  Future<WeatherForecast> _getOpenMeteoForecast({
    required double latitude,
    required double longitude,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = _formatDate(startDate);

    // Clamp to 16 days max (Open-Meteo free limit)
    final daysSpan = endDate.difference(startDate).inDays + 1;
    final clampedEnd = daysSpan > 16
        ? startDate.add(const Duration(days: 15))
        : endDate;
    final end = _formatDate(clampedEnd);

    final url = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      {
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
        'daily': [
          'temperature_2m_max',
          'temperature_2m_min',
          'weather_code',
          'precipitation_probability_max',
          'wind_speed_10m_max',
        ].join(','),
        'timezone': 'Asia/Kuala_Lumpur',
        'start_date': start,
        'end_date': end,
      },
    );

    debugPrint('🔗 [Open-Meteo] $url');

    final response = await http.get(url).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final daily = data['daily'];
    if (daily == null) throw Exception('Missing "daily" key in response');

    final dates = daily['time'] as List? ?? [];
    final maxTemps = daily['temperature_2m_max'] as List? ?? [];
    final minTemps = daily['temperature_2m_min'] as List? ?? [];
    final codes = daily['weather_code'] as List? ?? [];

    final List<DailyWeather> dailyWeather = [];

    for (int i = 0; i < dates.length; i++) {
      final date = DateTime.parse(dates[i] as String);

      if (date.isBefore(DateTime(startDate.year, startDate.month, startDate.day)) ||
          date.isAfter(DateTime(endDate.year, endDate.month, endDate.day))) {
        continue;
      }

      dailyWeather.add(
        DailyWeather(
          date: date,
          condition: _mapOpenMeteoCode(codes[i] as int?),
          maxTemperature: (maxTemps[i] as num?)?.toDouble() ?? 0.0,
          minTemperature: (minTemps[i] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    return WeatherForecast(daily: dailyWeather);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  YR.NO / MET NORWAY  —  Fallback
  //  • Free forever, no API key required
  //  • 9–10 day forecast
  //  • Global coverage (Malaysia ✅)
  //  • Only requirement: User-Agent header
  //  • https://developer.yr.no/doc
  // ═══════════════════════════════════════════════════════════════════════

  Future<WeatherForecast> _getYrForecast({
    required double latitude,
    required double longitude,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final url = Uri.parse(
      'https://api.met.no/weatherapi/locationforecast/2.0/compact'
          '?lat=${latitude.toStringAsFixed(4)}'
          '&lon=${longitude.toStringAsFixed(4)}',
    );

    debugPrint('🔗 [yr.no] $url');

    final response = await http.get(url, headers: {
      // ⚠️ yr.no REQUIRES a valid User-Agent — rejected without it
      'User-Agent': 'FoodieRouteApp/1.0 github.com/yourrepo',
      'Accept': 'application/json',
    }).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final timeseries = data['properties']?['timeseries'] as List? ?? [];

    if (timeseries.isEmpty) {
      throw Exception('Empty timeseries from yr.no');
    }

    // ── Group hourly data by date ──
    // Each entry has multiple timestamps; we group by date and
    // extract max/min temperature + symbol per day.
    final startComparable = DateTime(startDate.year, startDate.month, startDate.day);
    final endComparable   = DateTime(endDate.year,   endDate.month,   endDate.day);

    // Map: dateKey → { 'temps': [...], 'symbol': '...' }
    final Map<String, Map<String, dynamic>> grouped = {};

    for (final entry in timeseries) {
      final time = DateTime.parse(entry['time'] as String);
      final dateKey = _formatDate(time);
      final dateOnly = DateTime(time.year, time.month, time.day);

      // Skip dates outside requested range (with 1-day buffer for overnight data)
      if (dateOnly.isBefore(startComparable.subtract(const Duration(days: 1))) ||
          dateOnly.isAfter(endComparable.add(const Duration(days: 1)))) {
        continue;
      }

      final instant = entry['data']?['instant']?['details'];
      if (instant == null) continue;

      final temp = (instant['air_temperature'] as num?)?.toDouble();

      // Get symbol code: prefer next_1_hours → next_6_hours → next_12_hours
      final String? symbolCode =
          entry['data']?['next_1_hours']?['summary']?['symbol_code'] as String? ??
              entry['data']?['next_6_hours']?['summary']?['symbol_code'] as String? ??
              entry['data']?['next_12_hours']?['summary']?['symbol_code'] as String?;

      grouped.putIfAbsent(dateKey, () => {
        'temps': <double>[],
        'symbol': symbolCode,
      });

      if (temp != null) {
        (grouped[dateKey]!['temps'] as List<double>).add(temp);
      }
      // Update symbol to most specific (next_1_hours)
      if (symbolCode != null && (symbolCode.contains('_day') || !symbolCode.contains('_night'))) {
        grouped[dateKey]!['symbol'] = symbolCode;
      }
    }

    // ── Build DailyWeather from grouped data ──
    final List<DailyWeather> dailyWeather = [];

    final sortedKeys = grouped.keys.toList()..sort();
    for (final dateKey in sortedKeys) {
      final date = DateTime.parse(dateKey);

      // Filter strictly within range
      if (date.isBefore(startComparable) || date.isAfter(endComparable)) continue;

      final temps = grouped[dateKey]!['temps'] as List<double>;
      final symbol = grouped[dateKey]!['symbol'] as String?;

      final maxTemp = temps.isNotEmpty
          ? temps.reduce((a, b) => a > b ? a : b)
          : 0.0;
      final minTemp = temps.isNotEmpty
          ? temps.reduce((a, b) => a < b ? a : b)
          : 0.0;

      dailyWeather.add(
        DailyWeather(
          date: date,
          condition: _mapYrSymbol(symbol),
          maxTemperature: maxTemp,
          minTemperature: minTemp,
        ),
      );
    }

    return WeatherForecast(daily: dailyWeather);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  MAPPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// yr.no symbol codes
  /// https://api.met.no/weatherapi/weathericon/2.0/documentation
  String _mapYrSymbol(String? code) {
    if (code == null) return '🌤️ Data unavailable';
    final c = code.replaceAll(RegExp(r'_(day|night|polartwilight)$'), '');

    switch (c) {
      case 'clearsky':           return '☀️ Clear sky';
      case 'fair':               return '🌤️ Fair';
      case 'partlycloudy':       return '⛅ Partly cloudy';
      case 'cloudy':             return '☁️ Cloudy';
      case 'lightrainshowers':   return '🌦️ Light rain showers';
      case 'rainshowers':        return '🌧️ Rain showers';
      case 'heavyrainshowers':   return '🌧️ Heavy rain showers';
      case 'lightrain':          return '🌦️ Light rain';
      case 'rain':               return '🌧️ Rain';
      case 'heavyrain':          return '🌧️ Heavy rain';
      case 'lightrainandthunder': return '⛈️ Light rain + thunder';
      case 'rainandthunder':     return '⛈️ Rain + thunder';
      case 'heavyrainandthunder': return '⛈️ Heavy rain + thunder';
      case 'lightsnow':          return '❄️ Light snow';
      case 'snow':               return '❄️ Snow';
      case 'heavysnow':          return '❄️ Heavy snow';
      case 'lightsnowshowers':   return '🌨️ Light snow showers';
      case 'snowshowers':        return '🌨️ Snow showers';
      case 'heavysnowshowers':   return '🌨️ Heavy snow showers';
      case 'lightsnowandthunder': return '⛈️ Light snow + thunder';
      case 'snowandthunder':     return '⛈️ Snow + thunder';
      case 'heavysnowandthunder': return '⛈️ Heavy snow + thunder';
      case 'lightsleet':         return '🌧️ Light sleet';
      case 'sleet':              return '🌧️ Sleet';
      case 'heavysleet':         return '🌧️ Heavy sleet';
      case 'lightsleetshowers':  return '🌧️ Light sleet showers';
      case 'sleetshowers':       return '🌧️ Sleet showers';
      case 'heavysleetshowers':  return '🌧️ Heavy sleet showers';
      case 'lightsleetandthunder': return '⛈️ Light sleet + thunder';
      case 'sleetandthunder':    return '⛈️ Sleet + thunder';
      case 'heavysleetandthunder': return '⛈️ Heavy sleet + thunder';
      case 'fog':                return '🌫️ Fog';
      case 'lightrainshowersandthunder': return '🌦️ Light showers + thunder';
      case 'rainshowersandthunder': return '⛈️ Rain showers + thunder';
      case 'heavyrainshowersandthunder': return '⛈️ Heavy showers + thunder';
      default:                   return '🌤️ $code';
    }
  }

  /// WMO Weather interpretation codes (Open-Meteo)
  String _mapOpenMeteoCode(int? code) {
    if (code == null) return '🌤️ Data unavailable';
    switch (code) {
      case 0:                    return '☀️ Clear sky';
      case 1:                    return '🌤️ Mainly clear';
      case 2:                    return '⛅ Partly cloudy';
      case 3:                    return '☁️ Overcast';
      case 45: case 48:         return '🌫️ Fog';
      case 51:                   return '🌦️ Light drizzle';
      case 53:                   return '🌦️ Moderate drizzle';
      case 55:                   return '🌧️ Dense drizzle';
      case 56: case 57:         return '🌧️ Freezing drizzle';
      case 61:                   return '🌧️ Slight rain';
      case 63:                   return '🌧️ Moderate rain';
      case 65:                   return '🌧️ Heavy rain';
      case 66: case 67:         return '🌧️ Freezing rain';
      case 71:                   return '❄️ Slight snow';
      case 73:                   return '❄️ Moderate snow';
      case 75:                   return '❄️ Heavy snow';
      case 77:                   return '❄️ Snow grains';
      case 80:                   return '🌦️ Slight rain showers';
      case 81:                   return '🌧️ Moderate rain showers';
      case 82:                   return '🌧️ Violent rain showers';
      case 85: case 86:         return '❄️ Snow showers';
      case 95:                   return '⛈️ Thunderstorm';
      case 96:                   return '⛈️ Thunderstorm + hail';
      case 99:                   return '⛈️ Thunderstorm + heavy hail';
      default:                   return '🌤️ Mixed ($code)';
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}