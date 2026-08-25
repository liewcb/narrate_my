import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC402 A4 (Manage Preferred Language). [previewLanguageCode] is a
/// live, unsaved preview (A4 step 3 — "updates the on-screen display
/// immediately... not saved until Save is selected") separate from
/// [savedLanguageCode], the last committed value; [cancel] (A6) reverts the
/// preview without touching the account.
class LanguageVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  LanguageVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  String? savedLanguageCode;
  String? previewLanguageCode;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final profile = await _profileRepository.fetchProfile();
      savedLanguageCode = profile.preferredLanguage;
      previewLanguageCode = profile.preferredLanguage;
    } on AuthFailure catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// A4 step 2–3: live preview only.
  void preview(String code) {
    previewLanguageCode = code;
    notifyListeners();
  }

  /// A4 step 5 (Save) / REQ_503_11.
  Future<bool> save() async {
    final code = previewLanguageCode;
    if (code == null) return false;
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.updateLanguage(code);
      savedLanguageCode = code;
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

  /// A6: revert the live preview to the last saved value.
  void cancel() {
    previewLanguageCode = savedLanguageCode;
    notifyListeners();
  }
}
