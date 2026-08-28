import '../entities/itinerary_stop.dart';

class ItineraryStopDTO {
  final int stopId;
  final String itineraryId;
  final String placeId;
  final String? destinationId;
  final int dayIndex;
  final int stopOrder;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int? travelFromPrevMinutes;
  final String stopStatus;
  final String? skipReason;
  final String? weatherNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ItineraryStopDTO({
    required this.stopId,
    required this.itineraryId,
    required this.placeId,
    this.destinationId,
    required this.dayIndex,
    required this.stopOrder,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.travelFromPrevMinutes,
    this.stopStatus = 'PLANNED',
    this.skipReason,
    this.weatherNote,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Helper: parse a time-only string (HH:mm:ss) into DateTime (dummy date 1970-01-01)
  static DateTime _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return DateTime(1970, 1, 1, 0, 0);
    }
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      return DateTime(1970, 1, 1, hour, minute);
    }
    return DateTime(1970, 1, 1, 0, 0);
  }

  /// Helper: format DateTime to time-only string (HH:mm:ss)
  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';
  }

  /// Create from Supabase/Postgres map.
  factory ItineraryStopDTO.fromMap(Map<String, dynamic> map) {
    return ItineraryStopDTO(
      stopId: map['stop_id'] as int,
      itineraryId: map['itinerary_id'] as String,
      placeId: map['place_id'] as String,
      destinationId: map['destination_id'] as String?,
      dayIndex: map['day_index'] as int,
      stopOrder: map['stop_order'] as int,
      startTime: _parseTime(map['start_time'] as String?),
      endTime: _parseTime(map['end_time'] as String?),
      durationMinutes: map['duration_minutes'] as int,
      travelFromPrevMinutes: map['travel_from_prev_minutes'] as int?,
      stopStatus: map['stop_status'] ?? 'PLANNED',
      skipReason: map['skip_reason'] as String?,
      weatherNote: map['weather_note'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// Convert to Supabase/Postgres map.
  Map<String, dynamic> toMap() {
    return {
      'stop_id': stopId,
      'itinerary_id': itineraryId,
      'place_id': placeId,
      'destination_id': destinationId,
      'day_index': dayIndex,
      'stop_order': stopOrder,
      'start_time': _formatTime(startTime),
      'end_time': _formatTime(endTime),
      'duration_minutes': durationMinutes,
      'travel_from_prev_minutes': travelFromPrevMinutes,
      'stop_status': stopStatus,
      'skip_reason': skipReason,
      'weather_note': weatherNote,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to domain entity.
  ItineraryStop toEntity() {
    return ItineraryStop(
      stopId: stopId,
      itineraryId: itineraryId,
      placeId: placeId,
      destinationId: destinationId,
      dayIndex: dayIndex,
      stopOrder: stopOrder,
      startTime: startTime,          // ✅ already DateTime
      endTime: endTime,              // ✅ already DateTime
      durationMinutes: durationMinutes,
      travelFromPrevMinutes: travelFromPrevMinutes,
      stopStatus: stopStatus,
      skipReason: skipReason,
      weatherNote: weatherNote,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Create DTO from domain entity.
  factory ItineraryStopDTO.fromEntity(ItineraryStop entity) {
    return ItineraryStopDTO(
      stopId: entity.stopId,
      itineraryId: entity.itineraryId,
      placeId: entity.placeId,
      destinationId: entity.destinationId,
      dayIndex: entity.dayIndex,
      stopOrder: entity.stopOrder,
      startTime: entity.startTime,
      endTime: entity.endTime,
      durationMinutes: entity.durationMinutes,
      travelFromPrevMinutes: entity.travelFromPrevMinutes,
      stopStatus: entity.stopStatus,
      skipReason: entity.skipReason,
      weatherNote: entity.weatherNote,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}