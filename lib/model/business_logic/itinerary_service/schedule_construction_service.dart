// schedule_construction_service.dart

import '../../../core/config/itinerary_constants.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../entities/coordinates.dart';
import '../../entities/place.dart';
import 'anchor_selection_service.dart';
import 'scoring_service.dart';

class ScheduledStop {
  final ScoredAttraction attraction;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int travelFromPreviousMinutes;
  final String scheduleReason;
  final String weatherNote;

  const ScheduledStop({
    required this.attraction,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.travelFromPreviousMinutes,
    this.scheduleReason = '',
    this.weatherNote = '',
  });

  int get duration => endTime.difference(startTime).inMinutes;
}

class ScheduledDay {
  final int dayIndex;
  final DateTime date;
  final List<ScheduledStop> stops;
  final int totalDuration;
  final double totalTravelTime;

  const ScheduledDay({
    required this.dayIndex,
    required this.date,
    required this.stops,
    required this.totalDuration,
    required this.totalTravelTime,
  });
}

/// Pipeline Step: Schedule Construction.
///
/// Creates a time‑based schedule using the chosen transport mode.
/// Optionally uses AI-assisted time arrangement when [AIService] is
/// provided — the AI receives factual place data and returns only
/// time slots; the final stops are always reconstructed from the
/// original [Place] objects by placeId.
///
/// EXPLORATION WINDOW IS A HARD CONSTRAINT:
/// The returned schedule is deterministically enforced so that every stop
/// satisfies `window.start <= stop.start` AND `stop.end <= window.end`.
/// The AI output is treated as a proposal only — it is validated and, when
/// invalid, deterministically rebuilt.  This guarantee holds regardless of
/// what the AI returns.
class ScheduleConstructionService {
  static const double _walkingSpeedKph = 5.0;
  static const double _drivingSpeedKph = 40.0;
  static const double _transitSpeedKph = 30.0;

  final GoogleMapsService _mapsService;
  final AIService? _aiService;

  ScheduleConstructionService({
    GoogleMapsService? mapsService,
    AIService? aiService,
  })  : _mapsService = mapsService ?? GoogleMapsService(),
        _aiService = aiService;

  /// Create a schedule from daily plans, using the specified transport mode.
  ///
  /// When [useAi] is true and [AIService] is available, the AI arranges
  /// natural times for each day's ordered stops.  Every final stop is
  /// reconstructed from the original [Place] by placeId — the AI never
  /// invents factual data.  Regardless of the path taken, the returned
  /// schedule is validated and window-enforced before it is returned.
  Future<List<ScheduledDay>> constructSchedule({
    required List<DailyPlan> dailyPlans,
    required String explorationTime,
    required String transportMode,
    bool useAi = true,
    String travelPace = 'Standard',
  }) async {
    if (useAi && _aiService != null) {
      return _aiAssistedSchedule(
        dailyPlans,
        explorationTime,
        transportMode,
        travelPace: travelPace,
      );
    }
    return _deterministicSchedule(
      dailyPlans,
      explorationTime,
      transportMode,
      travelPace: travelPace,
    );
  }

  /// ── Deterministic schedule (fallback) ────────────────────────

  Future<List<ScheduledDay>> _deterministicSchedule(
    List<DailyPlan> dailyPlans,
    String explorationTime,
    String transportMode, {
    String travelPace = 'Standard',
  }) async {
    final window = _windowFor(explorationTime);
    final List<ScheduledDay> scheduledDays = [];

    for (final plan in dailyPlans) {
      final date = plan.date ?? DateTime(2024, 1, 1);
      final ordered = plan.sortedAttractions;

      final stops = await _buildWindowEnforcedStops(
        ordered: ordered,
        window: window,
        date: date,
        transportMode: transportMode,
        source: 'deterministic',
        travelPace: travelPace,
      );

      _verifyFinalSchedule(
        stops: stops,
        window: window,
        dayIndex: plan.dayIndex,
      );

      final totalDuration =
          stops.fold<int>(0, (sum, s) => sum + s.durationMinutes);
      final totalTravelTime = stops.fold<double>(
          0, (sum, s) => sum + s.travelFromPreviousMinutes);

      scheduledDays.add(ScheduledDay(
        dayIndex: plan.dayIndex,
        date: date,
        stops: stops,
        totalDuration: totalDuration,
        totalTravelTime: totalTravelTime,
      ));
    }

    return scheduledDays;
  }

