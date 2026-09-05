import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/register_messages.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs the Mandatory Details screen — a non-skippable step added at
/// Foo's request, shown exactly once, immediately after registration (any
/// method: phone, username, or Google). NOT part of the written UC402
/// Manage Preferences spec; deliberately kept separate from
/// [PreferencesVm]/`InitialPreferencesScreen`, which stays skippable.
class MandatoryDetailsVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  MandatoryDetailsVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  bool isSaving = false;
  String? errorMessage;

  /// Added 2 Sep: a tourist arriving here straight from Google Sign-In
  /// already has `full_name` on their profile row, copied from their Google
  /// account by `SupabaseProfileRepositoryAdapter._backfillFromGoogleIdentity`.
  /// The screen pre-fills the name field from this so they aren't asked to
  /// retype something they just handed over. Null for phone/username
  /// registrations, where the field simply starts empty as before.
  Profile? profile;

  Future<void> load() async {
    try {
      profile = await _profileRepository.fetchProfile();
      notifyListeners();
    } on AuthFailure catch (_) {
      // Non-fatal: this only feeds a convenience pre-fill. The tourist can
      // always type the name, and `save()` is what actually validates.
    }
  }

  /// Validates locally first (empty name / missing or future DOB — the
  /// screen shouldn't even need a round trip to catch these), then saves.
  /// Returns true on success.
  Future<bool> save({required String fullName, required DateTime? dateOfBirth}) async {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) {
      errorMessage = RegisterMessages.m11NameRequired;
      notifyListeners();
      return false;
    }
    if (dateOfBirth == null) {
      errorMessage = RegisterMessages.m12DobRequired;
      notifyListeners();
      return false;
    }
    if (dateOfBirth.isAfter(DateTime.now())) {
      errorMessage = RegisterMessages.m13DobInFuture;
      notifyListeners();
      return false;
    }
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final Profile _ = await _profileRepository.completeMandatoryDetails(
        fullName: trimmedName,
        dateOfBirth: dateOfBirth,
      );
      isSaving = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isSaving = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      isSaving = false;
      errorMessage = RegisterMessages.m14UnableToSaveDetails;
      notifyListeners();
      return false;
    }
  }
}
