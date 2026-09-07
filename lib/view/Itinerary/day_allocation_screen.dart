import 'package:flutter/material.dart';
import '../../model/entities/trip_draft.dart';
import 'split_days_screen.dart';

/// Step 4: Allocate days to each destination.
/// Receives the current draft from the previous wizard step.
class AddAllocationScreen extends StatelessWidget {
  final TripDraft draft;

  const AddAllocationScreen({super.key, required this.draft});

  @override
  Widget build(BuildContext context) {
    // Build DestinationWithDays list from the draft's destinations.
    // Use daySplit if available, otherwise default to 1 day per destination.
    final destinationsWithDays = draft.destinations.map((dest) {
      final allocatedDays = draft.daySplit[dest.destinationName] ?? 1;
      return DestinationWithDays(
        id: dest.id,
        name: dest.destinationName,
        imageUrl: dest.imageUrl,
        initialDays: allocatedDays,
      );
    }).toList();

    // If daySplit is empty, distribute days evenly (or fallback to totalDays / count).
    int totalDays = draft.totalDays;
    if (draft.daySplit.isEmpty) {
      // Use even distribution as fallback.
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
      draft: draft,
      destinations: destinationsWithDays,
      totalPlannedDays: totalDays,
    );
  }
}