  /// ── AI-assisted schedule construction ────────────────────────

  Future<List<ScheduledDay>> _aiAssistedSchedule(
    List<DailyPlan> dailyPlans,
    String explorationTime,
    String transportMode, {
    String travelPace = 'Standard',
  }) async {
    if (_aiService == null) {
      return _deterministicSchedule(dailyPlans, explorationTime, transportMode);
    }

    final window = _windowFor(explorationTime);
    final expStart = '${window.startHour.toString().padLeft(2, '0')}:'
        '${window.startMinute.toString().padLeft(2, '0')}';
    final expEnd = '${window.endHour.toString().padLeft(2, '0')}:'
        '${window.endMinute.toString().padLeft(2, '0')}';

    final List<ScheduledDay> scheduledDays = [];

    for (final plan in dailyPlans) {
      print('🕐 STEP 8 - AI SCHEDULE CONSTRUCTION');
      print('Day: ${plan.dayIndex + 1}');
      print('Exploration: $expStart - $expEnd');

      final date = plan.date ?? DateTime(2024, 1, 1);
      final ordered = plan.sortedAttractions;

      // Build the stop facts for the AI (with ACTUAL travel times).
      final stopFacts = <Map<String, dynamic>>[];
      final travelMinutes = <int>[];
      for (int i = 0; i < ordered.length; i++) {
        final attr = ordered[i];
        final place = attr.place;
        final travelFromPrev = (i > 0)
            ? await _getTravelTime(
                origin: ordered[i - 1].place.coordinates,
                destination: place.coordinates,
                mode: transportMode,
              )
            : 0.0;
        travelMinutes.add(travelFromPrev.ceil());

        print('📍 ${place.placeId} | ${place.placeName} '
            '| duration=${place.visitDurationMinutes} '
            '| travel=$travelFromPrev');

        stopFacts.add({
          'placeId': place.placeId,
          'name': place.placeName,
          'address': place.placeAddress,
          'latitude': place.placeLatitude,
          'longitude': place.placeLongitude,
          'rating': place.placeRating,
          'types': place.placeTypes.join(', '),
          'openingHours': place.openingHours?.weekdayText.isNotEmpty == true
              ? place.openingHours!.weekdayText.join('; ')
              : 'unknown',
          'visitDurationMinutes': place.visitDurationMinutes ?? 120,
          'travelFromPreviousMinutes': travelFromPrev.ceil(),
        });
      }

      print('🤖 Sending schedule request to AI...');

      final aiResult = await _aiService.constructDaySchedule(
        dayIndex: plan.dayIndex,
        date: date,
        destinationName: 'planned',
        explorationStart: expStart,
        explorationEnd: expEnd,
        travelPace: travelPace,
        stops: stopFacts,
        explorationWindow: window,
      );

      print('🤖 AI response: ${aiResult.schedule.length} stops, '
          'needsRepair=${aiResult.needsRepair}');

      // ── Deterministically validate / enforce the AI proposal ──
      // The AI is a proposal engine, NOT a constraint engine.  Every AI
      // stop is rebuilt inside the exploration window using the actual
      // visit durations and actual travel times.
      final stops = await _buildWindowEnforcedStops(
        ordered: ordered,
        window: window,
        date: date,
        transportMode: transportMode,
        source: 'ai',
        aiProposal: aiResult.schedule,
        travelMinutes: travelMinutes,
        travelPace: travelPace,
      );

      _verifyFinalSchedule(
        stops: stops,
        window: window,
        dayIndex: plan.dayIndex,
      );

      final totalDuration =
          stops.fold<int>(0, (sum, s) => sum + s.durationMinutes);
      final totalTravelTime = stops.fold<double>(
          0, (sum, s) => sum + s.travelFromPreviousMinutes);

      scheduledDays.add(ScheduledDay(
        dayIndex: plan.dayIndex,
        date: date,
        stops: stops,
        totalDuration: totalDuration,
        totalTravelTime: totalTravelTime,
      ));
    }

    return scheduledDays;
  }

