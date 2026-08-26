// models/travel_info.dart
/// Travel information between two locations.
class TravelInfo {
  final double distanceKm;
  final double durationMinutes;
  final String durationText;

  const TravelInfo({
    required this.distanceKm,
    required this.durationMinutes,
    required this.durationText,
  });

  /// Convert to a Map for JSON serialization.
  Map<String, dynamic> toJson() => {
    'distanceKm': distanceKm,
    'durationMinutes': durationMinutes,
    'durationText': durationText,
  };

  /// Create from JSON.
  factory TravelInfo.fromJson(Map<String, dynamic> json) {
    return TravelInfo(
      distanceKm: (json['distanceKm'] as num).toDouble(),
      durationMinutes: (json['durationMinutes'] as num).toDouble(),
      durationText: json['durationText'] as String,
    );
  }

  @override
  String toString() =>
      'TravelInfo(distanceKm: $distanceKm, durationMinutes: $durationMinutes, durationText: $durationText)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TravelInfo &&
              runtimeType == other.runtimeType &&
              distanceKm == other.distanceKm &&
              durationMinutes == other.durationMinutes &&
              durationText == other.durationText;

  @override
  int get hashCode =>
      distanceKm.hashCode ^ durationMinutes.hashCode ^ durationText.hashCode;
}