// lib/model/business_logic/itinerary_service/ai_place_insertion_service.dart
//
// AI-first insertion planner for Recommended Places.
//
// AI decides:
//   - ACCEPT / REJECT
//   - insertion position
//   - visit duration
//   - approximate start/end time
//   - approximate travel time
//
// No Google routing and no deterministic ValidationService call are made
// in this insertion path. Dart performs only structural conversion checks.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/ai_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'custom_place_service.dart';
import 'schedule_construction_service.dart';

class AiPlaceInsertionResult {
  final bool accepted;
  final int? insertIndex;
  final String? insertAfterPlaceId;
  final int durationMinutes;
  final int? travelFromPreviousMinutes;
  final DateTime? startTime;
  final DateTime? endTime;
  final String reason;

  const AiPlaceInsertionResult({
    required this.accepted,
    required this.insertIndex,
    required this.insertAfterPlaceId,
    required this.durationMinutes,
    required this.travelFromPreviousMinutes,
    required this.startTime,
    required this.endTime,
    required this.reason,
  });
}

class AiPlaceInsertionService {
  final AIService _aiService;

  AiPlaceInsertionService({AIService? aiService})
      : _aiService = aiService ?? AIService();

  static const Duration defaultTimeout = Duration(seconds: 6);

  Future<AiPlaceInsertionResult?> validateAndPlan({
    required int dayIndex,
    required DateTime date,
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int defaultDurationMinutes,
    required String explorationTime,
    required String transportMode,
    required String travelPace,
    required List<String> interests,
    required Coordinates? tripLocation,
    Duration timeout = defaultTimeout,
  }) async {
    final prompt = _buildPrompt(
      dayIndex: dayIndex,
      date: date,
      existingStops: existingStops,
      newPlace: newPlace,
      defaultDurationMinutes: defaultDurationMinutes,
      explorationTime: explorationTime,
      transportMode: transportMode,
      travelPace: travelPace,
      interests: interests,
      tripLocation: tripLocation,
    );

    try {
      final raw = await _aiService
          .generateRawContent(
            prompt,
            timeout: timeout,
            totalBudget: timeout,
            requestName: 'RECOMMENDED_PLACE_AI_VALIDATE',
          )
          .timeout(timeout);

      return _parse(raw, date);
    } catch (e) {
      debugPrint('[AI Place Validation] request failed: $e');
      return null;
    }
  }