  // ============================================================
  // WINDOW ENFORCEMENT (deterministic)
  // ============================================================

  /// Build stops that are guaranteed to fit inside [window].
  ///
  /// If [aiProposal] is provided, its *order* is respected but its times are
  /// deterministically rebuilt (the AI is not trusted to honour the window).
  /// Stops that cannot fit before the window end are skipped, never
  /// shortened or pushed past the end time.
  Future<List<ScheduledStop>> _buildWindowEnforcedStops({
    required List<ScoredAttraction> ordered,
    required ExplorationWindow window,
    required DateTime date,
    required String transportMode,
    required String source,
    List<AIScheduleStop>? aiProposal,
    List<int>? travelMinutes,
    String travelPace = 'Standard',
  }) async {
    final stops = <ScheduledStop>[];
    final windowStartMin = window.startHour * 60 + window.startMinute;
    final windowEndMin = window.endHour * 60 + window.endMinute;

    // Use the AI order when available; otherwise the sorted plan order.
    final effectiveOrder = <ScoredAttraction>[];
    if (aiProposal != null && aiProposal.isNotEmpty) {
      final seen = <String>{};
      for (final aiStop in aiProposal) {
        final match = ordered.cast<ScoredAttraction?>().firstWhere(
              (a) =>
                  a != null &&
                  a.place.placeId.toLowerCase() == aiStop.placeId.toLowerCase(),
              orElse: () => null,
            );
        if (match != null && seen.add(match.place.placeId)) {
          effectiveOrder.add(match);
        }
      }
    }
    if (effectiveOrder.isEmpty) {
      effectiveOrder.addAll(ordered);
    }

    var cursorMin = windowStartMin;
    final buffer = ItineraryConstants.bufferForPace(travelPace);
    final maxStops = ItineraryConstants.maxStopsPerDay;
    // Preferred (soft) activity boundary — stops before this are ideal;
    // must-visit places may extend past it, but the day should not be
    // packed merely because time remains.
    final preferredEndMin =
        ItineraryConstants.preferredActivityEndMinute(window, travelPace);

    // Log the pace planning rules for debugging.
    print('[PACE] Travel Pace: $travelPace '
        'Window: ${_hhmm(windowStartMin)} - ${_hhmm(windowEndMin)} '
        'Preferred boundary: ${_hhmm(preferredEndMin)} '
        'Hard boundary: ${_hhmm(windowEndMin)}');
    print(ItineraryConstants.paceRulesFor(travelPace,
        explorationStart: _hhmm(windowStartMin),
        explorationEnd: _hhmm(windowEndMin)));

    for (int i = 0; i < effectiveOrder.length && i < maxStops; i++) {
      final attraction = effectiveOrder[i];
      // Category- and pace-aware planned duration: use the place's known
      // visit duration when present, else derive from its category; then
      // apply the pace factor.
      final knownDuration = attraction.place.visitDurationMinutes;
      final baseDuration = knownDuration != null && knownDuration > 0
          ? knownDuration
          : ItineraryConstants.baseDurationForCategory(
              attraction.place.category,
              ItineraryConstants.defaultDurationMinutes,
            );
      final duration = _paceAdjustedDuration(baseDuration, travelPace);

      // Travel from the previous stop (actual when available).
      final travel = i > 0
          ? (travelMinutes != null && i < travelMinutes.length
              ? travelMinutes[i]
              : (await _getTravelTime(
                  origin: effectiveOrder[i - 1].place.coordinates,
                  destination: attraction.place.coordinates,
                  mode: transportMode,
                )).ceil())
          : 0;

      // Opening-hours check (best effort when data exists).
      final openingHours = attraction.place.openingHours;
      final opensOnDay = openingHours == null ||
          openingHours.isOpenOnDay(date.weekday);

      // FIRST stop starts at EXACTLY the exploration start.
      // Subsequent stops: previous end + travel time + pace buffer.
      final startMin = i == 0
          ? windowStartMin
          : cursorMin + travel + buffer;
      final endMin = startMin + duration;

      // Preferred-boundary gate: once the cursor exceeds the preferred
      // activity boundary, only must-visit places are considered for
      // addition (they may extend to the hard boundary).  This prevents
      // the scheduler from packing the day merely because time remains.
      final isMustVisit = attraction.isMustVisit;
      final couldFit = endMin <= windowEndMin;
      final withinPreferred = endMin <= preferredEndMin;
      final shouldAdd = couldFit && opensOnDay &&
          (withinPreferred || isMustVisit);

      final startStr = _hhmm(startMin);
      final endStr = _hhmm(endMin);

      print(
        '  ${startStr} - ${endStr} ${attraction.place.placeName}   '
        '${shouldAdd ? "SELECTED" : "REJECTED"}'
        '   [base=${baseDuration}m planned=${duration}m '
        'travel=${travel}m buffer=${buffer}m '
        'opens=$opensOnDay mustVisit=$isMustVisit]',
      );
      if (endMin > windowEndMin) {
        print('    Reason: exceeds ${_hhmm(windowEndMin)}');
      }
      if (endMin > preferredEndMin && !isMustVisit) {
        print('    Reason: past preferred boundary '
            '${_hhmm(preferredEndMin)}; not a must-visit');
      }
      if (!opensOnDay) {
        print('    Reason: closed on this day');
      }

      if (!shouldAdd) {
        continue;
      }

      stops.add(ScheduledStop(
        attraction: attraction,
        startTime: _dateAt(date, startMin),
        endTime: _dateAt(date, endMin),
        durationMinutes: duration,
        travelFromPreviousMinutes: i == 0 ? 0 : travel,
        scheduleReason: source == 'ai'
            ? 'AI-assisted, window-enforced'
            : 'Deterministic schedule',
        weatherNote: '',
      ));

      cursorMin = endMin;
    }

    // Log the final schedule summary.
    final totalActivity =
        stops.fold<int>(0, (s, st) => s + st.durationMinutes);
    final totalTravel = stops.fold<int>(
        0, (s, st) => s + st.travelFromPreviousMinutes);
    final flexible = windowEndMin - (stops.isEmpty ? windowStartMin : cursorMin);
    print('[STOP SELECTION] Selected: ${stops.length} '
        'Activity: ${totalActivity}m '
        'Travel: ${totalTravel}m '
        'Flexible: ${flexible}m '
        'Preferred boundary: ${_hhmm(preferredEndMin)} '
        'Hard boundary: ${_hhmm(windowEndMin)}');
    for (final s in stops) {
      print('  ${_hhmm(_toMin(s.startTime))} → ${_hhmm(_toMin(s.endTime))} '
          '${s.attraction.place.placeName}');
    }
    if (flexible > 0) {
      print('  Flexible time: ${_hhmm(cursorMin)} → ${_hhmm(windowEndMin)}');
    }

    return stops;
  }

