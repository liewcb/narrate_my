// lib/domain/entities/itinerary.dart

class Itinerary {
  final String itineraryId;
  final String userId;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final String explorationTime;   // 'Relaxed', 'Standard', 'Intense'
  final String travelPace;        // 'Slow', 'Standard', 'Fast'
  final String travelType;        // 'Solo', 'Family', 'Group', ...
  final String transportationMode; // 'walking', 'driving', 'transit'
  final List<String> interests;
  final String? coverImageUrl;
  final String status;            // 'UPCOMING', 'ONGOING', 'PAST'
  final int version;
  final DateTime lastModifiedAt;
  final Map<String, dynamic>? lastValidationResult;
  final bool isDraft;
  final DateTime createdAt;

  const Itinerary({
    required this.itineraryId,
    required this.userId,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.explorationTime,
    required this.travelPace,
    this.travelType = 'Solo',
    this.transportationMode = 'walking',
    required this.interests,
    this.coverImageUrl,
    this.status = 'UPCOMING',
    this.version = 1,
    required this.lastModifiedAt,
    this.lastValidationResult,
    this.isDraft = false,
    required this.createdAt,
  });

  Itinerary copyWith({
    String? itineraryId,
    String? userId,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    int? totalDays,
    String? explorationTime,
    String? travelPace,
    String? travelType,
    String? transportationMode,
    List<String>? interests,
    String? coverImageUrl,
    String? status,
    int? version,
    DateTime? lastModifiedAt,
    Map<String, dynamic>? lastValidationResult,
    bool? isDraft,
    DateTime? createdAt,
  }) {
    return Itinerary(
      itineraryId: itineraryId ?? this.itineraryId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalDays: totalDays ?? this.totalDays,
      explorationTime: explorationTime ?? this.explorationTime,
      travelPace: travelPace ?? this.travelPace,
      travelType: travelType ?? this.travelType,
      transportationMode:
          transportationMode ?? this.transportationMode,
      interests: interests ?? this.interests,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      status: status ?? this.status,
      version: version ?? this.version,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      lastValidationResult: lastValidationResult ?? this.lastValidationResult,
      isDraft: isDraft ?? this.isDraft,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}