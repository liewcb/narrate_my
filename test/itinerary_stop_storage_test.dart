import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/dto/itinerary_stop_dto.dart';
void main() {
  ItineraryStopDTO stop(String status, DateTime start, DateTime end) => ItineraryStopDTO(
    stopId: 1, itineraryId: 'trip', placeId: 'place', dayIndex: 1, stopOrder: 1,
    startTime: start, endTime: end, durationMinutes: 60, stopStatus: status,
    weatherNote: 'Rain expected', createdAt: DateTime(2026), updatedAt: DateTime(2026));
  test('unscheduled serializes to supported status and round-trips without fake time', () {
    final row = stop('UNSCHEDULED', DateTime(2026), DateTime(2026)).toMap();
    expect(row['stop_status'], 'PLANNED');
    expect(row['start_time'], '00:00:00');
    expect(row['end_time'], '00:01:00');
    final restored = ItineraryStopDTO.fromMap(row).toEntity();
    expect(restored.stopStatus, 'UNSCHEDULED');
    expect(restored.startTime, restored.endTime);
    expect(restored.weatherNote, 'Rain expected');
  });
  test('scheduled planned stop and weather note are unchanged', () {
    final row = stop('PLANNED', DateTime(2026,1,1,10), DateTime(2026,1,1,11)).toMap();
    expect(row['weather_note'], 'Rain expected');
    final restored = ItineraryStopDTO.fromMap(row).toEntity();
    expect(restored.stopStatus, 'PLANNED');
    expect(restored.startTime.hour, 10);
    expect(restored.endTime.hour, 11);
  });
  test('completed and skipped statuses remain unchanged', () {
    for (final status in ['COMPLETED', 'SKIPPED']) {
      final row = stop(status, DateTime(2026,1,1,10), DateTime(2026,1,1,11)).toMap();
      expect(row['stop_status'], status);
      expect(ItineraryStopDTO.fromMap(row).stopStatus, status);
    }
  });
  test('setting a real time removes the unscheduled storage marker', () {
    final pending = ItineraryStopDTO.fromMap(stop('UNSCHEDULED', DateTime(2026), DateTime(2026)).toMap()).toEntity();
    final scheduled = pending.copyWith(stopStatus: 'PLANNED',
      startTime: DateTime(2026,1,1,10), endTime: DateTime(2026,1,1,11));
    final row = ItineraryStopDTO.fromEntity(scheduled).toMap();
    expect(row['weather_note'], 'Rain expected');
    expect(ItineraryStopDTO.fromMap(row).stopStatus, 'PLANNED');
  });
}
