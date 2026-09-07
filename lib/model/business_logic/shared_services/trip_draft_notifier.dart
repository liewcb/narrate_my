// lib/model/business_logic/shared_services/trip_draft_notifier.dart
import 'package:flutter/foundation.dart';
import '../../entities/trip_draft.dart';

class TripDraftNotifier extends ChangeNotifier {
  TripDraft _draft;

  TripDraftNotifier([TripDraft? initialDraft])
      : _draft = initialDraft ?? TripDraft.empty();

  TripDraft get draft => _draft;

  void updateDraft(TripDraft newDraft) {
    _draft = newDraft;
    notifyListeners();
  }

  void updateWith(TripDraft Function(TripDraft) updater) {
    _draft = updater(_draft);
    notifyListeners();
  }

  // Convenience: reset to empty
  void reset() {
    _draft = TripDraft.empty();
    notifyListeners();
  }
}