  /// Apply the travel-pace duration factor to a base visit duration.
  int _paceAdjustedDuration(int base, String pace) {
    final factor = ItineraryConstants.durationFactorForPace(pace);
    final adjusted = (base * factor).round();
    return adjusted.clamp(
      ItineraryConstants.minimumVisitDurationMinutes,
      ItineraryConstants.maximumVisitDurationMinutes,
    );
  }

  int _toMin(DateTime t) => t.hour * 60 + t.minute;

  /// Deterministically validate the final day against the window.
  ///
  /// This is an actual validation (not just a print): it returns `true`
  /// only when every stop satisfies the window, duration and travel
  /// constraints.  The schedule built by this service is already
  /// window-enforced, so this acts as a final safety check.
  bool _verifyFinalSchedule({
    required List<ScheduledStop> stops,
    required ExplorationWindow window,
    required int dayIndex,
  }) {
    final windowStartMin = window.startHour * 60 + window.startMinute;
    final windowEndMin = window.endHour * 60 + window.endMinute;
    var valid = true;

    print('[SCHEDULE VALIDATION] Day ${dayIndex + 1} '
        'Window: ${_hhmm(windowStartMin)} - ${_hhmm(windowEndMin)}');

    for (int i = 0; i < stops.length; i++) {
      final s = stops[i];
      final startMin = s.startTime.hour * 60 + s.startTime.minute;
      final endMin = s.endTime.hour * 60 + s.endTime.minute;
      final endAfterStart = endMin > startMin;
      final inWindow = startMin >= windowStartMin && endMin <= windowEndMin;
      final durationOk = s.durationMinutes == endMin - startMin;

      var ok = endAfterStart && inWindow && durationOk;
      if (i > 0) {
        final prevEnd = stops[i - 1].endTime.hour * 60 +
            stops[i - 1].endTime.minute;
        ok = ok && startMin >= prevEnd + s.travelFromPreviousMinutes;
      }
      if (!ok) valid = false;

      print(
        '  ${_hhmm(startMin)} - ${_hhmm(endMin)} ${s.attraction.place.placeName}   '
        '${ok ? "VALID" : "INVALID"}',
      );
      if (endMin > windowEndMin) {
        print('    Reason: Stop exceeds exploration end time '
            '${_hhmm(windowEndMin)}');
      }
      if (startMin < windowStartMin) {
        print('    Reason: Stop before exploration start time '
            '${_hhmm(windowStartMin)}');
      }
      if (!durationOk) {
        print('    Reason: Duration mismatch (${s.durationMinutes}m vs '
            '${endMin - startMin}m)');
      }
    }

    return valid;
  }

