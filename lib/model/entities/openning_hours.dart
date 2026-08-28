
class OpeningHours {
  final bool isOpenNow;
  final List<Period> periods;
  final List<String> weekdayText;

  const OpeningHours({
    required this.isOpenNow,
    this.periods = const [],
    this.weekdayText = const [],
  });

  /// Alias getter to support code using `.openNow` without breaking existing references to `.isOpenNow`
  bool get openNow => isOpenNow;

  /// Create from JSON (Google Places API format).
  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    return OpeningHours(
      isOpenNow: json['open_now'] ?? json['isOpenNow'] ?? false,
      periods: (json['periods'] as List?)
          ?.map((p) => Period.fromJson(p as Map<String, dynamic>))
          .toList() ??
          [],
      weekdayText: (json['weekday_text'] as List?)?.cast<String>() ?? [],
    );
  }

  /// Convert to JSON for storage.
  Map<String, dynamic> toJson() => {
    'isOpenNow': isOpenNow,
    'periods': periods.map((p) => p.toJson()).toList(),
    'weekdayText': weekdayText,
  };

  /// Check if the place is open on a specific date.
  ///
  /// [date] The date to check.
  /// Returns `true` if open, `false` otherwise.
  bool isOpenOnDay(int weekday) {
    final periodDay = weekday % 7; // 1→1, 7→0
    return periods.any((p) => p.open.day == periodDay);
  }

  bool isOpenWithinWindow(int windowStartMinutes, int windowEndMinutes) {
    for (final period in periods) {
      final openMinutes = _timeToMinutes(period.open.time);
      final closeMinutes = _timeToMinutes(period.close.time);
      if (openMinutes < windowEndMinutes && closeMinutes > windowStartMinutes) {
        return true;
      }
    }
    return false;
  }

  int _timeToMinutes(String time) {
    final hours = int.parse(time.substring(0, 2));
    final minutes = int.parse(time.substring(2, 4));
    return hours * 60 + minutes;
  }

  @override
  String toString() => 'OpeningHours(isOpenNow: $isOpenNow, periods: ${periods.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is OpeningHours &&
              runtimeType == other.runtimeType &&
              isOpenNow == other.isOpenNow &&
              periods.length == other.periods.length;

  @override
  int get hashCode => isOpenNow.hashCode ^ periods.length.hashCode;
}

/// Represents a period (open/close) for a specific day.
class Period {
  final Time open;
  final Time close;

  const Period({required this.open, required this.close});

  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      open: Time.fromJson(json['open'] as Map<String, dynamic>),
      close: Time.fromJson(json['close'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'open': open.toJson(),
    'close': close.toJson(),
  };

  @override
  String toString() => 'Period(open: $open, close: $close)';
}

/// Represents a specific time in the opening hours schedule.
class Time {
  final int day; // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  final String time; // Format: "HHMM" e.g., "0900" or "2200"

  const Time({required this.day, required this.time});

  factory Time.fromJson(Map<String, dynamic> json) {
    return Time(
      day: json['day'] as int,
      time: json['time'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'time': time,
  };

  /// Convert the time string to a JSON-friendly map.
  Map<String, int> toTimeMap() {
    final hours = int.parse(time.substring(0, 2));
    final minutes = int.parse(time.substring(2, 4));
    return {'hour': hours, 'minute': minutes};
  }

  @override
  String toString() => 'Time(day: $day, time: $time)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Time &&
              runtimeType == other.runtimeType &&
              day == other.day &&
              time == other.time;

  @override
  int get hashCode => day.hashCode ^ time.hashCode;
}
