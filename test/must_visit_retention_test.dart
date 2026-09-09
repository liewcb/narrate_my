import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/core/services/ai_service.dart';
import 'package:narrate_my/model/business_logic/itinerary_service/ai_schedule_validator.dart';
const id = 'ChIJj1G3Qtc3zDER-HLxtyN2cHo';
AIDaySchedule day(int n, List<AIScheduleStop> stops) => AIDaySchedule(dayIndex:n,date:'2026-09-09',schedule:stops);
AIScheduleStop stop(String id) => AIScheduleStop(stopOrder:1,placeId:id,startTime:'10:00',endTime:'11:00',visitDurationMinutes:60,travelFromPreviousMinutes:0,scheduleReason:'',weatherNote:'');
void main() {
 test('one-day missing must-visit survives validation as unscheduled', () {
   final days=retainUnscheduledMustVisits(days:[day(0,[stop('ordinary')])],durations:{id:90},targetDays:{id:0});
   final result=AiScheduleValidator().validate(days:days,knownPlaceIds:{id,'ordinary'},mustVisitIds:[id],totalDays:1,explorationTime:'Relaxed',unscheduledPlaceIds:{id});
   expect(result.passed,isTrue,reason:result.feedbackText);
   expect(days.single.schedule.last.placeId,id);
   expect(days.single.schedule.last.startTime,'00:00');
 });
 test('all-unscheduled day is valid when the known required place cannot fit', () {
   final days=retainUnscheduledMustVisits(days:[day(0,[])],durations:{id:90},targetDays:{id:0});
   expect(AiScheduleValidator().validate(days:days,knownPlaceIds:{id},mustVisitIds:[id],totalDays:1,explorationTime:'Relaxed',unscheduledPlaceIds:{id}).passed,isTrue);
 });
 test('retention is idempotent and does not duplicate a scheduled must-visit', () {
   final original=[day(0,[stop(id)])];
   final first=retainUnscheduledMustVisits(days:original,durations:{id:90},targetDays:{id:0});
   final second=retainUnscheduledMustVisits(days:first,durations:{id:90},targetDays:{id:0});
   expect(second.single.schedule.length,1);
   expect(second.single.schedule.single.startTime,'10:00');
 });
 test('pending place stays on its assigned day and still checks destination', () {
   final days=retainUnscheduledMustVisits(days:[day(0,[]),day(1,[])],durations:{id:90},targetDays:{id:1});
   expect(days.first.schedule,isEmpty);
   final result=AiScheduleValidator().validate(days:days,knownPlaceIds:{id},mustVisitIds:[id],totalDays:2,explorationTime:'Relaxed',unscheduledPlaceIds:{id},destinationOrder:['KL','Penang'],allocatedDaysPerDestination:{'KL':1,'Penang':1},placeIdToDestination:{id:'KL'});
   expect(result.passed,isFalse);
 });
 test('unknown retained place remains invalid', () {
   final days=retainUnscheduledMustVisits(days:[day(0,[])],durations:{id:90},targetDays:{id:0});
   final result=AiScheduleValidator().validate(days:days,knownPlaceIds:{},mustVisitIds:[id],totalDays:1,explorationTime:'Relaxed',unscheduledPlaceIds:{id});
   expect(result.issues.any((i)=>i.type=='unknown_place_id'),isTrue);
 });
 test('unapproved zero-length times are still rejected', () {
   final days=retainUnscheduledMustVisits(days:[day(0,[])],durations:{id:90},targetDays:{id:0});
   expect(AiScheduleValidator().validate(days:days,knownPlaceIds:{id},mustVisitIds:[id],totalDays:1,explorationTime:'Relaxed').passed,isFalse);
 });
}
