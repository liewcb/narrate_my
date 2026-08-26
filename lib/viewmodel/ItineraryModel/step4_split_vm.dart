// lib/viewmodel/ItineraryModel/step4_split_vm.dart
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../model/entities/trip_draft.dart';

/// A computed allocation for a single destination used by the View.
class DestinationAllocation {
  final String destination;
  final int days;
  final String dayLabel;          // e.g. "DAY 1-3"
  final DateTime startDate;       // e.g. Aug 20
  final DateTime endDate;         // e.g. Aug 22
  final String dateRangeLabel;    // e.g. "Aug 20 – Aug 22"

  DestinationAllocation({
    required this.destination,
    required this.days,
    required this.dayLabel,
    required this.startDate,
    required this.endDate,
    required this.dateRangeLabel,
  });
}

/// ViewModel for Step 4 (Split your trip).
class Step4SplitVM extends ChangeNotifier {
  final TripDraft _incomingDraft;

  late List<String> destinations;
  final Map<String, int> _daySplit = {};

  Step4SplitVM(this._incomingDraft) {
    destinations = List.of(_incomingDraft.destinations);

    if (_incomingDraft.daySplit.isNotEmpty) {
      _daySplit.addAll(_incomingDraft.daySplit);
    } else {
      autoBalanceDays();
    }
  }

  // ─── Getters ─────────────────────────────────────────────────

  Map<String, int> get daySplit => Map.unmodifiable(_daySplit);

  int get totalDays => _incomingDraft.totalDays;
  DateTime? get startDate => _incomingDraft.startDate;
  DateTime? get endDate => _incomingDraft.endDate;

  int get allocatedDays => _daySplit.values.fold(0, (a, b) => a + b);

  /// Computed allocations in destination order with day labels and
  /// calendar date ranges.
  List<DestinationAllocation> get allocations {
    if (destinations.isEmpty) return [];
    final sd = startDate;
    if (sd == null) return [];

    final result = <DestinationAllocation>[];
    final formatter = DateFormat('MMM d');
    int dayStart = 1;
    var cursor = sd;

    for (final dest in destinations) {
      final days = _daySplit[dest] ?? 1;
      final destStart = cursor;
      final destEnd = cursor.add(Duration(days: days - 1));
      final dayEnd = dayStart + days - 1;

      result.add(DestinationAllocation(
        destination: dest,
        days: days,
        dayLabel: dayStart == dayEnd ? 'DAY $dayStart' : 'DAY $dayStart-$dayEnd',
        startDate: destStart,
        endDate: destEnd,
        dateRangeLabel: '${formatter.format(destStart)} – ${formatter.format(destEnd)}',
      ));

      dayStart = dayEnd + 1;
      cursor = destEnd.add(const Duration(days: 1));
    }
    return result;
  }

  Map<String, String> get validationErrors {
    final errors = <String, String>{};
    if (destinations.isEmpty) {
      errors['destinations'] = 'No destinations selected.';
    } else if (totalDays < destinations.length) {
      errors['days'] =
          'Trip has $totalDays days but needs at least ${destinations.length} days '
          '(one per destination). Extend your dates in Step 2.';
    } else if (allocatedDays != totalDays) {
      errors['days'] =
          'Allocated days ($allocatedDays) must equal total days ($totalDays).';
    } else {
      // Date-range validation: the last destination must end on the trip end date.
      final allocs = allocations;
      if (allocs.isNotEmpty) {
        final lastEnd = allocs.last.endDate;
        final tripEnd = endDate;
        if (tripEnd != null && lastEnd != tripEnd) {
          errors['dates'] =
              'Last destination (${allocs.last.destination}) ends on '
              '${DateFormat('MMM d').format(lastEnd)} but the trip ends on '
              '${DateFormat('MMM d').format(tripEnd)}. Adjust the day split.';
        }
      }
    }
    return errors;
  }

  Map<String, String> validate() => validationErrors;

  // ─── Day Allocation ──────────────────────────────────────────

  void setDayCount(String destination, int days) {
    if (_daySplit[destination] == null) return;
    final others = destinations.where((d) => d != destination).toList();
    final maxForDest = totalDays - others.length;
    final clamped = days.clamp(1, maxForDest).toInt();
    if (clamped != days) return;
    if (_daySplit[destination] == clamped) return;
    _daySplit[destination] = clamped;
    _rebalanceOthers(destination);
    notifyListeners();
  }

  void incrementDay(String destination) {
    if (_daySplit[destination] == null) return;
    final others = destinations.where((d) => d != destination).toList();
    final maxForDest = totalDays - others.length;
    final current = _daySplit[destination]!;
    if (current < maxForDest) {
      _daySplit[destination] = current + 1;
      _rebalanceOthers(destination);
      notifyListeners();
    }
  }

  void decrementDay(String destination) {
    if (_daySplit[destination] == null) return;
    final current = _daySplit[destination]!;
    if (current > 1) {
      _daySplit[destination] = current - 1;
      _rebalanceOthers(destination);
      notifyListeners();
    }
  }

  // ─── Reordering ──────────────────────────────────────────────

  /// Move a destination from [oldIndex] to [newIndex] without
  /// changing its allocated day count.
  void reorderDestinations(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= destinations.length) return;
    final dest = destinations.removeAt(oldIndex);
    destinations.insert(newIndex, dest);
    notifyListeners();
  }

  // ─── Auto-balance ────────────────────────────────────────────

  void autoBalanceDays() {
    if (destinations.isEmpty) return;
    final days = totalDays;
    int base = days ~/ destinations.length;
    int extra = days % destinations.length;
    for (int i = 0; i < destinations.length; i++) {
      _daySplit[destinations[i]] = base + (i < extra ? 1 : 0);
    }
    notifyListeners();
  }

  // ─── Build Draft ─────────────────────────────────────────────

  TripDraft buildDraft([TripDraft? prior]) {
    final errors = validationErrors;
    if (errors.isNotEmpty) {
      throw StateError(errors.values.first);
    }
    return (prior ?? _incomingDraft).copyWith(
      destinations: List.of(destinations),
      daySplit: Map.of(_daySplit),
    );
  }

  // ─── Private Helpers ─────────────────────────────────────────

  void _rebalanceOthers(String excludedDestination) {
    final others = destinations.where((d) => d != excludedDestination).toList();
    final used = _daySplit[excludedDestination]!;
    int remaining = totalDays - used;
    if (remaining < 0) {
      _daySplit[excludedDestination] = totalDays - (others.length - 1);
      remaining = totalDays - _daySplit[excludedDestination]!;
    }
    if (others.isNotEmpty) {
      int base = remaining ~/ others.length;
      int extra = remaining % others.length;
      for (int i = 0; i < others.length; i++) {
        _daySplit[others[i]] = base + (i < extra ? 1 : 0);
      }
    }
  }
}