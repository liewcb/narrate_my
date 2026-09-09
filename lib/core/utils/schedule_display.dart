import 'package:flutter/material.dart';

/// Unscheduled placeholders must never participate in clock comparisons.
bool isUnscheduledTime(DateTime start, DateTime end, {String? status}) =>
    status == 'UNSCHEDULED' ||
    (start.hour == 0 && start.minute == 0 && end.hour == 0 && end.minute == 0);

String formatScheduleMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
}

/// Resolves transportation icon based on user's selected mode (e.g. KTM/LRT/MRT, Driving, Walking).
IconData getTransportationIcon(String? mode) {
  if (mode == null || mode.isEmpty) return Icons.directions_car_rounded;
  final m = mode.toLowerCase();
  if (m.contains('transit') ||
      m.contains('ktm') ||
      m.contains('lrt') ||
      m.contains('mrt') ||
      m.contains('train') ||
      m.contains('subway') ||
      m.contains('rail')) {
    return Icons.directions_subway_rounded;
  }
  if (m.contains('bus')) {
    return Icons.directions_bus_rounded;
  }
  if (m.contains('walk')) {
    return Icons.directions_walk_rounded;
  }
  if (m.contains('bike') || m.contains('cycl')) {
    return Icons.directions_bike_rounded;
  }
  return Icons.directions_car_rounded;
}