  String _buildPrompt({
    required int dayIndex,
    required DateTime date,
    required List<ExistingStopContext> existingStops,
    required Place newPlace,
    required int defaultDurationMinutes,
    required String explorationTime,
    required String transportMode,
    required String travelPace,
    required List<String> interests,
    required Coordinates? tripLocation,
  }) {
    final b = StringBuffer();

    b
      ..writeln('You are the final validator and planner for adding ONE place')
      ..writeln('to an existing travel itinerary day.')
      ..writeln()
      ..writeln('Use ONLY the supplied places.')
      ..writeln('Do not invent, replace, remove, or rename any existing stop.')
      ..writeln('The selected NEW PLACE is the only place that may be added.')
      ..writeln()
      ..writeln('Accept only when the place is suitable for the day,')
      ..writeln('geographically reasonable, and can fit the exploration period.')
      ..writeln('Prefer a nearby location because the candidate came from the')
      ..writeln('database using existing route/destination spatial anchors.')
      ..writeln()
      ..writeln(
        'Traveler interests: '
        '${interests.isEmpty ? 'none' : interests.join(', ')}',
      )
      ..writeln('Travel pace: $travelPace')
      ..writeln('Exploration time: $explorationTime')
      ..writeln('Transport: $transportMode')
      ..writeln('Day index: $dayIndex')
      ..writeln(
        'Date: ${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
      );

    if (tripLocation != null) {
      b.writeln(
        'Route center: ${tripLocation.latitude}, ${tripLocation.longitude}',
      );
    }

    b
      ..writeln()
      ..writeln('NEW PLACE:')
      ..writeln('placeId=${newPlace.placeId}')
      ..writeln('name=${newPlace.placeName}')
      ..writeln('category=${newPlace.placeCategory ?? 'unknown'}')
      ..writeln('rating=${newPlace.rating}')
      ..writeln('latitude=${newPlace.latitude}')
      ..writeln('longitude=${newPlace.longitude}')
      ..writeln('defaultVisitMinutes=$defaultDurationMinutes')
      ..writeln(
        'openingHours=${newPlace.openingHours ?? 'unknown'}',
      )
      ..writeln()
      ..writeln('EXISTING STOPS IN CURRENT ORDER:');

    for (var i = 0; i < existingStops.length; i++) {
      final s = existingStops[i];

      b
        ..writeln('STOP $i')
        ..writeln('placeId=${s.place.placeId}')
        ..writeln('name=${s.place.placeName}')
        ..writeln('category=${s.place.placeCategory ?? 'unknown'}')
        ..writeln('latitude=${s.place.latitude}')
        ..writeln('longitude=${s.place.longitude}')
        ..writeln('start=${_hhmm(s.startTime)}')
        ..writeln('end=${_hhmm(s.endTime)}')
        ..writeln('durationMinutes=${s.durationMinutes}')
        ..writeln('travelFromPreviousMinutes=${s.travelFromPrevMinutes}')
        ..writeln('mustVisit=${s.isMustVisit}')
        ..writeln();
    }

    b
      ..writeln('Return JSON ONLY. No markdown.')
      ..writeln()
      ..writeln('If the place should NOT be added:')
      ..writeln(
        '{"decision":"REJECT","insert_after_place_id":null,'
        '"duration_minutes":0,"start_time":null,"end_time":null,'
        '"travel_from_previous_minutes":0,"reason":"short reason"}',
      )
      ..writeln()
      ..writeln('If the place SHOULD be added:')
      ..writeln(
        '{"decision":"ACCEPT","insert_after_place_id":'
        '"<existing placeId or null>","duration_minutes":60,'
        '"start_time":"10:30","end_time":"11:30",'
        '"travel_from_previous_minutes":10,"reason":"short reason"}',
      )
      ..writeln()
      ..writeln('Rules:')
      ..writeln('- null insert_after_place_id means insert at the beginning.')
      ..writeln('- The ID must exactly match an existing stop ID.')
      ..writeln('- Keep existing stop times unchanged whenever possible.')
      ..writeln('- Do not move existing stops.')
      ..writeln('- Do not create another new place.')
      ..writeln('- Use the supplied default duration unless clearly inappropriate.')
      ..writeln('- travel_from_previous_minutes is an estimate.')
      ..writeln('- Reject when the day is already too full.');

    return b.toString();
  }

  AiPlaceInsertionResult? _parse(
    String raw,
    DateTime date,
  ) {
    try {
      final text = raw.trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');

      if (start < 0 || end <= start) return null;

      final decoded = jsonDecode(text.substring(start, end + 1));

      if (decoded is! Map<String, dynamic>) return null;

      final decision = decoded['decision']?.toString().toUpperCase();
      final accepted = decision == 'ACCEPT';
      final reason = decoded['reason']?.toString().trim() ?? '';

      if (!accepted) {
        return AiPlaceInsertionResult(
          accepted: false,
          insertIndex: null,
          insertAfterPlaceId: null,
          durationMinutes: 0,
          travelFromPreviousMinutes: 0,
          startTime: null,
          endTime: null,
          reason: reason.isEmpty
              ? 'The AI determined that this place should not be added.'
              : reason,
        );
      }

      final rawAfterId = decoded['insert_after_place_id'];
      final afterId = rawAfterId?.toString().trim();

      final duration =
          (decoded['duration_minutes'] as num?)?.toInt() ?? 0;
      final travel =
          (decoded['travel_from_previous_minutes'] as num?)?.toInt() ?? 0;

      if (duration <= 0 || duration > 480) return null;
      if (travel < 0 || travel > 240) return null;

      final startTime = _parseTime(decoded['start_time'], date);
      final endTime = _parseTime(decoded['end_time'], date);

      if (startTime == null || endTime == null) return null;
      if (!endTime.isAfter(startTime)) return null;

      return AiPlaceInsertionResult(
        accepted: true,
        insertIndex: null,
        insertAfterPlaceId:
            afterId == null || afterId.isEmpty ? null : afterId,
        durationMinutes: duration,
        travelFromPreviousMinutes: travel,
        startTime: startTime,
        endTime: endTime,
        reason: reason,
      );
    } catch (e) {
      debugPrint('[AI Place Validation] parse failed: $e');
      return null;
    }
  }

  DateTime? _parseTime(dynamic value, DateTime date) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) return null;

    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
  }

  String _hhmm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
