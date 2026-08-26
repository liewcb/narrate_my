// lib/domain/entities/itinerary_stop.dart
import 'place.dart';

class ItineraryStop {
  final int stopId;
  final String itineraryId;
  final String placeId;          // references places.id
  final int dayIndex;
  final int stopOrder;
  final DateTime startTime;      // stored as TIME but we use DateTime for convenience
  final DateTime endTime;
  final int durationMinutes;
  final int? travelFromPrevMinutes;
  final String stopStatus;       // 'PLANNED', 'COMPLETED', 'SKIPPED'
  final String? skipReason;
  final String? weatherNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Joined Place data (nullable — filled by the ViewModel/repository).
  final Place? place;

  const ItineraryStop({
    required this.stopId,
    required this.itineraryId,
    required this.placeId,
    required this.dayIndex,
    required this.stopOrder,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.travelFromPrevMinutes,
    this.stopStatus = 'PLANNED',
    this.skipReason,
    this.weatherNote,
    this.place,
    required this.createdAt,
    required this.updatedAt,
  });

  ItineraryStop copyWith({
    int? stopId,
    String? itineraryId,
    String? placeId,
    int? dayIndex,
    int? stopOrder,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    int? travelFromPrevMinutes,
    String? stopStatus,
    String? skipReason,
    String? weatherNote,
    Place? place,
    bool clearPlace = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItineraryStop(
      stopId: stopId ?? this.stopId,
      itineraryId: itineraryId ?? this.itineraryId,
      placeId: placeId ?? this.placeId,
      dayIndex: dayIndex ?? this.dayIndex,
      stopOrder: stopOrder ?? this.stopOrder,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      travelFromPrevMinutes: travelFromPrevMinutes ?? this.travelFromPrevMinutes,
      stopStatus: stopStatus ?? this.stopStatus,
      skipReason: skipReason ?? this.skipReason,
      weatherNote: weatherNote ?? this.weatherNote,
      place: clearPlace ? null : (place ?? this.place),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------- Serialization ----------
  Map<String, dynamic> toMap() {
    return {
      'stop_id': stopId,
      'itinerary_id': itineraryId,
      'place_id': placeId,
      'day_index': dayIndex,
      'stop_order': stopOrder,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration_minutes': durationMinutes,
      'travel_from_prev_minutes': travelFromPrevMinutes,
      'stop_status': stopStatus,
      'skip_reason': skipReason,
      'weather_note': weatherNote,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ItineraryStop.fromMap(Map<String, dynamic> map) {
    return ItineraryStop(
      stopId: map['stop_id'] as int,
      itineraryId: map['itinerary_id'] as String,
      placeId: map['place_id'] as String,
      dayIndex: map['day_index'] as int,
      stopOrder: map['stop_order'] as int,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      durationMinutes: map['duration_minutes'] as int,
      travelFromPrevMinutes: map['travel_from_prev_minutes'] as int?,
      stopStatus: map['stop_status'] as String? ?? 'PLANNED',
      skipReason: map['skip_reason'] as String?,
      weatherNote: map['weather_note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
