import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/business_logic/shared_services/trip_draft_notifier.dart';
import '../../model/entities/trip_draft.dart';
import './split_days_screen.dart';

/// Step 4: Allocate days to each destination.
/// Receives the current draft from the previous wizard step.
class AddAllocationScreen extends StatelessWidget {
  const AddAllocationScreen({super.key}); // Removed constructor parameter

  @override
  Widget build(BuildContext context) {
    // Read directly from global notifier
    final draft = context.watch<TripDraftNotifier>().draft;

    final destinationsWithDays = draft.destinations.map((dest) {
      final allocatedDays = draft.daySplit[dest.destinationName] ?? 1;
      return DestinationWithDays(
        id: dest.id,
        name: dest.destinationName,
        imageUrl: dest.imageUrl,
        initialDays: allocatedDays,
      );
    }).toList();

    int totalDays = draft.totalDays;
    if (draft.daySplit.isEmpty) {
      final count = destinationsWithDays.length;
      if (count > 0) {
        final base = totalDays ~/ count;
        final extra = totalDays % count;
        for (int i = 0; i < count; i++) {
          destinationsWithDays[i].days = base + (i < extra ? 1 : 0);
        }
      }
    }

    return SplitDaysScreen(
      destinations: destinationsWithDays,
      totalPlannedDays: totalDays,
    );
  }
}