// lib/viewmodel/ItineraryModel/itinerary_final_vm.dart
//
// ViewModel for ItineraryFinalScreen — holds the validated
// ItineraryResult and exposes derived presentation state.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/config/api_keys.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';

/// UI display model for a single itinerary stop.
class StopData {
  final String time;
  final String duration;
  final String name;
  final String type;
  final String? imageUrl;
  final String? transitTime; // actual travel time e.g. "15 min"
  final bool isHighlighted;

  StopData({
    required this.time,
    required this.duration,
    required this.name,
    required this.type,
    this.imageUrl,
    this.transitTime,
    this.isHighlighted = false,
  });
}

/// UI display model for a single day.
class DayData {
  final int dayNumber;
  final String date;
  final int totalStops;
  final String? timeRange;
  final bool isSelected;
  final List<StopData> stops;

  DayData({
    required this.dayNumber,
    required this.date,
    required this.totalStops,
    this.timeRange,
    this.isSelected = false,
    required this.stops,
  });
}

/// ViewModel for the final itinerary preview screen.
///
/// Owns the validated [ItineraryResult] and derives all presentation
/// state (day list, statistics, title, date range, city count, hero
/// image, transit formatting). The View is a pure projection of this
/// state and never performs generation or business logic.
class ItineraryFinalViewModel extends ChangeNotifier {
  ItineraryResult _result;
  final String _title;
  final String? _itineraryId;
  final Future<void> Function()? _regenerateRequest;
  final Future<ItineraryResult> Function()? _regenerateAlternatives;
  final Future<bool> Function()? _saveRequest;

  int _selectedDayIndex = 0;

  ItineraryFinalViewModel({
    required ItineraryResult result,
    required String title,
    String? itineraryId,
    Future<void> Function()? regenerateRequest,
    Future<ItineraryResult> Function()? regenerateAlternatives,
    Future<bool> Function()? saveRequest,
  })  : _result = result,
        _title = title,
        _itineraryId = itineraryId,
        _regenerateRequest = regenerateRequest,
        _regenerateAlternatives = regenerateAlternatives,
        _saveRequest = saveRequest;

  // ─── State ────────────────────────────────────────────────────

  bool isLoading = false;
  bool isSaving = false;
  bool isSaved = false;
  String? errorMessage;
  String? saveMessage;

  // ─── Getters ──────────────────────────────────────────────────

  ItineraryResult get result => _result;
  String get title => _title;
  String? get itineraryId => _itineraryId;

  /// Whether a regeneration callback was provided (i.e. the screen can
  /// offer a "Regenerate" action wired to the generation pipeline).
  bool get canRegenerate =>
      _regenerateRequest != null || _regenerateAlternatives != null;

  /// True while regeneration is running (blocks repeated taps).
  bool get isRegenerating => isLoading;

  int get selectedDayIndex => _selectedDayIndex;

  /// The full day list derived from the scheduled days.
  List<DayData> get days => _buildDays();

  int get totalStops =>
      _result.scheduledDays?.fold<int>(0, (sum, d) => sum + d.stops.length) ?? 0;

  Duration get totalTravelTime => Duration(
        minutes: _result.scheduledDays?.fold<int>(
                0, (sum, d) => sum + d.totalTravelTime.toInt()) ??
            0,
      );

  /// Number of unique destination IDs from the scheduled stops.
  int get cityCount {
    final ids = <String>{};
    for (final day in _result.scheduledDays ?? []) {
      for (final stop in day.stops) {
        final destId = stop.attraction.place.destinationId;
        if (destId != null && destId.isNotEmpty) ids.add(destId);
      }
    }
    return ids.isNotEmpty ? ids.length : (_result.scheduledDays?.isNotEmpty == true ? 1 : 0);
  }

  /// Date range from the first to last scheduled day.
  String get dateRange {
    final days = _result.scheduledDays;
    if (days == null || days.isEmpty) return '';
    final first = days.first.date;
    final last = days.last.date;
    final formatter = DateFormat('MMM d');
    return '${formatter.format(first)} – ${formatter.format(last)}';
  }

