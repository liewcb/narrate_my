import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC402 A2 (Manage Personal Information). Phone-change (A9–A12) and
/// password-change (A16–A18) are separate sub-flows this VM triggers but
/// doesn't own the mechanics of — phone-change hands off to the shared
/// `OtpVm`/`OtpScreen` (`OtpFlow.changePhone`), password-change to its own
/// small `ChangePasswordVm`/screen. All on the same [ProfileRepository]
/// now (merged 25 Aug to match the architecture diagram) — the doc split
/// above referred to the old `AuthRepository`, which no longer exists.
class PersonalInfoVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  PersonalInfoVm({
    ProfileRepository? profileRepository,
  }) : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    load();
  }

  Profile? profile;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  String? fieldError;

  // Added at Foo's request (2 Sep): Delete Account moved here from the
  // Profile home screen, under this screen's own "Danger Zone" — separate
  // state from [errorMessage]/[isSaving] (which drive the Personal Info
  // form's own Save/Cancel) so a failed delete doesn't get tangled up with
  // an in-progress or just-failed field save.
  bool isDeletingAccount = false;
  String? deleteAccountErrorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      profile = await _profileRepository.fetchProfile();
    } on AuthFailure catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// UC402 A2 steps 3–8 (REQ_503_11 scopes the atomicity to the SECTION).
  /// Used to also take a `bio` param — removed 2 Sep at Foo's request along
  /// with the `profiles.bio` column and its field on the Personal Info
  /// screen.
  Future<bool> save({required String fullName}) async {
    if (!Validators.isNotEmpty(fullName)) {
      // A5: highlight-and-retry, not a full section reset.
      errorMessage = ProfileMessages.m4CorrectHighlighted;
      fieldError = 'fullName';
      notifyListeners();
      return false;
    }
    isSaving = true;
    errorMessage = null;
    fieldError = null;
    notifyListeners();
    try {
      profile = await _profileRepository.updatePersonalInfo(
        fullName: fullName.trim(),
      );
      isSaving = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      // A7: keep the caller's unsaved values on screen — this VM doesn't
      // clear `profile` on failure, so the screen's controllers (which the
      // caller owns) are untouched.
      isSaving = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// A6 (REQ_503_10): the screen discards its own staged controller text
  /// and re-reads `profile`'s last-saved values — this just supplies M5.
  String get discardedMessage => ProfileMessages.m5ChangesDiscarded;

  /// UC402 A9 steps 1–4 (A10 format, A11 duplicate). On success the screen
  /// navigates to `OtpScreen(flow: OtpFlow.changePhone, e164Phone:
  /// newE164Phone)`; after that pops back `true`, call [load] again to
  /// pick up the committed phone number.
  Future<bool> sendPhoneChangeOtp(String newE164Phone) async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.sendPhoneChangeOtp(newE164Phone);
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

  /// UC402 A13. On success (M12), [profile]'s `hasGoogleLinked` flips —
  /// the screen doesn't need a separate refresh.
  Future<bool> linkGoogleAccount() async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      profile = await _profileRepository.linkGoogleAccount();
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

  /// UC402 A20/A21. The confirmation prompt (M19) is the screen's
  /// responsibility — call this only after the tourist has confirmed.
  Future<bool> unlinkGoogleAccount() async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.unlinkGoogleAccount();
      isSaving = false;
      await load();
      return true;
    } on AuthFailure catch (e) {
      isSaving = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// UC402 "Delete Account" (added at Foo's request, not in the written
  /// spec — see `deleteAccount()` on `ProfileVm`, which this mirrors).
  /// Irreversible — the calling screen must confirm with the tourist first.
  Future<bool> deleteAccount() async {
    isDeletingAccount = true;
    deleteAccountErrorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.deleteAccount();
      isDeletingAccount = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isDeletingAccount = false;
      deleteAccountErrorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
