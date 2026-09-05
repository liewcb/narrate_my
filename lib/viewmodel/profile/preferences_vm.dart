import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/entities/preferences.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC402 A3 (Manage Preferences). All five categories save together
/// as one atomic update (REQ_503_11 scopes atomicity to the section) — the
/// screen stages edits locally (a plain [Preferences] value it builds from
/// its own chip-selection state) and only calls [save] once, on the
/// section's Save button.
class PreferencesVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  PreferencesVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  Preferences? preferences;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      preferences = await _profileRepository.fetchPreferences();
    } on AuthFailure catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save(Preferences updated) async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.updatePreferences(updated);
      preferences = updated;
      isSaving = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isSaving = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