  /// Hero image: first stop's place photo, or null for a neutral placeholder.
  String? get heroImageUrl {
    for (final day in _result.scheduledDays ?? []) {
      for (final stop in day.stops) {
        final ref = stop.attraction.place.placePhotoRef;
        if (ref != null && ref.isNotEmpty) {
          return 'https://maps.googleapis.com/maps/api/place/photo'
              '?maxwidth=800&photoreference=$ref'
              '&key=${ApiKeys.googleMapsApiKey}'; // ✅ added API key
        }
      }
    }
    return null;
  }

  // ─── Actions ──────────────────────────────────────────────────

  void selectDay(int index) {
    _selectedDayIndex = index;
    notifyListeners();
  }

  /// Re-run generation via the provided callback. Sets loading state
  /// and updates [_result] on success. Uses the candidate-reuse
  /// regeneration callback when available, otherwise the full pipeline.
  ///
  /// Old itinerary is preserved when the returned result is the SAME object
  /// (the regeneration service returns the original unchanged on failure).
  Future<void> regenerate() async {
    if (!canRegenerate) return;
    if (isLoading) return; // prevent concurrent regeneration
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (_regenerateAlternatives != null) {
        final newResult = await _regenerateAlternatives();
        if (!identical(newResult, _result)) {
          updateResult(newResult);
        } else {
          errorMessage = 'Regeneration failed. The previous itinerary has '
              'been preserved.';
        }
      } else if (_regenerateRequest != null) {
        await _regenerateRequest();
      }
    } catch (e) {
      errorMessage = 'Regeneration failed: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Replace the held result (called after regeneration completes).
  void updateResult(ItineraryResult newResult) {
    _result = newResult;
    _selectedDayIndex = 0;
    isSaved = false;
    saveMessage = null;
    notifyListeners();
  }

  /// Whether a save callback was provided.
  bool get canSave => _saveRequest != null;

  /// True while a save operation is in progress (blocks duplicate saves).
  bool get isSaveInProgress => isSaving;

  /// Save the current itinerary via the provided repository-backed callback.
  Future<void> save() async {
    if (!canSave || isSaving) return;
    if (!_result.success) {
      saveMessage = 'The itinerary is not valid and cannot be saved.';
      notifyListeners();
      return;
    }
    isSaving = true;
    saveMessage = null;
    notifyListeners();

    try {
      final ok = await _saveRequest!();
      if (ok) {
        isSaved = true;
        saveMessage = 'Itinerary saved successfully.';
      } else {
        saveMessage = 'Unable to save itinerary. Please check your '
            'connection and try again.';
      }
    } catch (e) {
      saveMessage = 'Unable to save itinerary. Please check your '
          'connection and try again.';
    }
    isSaving = false;
    notifyListeners();
  }

  // ─── Private helpers ──────────────────────────────────────────

  List<DayData> _buildDays() {
    final sDays = _result.scheduledDays;
    if (sDays == null || sDays.isEmpty) return [];
    final formatter = DateFormat('EEE, MMM d');

    return sDays.map((day) {
      final stops = day.stops.map((s) {
        final place = s.attraction.place;
        return StopData(
          time: _fmtTime(s.startTime),
          duration: '${s.durationMinutes} min',
          name: place.placeName,
          type: place.category ??
              (place.placeTypes.isNotEmpty ? place.placeTypes.first : 'Attraction'),
          imageUrl: place.placePhotoRef != null
              ? 'https://maps.googleapis.com/maps/api/place/photo'
                  '?maxwidth=200&photoreference=${place.placePhotoRef}'
              : null,
          transitTime: s.travelFromPreviousMinutes > 0
              ? '${s.travelFromPreviousMinutes} min'
              : null,
          isHighlighted: day.stops.isNotEmpty && s == day.stops.first,
        );
      }).toList();

      final first = day.stops.isNotEmpty ? day.stops.first : null;
      final last = day.stops.isNotEmpty ? day.stops.last : null;

      return DayData(
        dayNumber: day.dayIndex + 1,
        date: formatter.format(day.date),
        totalStops: stops.length,
        timeRange: (first != null && last != null)
            ? '${_fmtTime(first.startTime)} - ${_fmtTime(last.endTime)}'
            : null,
        isSelected: day.dayIndex == _selectedDayIndex,
        stops: stops,
      );
    }).toList();
  }

  String _fmtTime(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:$m $ampm';
  }
}