  /// Get travel time (minutes) between two coordinates using the chosen mode.
  Future<double> _getTravelTime({
    required Coordinates origin,
    required Coordinates destination,
    required String mode,
  }) async {
    try {
      final travelInfo = await _mapsService.getTravelTime(
        origin: origin,
        destination: destination,
        mode: mode,
      );
      return travelInfo.durationMinutes;
    } catch (e) {
      return _estimateTravelTime(origin, destination, mode);
    }
  }

  double _estimateTravelTime(Coordinates a, Coordinates b, String mode) {
    final distanceKm = a.distanceTo(b);
    double speedKph;
    switch (mode) {
      case 'walking':
        speedKph = _walkingSpeedKph;
        break;
      case 'driving':
        speedKph = _drivingSpeedKph;
        break;
      case 'transit':
        speedKph = _transitSpeedKph;
        break;
      default:
        speedKph = _walkingSpeedKph;
    }
    return (distanceKm / speedKph) * 60.0;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  ExplorationWindow _windowFor(String explorationTime) =>
      ItineraryConstants.explorationWindows[explorationTime] ??
      ItineraryConstants.explorationWindows['Standard']!;

  DateTime _dateAt(DateTime date, int minutesOfDay) => DateTime(
        date.year,
        date.month,
        date.day,
        minutesOfDay ~/ 60,
        minutesOfDay % 60,
      );

  String _hhmm(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
