import 'dart:convert';
import '../entities/itinerary.dart';

/// Data Transfer Object for [Itinerary].
/// Handles conversion between the domain entity and database/network maps.
class ItineraryDTO {
  final String itineraryId;
  final String userId;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final String explorationTime;
  final String travelPace;
  final List<String> interests;
  final String? coverImageUrl;
  final String status;
  final int version;
  final DateTime lastModifiedAt;
  final Map<String, dynamic>? lastValidationResult;
  final bool isDraft;
  final DateTime createdAt;

  const ItineraryDTO({
    required this.itineraryId,
    required this.userId,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.explorationTime,
    required this.travelPace,
    required this.interests,
    this.coverImageUrl,
    this.status = 'UPCOMING',
    this.version = 1,
    required this.lastModifiedAt,
    this.lastValidationResult,
    this.isDraft = false,
    required this.createdAt,
  });

  // ---------- From/To Entity ----------
  factory ItineraryDTO.fromEntity(Itinerary entity) {
    return ItineraryDTO(
      itineraryId: entity.itineraryId,
      userId: entity.userId,
      title: entity.title,
      description: entity.description,
      startDate: entity.startDate,
      endDate: entity.endDate,
      totalDays: entity.totalDays,
      explorationTime: entity.explorationTime,
      travelPace: entity.travelPace,
      interests: entity.interests,
      coverImageUrl: entity.coverImageUrl,
      status: entity.status,
      version: entity.version,
      lastModifiedAt: entity.lastModifiedAt,
      lastValidationResult: entity.lastValidationResult,
      isDraft: entity.isDraft,
      createdAt: entity.createdAt,
    );
  }

  Itinerary toEntity() {
    return Itinerary(
      itineraryId: itineraryId,
      userId: userId,
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      totalDays: totalDays,
      explorationTime: explorationTime,
      travelPace: travelPace,
      interests: interests,
      coverImageUrl: coverImageUrl,
      status: status,
      version: version,
      lastModifiedAt: lastModifiedAt,
      lastValidationResult: lastValidationResult,
      isDraft: isDraft,
      createdAt: createdAt,
    );
  }

  factory ItineraryDTO.fromMap(Map<String, dynamic> map) {
    final rawInterests = map['interests'];

    if (map == null || map.isEmpty) {
      throw ArgumentError('Map is null or empty');
    }

    List<String> interests = [];

    if (rawInterests is List) {
      interests = rawInterests
          .map((e) => e.toString())
          .toList();
    } else if (rawInterests is String &&
        rawInterests.isNotEmpty) {
      final decoded = jsonDecode(rawInterests);

      if (decoded is List) {
        interests = decoded
            .map((e) => e.toString())
            .toList();
      }
    }

    final rawValidation = map['last_validation_result'];

    Map<String, dynamic>? lastValidationResult;

    if (rawValidation == null) {
      lastValidationResult = null;
    } else if (rawValidation is Map) {
      lastValidationResult =
      Map<String, dynamic>.from(rawValidation);
    } else if (rawValidation is String &&
        rawValidation.isNotEmpty) {
      final decoded = jsonDecode(rawValidation);

      if (decoded is Map) {
        lastValidationResult =
        Map<String, dynamic>.from(decoded);
      }
    }

    return ItineraryDTO(
      itineraryId: map['itinerary_id']?.toString() ?? '',
      userId: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      startDate: DateTime.parse(
        map['start_date'].toString(),
      ),
      endDate: DateTime.parse(
        map['end_date'].toString(),
      ),
      totalDays: (map['total_days'] as num?)?.toInt() ?? 0,
      explorationTime:
      map['exploration_time']?.toString() ?? '',
      travelPace:
      map['travel_pace']?.toString() ?? '',
      interests: interests,
      coverImageUrl:
      map['cover_image_url']?.toString(),
      status:
      map['status']?.toString() ?? 'UPCOMING',
      version:
      (map['version'] as num?)?.toInt() ?? 1,
      lastModifiedAt: map['last_modified_at'] != null
          ? DateTime.parse(
        map['last_modified_at'].toString(),
      )
          : DateTime.now(),
      lastValidationResult:
      lastValidationResult,
      isDraft:
      map['is_draft'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(
        map['created_at'].toString(),
      )
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMapForRemote() {
    return {
      'itinerary_id': itineraryId,
      'id': userId,
      'title': title,
      'description': description,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'total_days': totalDays,
      'exploration_time': explorationTime,
      'travel_pace': travelPace,
      'interests': interests, // ✅ List – Supabase array
      'cover_image_url': coverImageUrl,
      'status': status,
      'version': version,
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'last_validation_result': lastValidationResult != null
          ? jsonEncode(lastValidationResult)
          : null,
      'is_draft': isDraft, // ✅ boolean
      'created_at': createdAt.toIso8601String(),
    };
  }

  // ---------- For SQLite (local) ----------
  Map<String, dynamic> toMapForLocal() {
    return {
      'itinerary_id': itineraryId,
      'id': userId,
      'title': title,
      'description': description,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'total_days': totalDays,
      'exploration_time': explorationTime,
      'travel_pace': travelPace,
      'interests': jsonEncode(interests), // ✅ JSON string
      'cover_image_url': coverImageUrl,
      'status': status,
      'version': version,
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'last_validation_result': lastValidationResult != null
          ? jsonEncode(lastValidationResult)
          : null,
      'is_draft': isDraft ? 1 : 0, // ✅ integer
      'created_at': createdAt.toIso8601String(),
    };
  }
}