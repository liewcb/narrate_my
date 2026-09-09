import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/services/ai_service.dart';
import 'package:narrate_my/model/entities/place.dart';
import 'package:narrate_my/model/entities/weather.dart';
import 'package:narrate_my/model/business_logic/itinerary_service/generation_pipeline_service.dart';
import 'package:narrate_my/model/business_logic/itinerary_service/schedule_construction_service.dart';
import 'package:narrate_my/model/business_logic/itinerary_service/scoring_service.dart';
import 'package:narrate_my/viewmodel/Itinerary/edit_itinerary_vm.dart';

final date = DateTime(2026, 9, 9);
ScheduledStop stop(String id, int start, int end, {bool mustVisit = false}) => ScheduledStop(
  attraction: ScoredAttraction(place: Place(placeId: id, placeName: id,
    placeAddress: 'Test', placeRating: 4.5, placeTypes: const ['museum'], placeLatitude: 3.1, placeLongitude: 101.6),
    score: 1, breakdown: const {}, isMustVisit: mustVisit),
  startTime: date.add(Duration(minutes: start)),
  endTime: date.add(Duration(minutes: end)),
  durationMinutes: end-start, travelFromPreviousMinutes: 0);
ItineraryResult result(List<ScheduledStop> stops) => ItineraryResult.success(
  scheduledDays: [ScheduledDay(dayIndex: 0, date: date, stops: stops,
    totalDuration: 180, totalTravelTime: 0)],
  weather: const WeatherForecast(daily: []),
  criticFeedback: const CriticResult(overallSuitable: true, score: 90,
    issues: [], recommendations: [], summary: ''));
EditItineraryViewModel model(ItineraryResult input) => EditItineraryViewModel(
  result: input, dayIndex: 0, tripStartDate: date, explorationTime: 'Standard',
  mustVisitPlaceIds: [], title: 'Test', now: () => date.add(const Duration(hours: 19)));

void main() {
  test('overflow is retained as unscheduled, with no next-day time', () {
    final input = result([stop('a', 600, 660), stop('b', 1421, 1541)]).scheduledDays!.first;
    final fixed = normalizeProposedDay(input, 'Standard');
    expect(fixed.stops.length, 2);
    expect(fixed.stops.last.startTime, date);
    expect(fixed.stops.last.endTime, date);
    expect(fixed.stops.last.scheduleReason, contains('Unscheduled'));
    expect(fixed.stops.last.travelFromPreviousMinutes, 0);
    expect(input.stops.last.endTime.day, 10);
  });
  test('same-day wrapped time is unscheduled and IDs are deduplicated', () {
    final input = result([stop('a', 600, 660), stop('a', 720, 780),
      stop('b', 1421, 101)]).scheduledDays!.first;
    final fixed = normalizeProposedDay(input, 'Standard');
    expect(fixed.stops.length, 2);
    expect(fixed.stops.last.endTime, date);
  });
  test('existing unscheduled stop cannot make another stop start at dawn', () {
    final input = result([stop('a', 600, 660), stop('b', 0, 0),
      stop('c', 20, 80)]).scheduledDays!.first;
    final fixed = normalizeProposedDay(input, 'Standard');
    expect(fixed.stops.first.startTime.hour, 10);
    expect(fixed.stops.skip(1).every((s) => s.startTime == date && s.endTime == date), isTrue);
  });

  test('cross-midnight stop remains removable before it ends', () async {
    final vm = model(result([stop('a', 1200, 1260), stop('b', 1421, 1541)]));
    expect(vm.isStopEditable(1), isTrue);
    expect(await vm.removeStopByPlaceId('b'), isTrue);
    expect(vm.stops.length, 1);
    vm.dispose();
  });
  test('unscheduled stop can be removed', () async {
    final vm = model(result([stop('a', 1200, 1260), stop('b', 0, 0)]));
    expect(await vm.removeStopByPlaceId('b'), isTrue);
    vm.dispose();
  });
  test('delete is draft-only and preserves manually selected times until review', () async {
    final input = result([stop('a', 1200, 1260), stop('b', 1320, 1380)]);
    final vm = model(input);
    expect(await vm.removeStopByPlaceId('a'), isTrue);
    expect(input.scheduledDays!.first.stops.length, 2);
    expect(vm.appliedResult, isNull);
    expect(vm.hasChanges, isTrue);
    expect(vm.stops.first.startTime, date.add(const Duration(minutes: 1320)));
    vm.applyChanges();
    expect(vm.appliedResult!.scheduledDays!.first.stops.length, 1);
    expect(input.scheduledDays!.first.stops.length, 2);
    vm.dispose();
  });
  test('end-time-only changes require discard confirmation', () {
    final vm = model(result([stop('a', 1200, 1260)]));
    expect(vm.hasChanges, isFalse);
    vm.stops.first.endTime = vm.stops.first.endTime.add(const Duration(minutes: 15));
    expect(vm.hasChanges, isTrue);
    vm.dispose();
  });
  test('elapsed stops remain protected with a visible reason', () async {
    final vm = model(result([stop('a', 600, 660), stop('b', 1200, 1260)]));
    expect(await vm.removeStopByPlaceId('a'), isFalse);
    expect(vm.error, isNotNull);
    expect(vm.hasChanges, isFalse);
    vm.dispose();
  });
  test('last stop cannot be removed and original remains intact', () async {
    final vm = model(result([stop('a', 1200, 1260)]));
    expect(await vm.removeStopByPlaceId('a'), isFalse);
    expect(vm.stops.length, 1);
    expect(vm.hasChanges, isFalse);
    vm.dispose();
  });
}

