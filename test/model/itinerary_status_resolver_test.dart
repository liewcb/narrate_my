import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';

/// Verifies the single source of truth for itinerary-level status
/// (UPCOMING / ONGOING / PAST) using calendar-day comparison.
void main() {
  final start = DateTime(2026, 9, 10);
  final end = DateTime(2026, 9, 13);

  String statusFor(DateTime today) => ItineraryStatusResolver
      .resolve(startDate: start, endDate: end, now: today)
      .name
      .toUpperCase();

  group('ItineraryStatusResolver (TEST 1-6 / AC-01..AC-06)', () {
    test('TEST 1: 3 days before start → UPCOMING', () {
      expect(statusFor(DateTime(2026, 9, 7)), 'UPCOMING');
    });

    test('TEST 2: 1 day before start → UPCOMING', () {
      expect(statusFor(DateTime(2026, 9, 9)), 'UPCOMING');
    });

    test('TEST 3 / AC-02: today == start → ONGOING (inclusive)', () {
      expect(statusFor(DateTime(2026, 9, 10)), 'ONGOING');
    });

    test('TEST 4 / AC-03: mid-trip → ONGOING', () {
      expect(statusFor(DateTime(2026, 9, 12)), 'ONGOING');
    });

    test('TEST 5 / AC-04: today == end → ONGOING (inclusive)', () {
      expect(statusFor(DateTime(2026, 9, 13)), 'ONGOING');
    });

    test('TEST 6 / AC-05: day after end → PAST', () {
      expect(statusFor(DateTime(2026, 9, 14)), 'PAST');
    });

    test('AC-06: time-of-day never changes the calendar-day result', () {
      // Late in the day on the start date is still ONGOING.
      expect(statusFor(DateTime(2026, 9, 10, 23, 59, 59)), 'ONGOING');
      // Early on the day before start is still UPCOMING.
      expect(statusFor(DateTime(2026, 9, 9, 0, 0, 0)), 'UPCOMING');
    });

    test('one-day trip: start == end == today → ONGOING', () {
      final single = DateTime(2026, 9, 10);
      expect(
        ItineraryStatusResolver
            .resolve(startDate: single, endDate: single, now: single)
            .name
            .toUpperCase(),
        'ONGOING',
      );
    });

    test('UPCOMING countdown: days until start', () {
      final today = DateTime(2026, 9, 7);
      final startDay = DateTime(start.year, start.month, start.day);
      final daysUntilStart = startDay.difference(
        DateTime(today.year, today.month, today.day),
      ).inDays;
      expect(daysUntilStart, 3);
    });
  });
}
