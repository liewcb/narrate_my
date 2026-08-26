// lib/model/entities/weather.dart

/// Daily weather data for a specific date.
class DailyWeather {
  final DateTime date;
  final String condition;
  final double maxTemperature;
  final double minTemperature;

  const DailyWeather({
    required this.date,
    required this.condition,
    required this.maxTemperature,
    required this.minTemperature,
  });

  /// Convert to JSON for storage (optional).
  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'condition': condition,
    'maxTemperature': maxTemperature,
    'minTemperature': minTemperature,
  };

  /// Create from JSON (optional).
  factory DailyWeather.fromJson(Map<String, dynamic> json) {
    return DailyWeather(
      date: DateTime.parse(json['date']),
      condition: json['condition'],
      maxTemperature: (json['maxTemperature'] as num).toDouble(),
      minTemperature: (json['minTemperature'] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'DailyWeather(date: $date, condition: $condition, max: $maxTemperature°C, min: $minTemperature°C)';
}

/// Container for a list of daily weather forecasts.
class WeatherForecast {
  final List<DailyWeather> daily;

  const WeatherForecast({required this.daily});

  Map<String, dynamic> toJson() => {
    'daily': daily.map((d) => d.toJson()).toList(),
  };

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    return WeatherForecast(
      daily: (json['daily'] as List)
          .map((d) => DailyWeather.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() => 'WeatherForecast(daily: ${daily.length} days)';
}