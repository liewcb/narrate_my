import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile/profile_adapter.dart';
import '../../model/repositories/interfaces/profile/profile_repository.dart';

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

  /// Own error slot for the phone-change bottom sheet — kept separate from
  /// [errorMessage] (used by Save/Google link/unlink) so a Google-link
  /// failure never shows inside the phone-change sheet, and a failed phone
  /// change never shows on the main screen's banner. Previously both
  /// actions shared [errorMessage], which meant whichever failed last would
  /// incorrectly render in the OTHER action's UI too.
  String? phoneChangeErrorMessage;

  void clearPhoneChangeError() {
    if (phoneChangeErrorMessage == null) return;
    phoneChangeErrorMessage = null;
    notifyListeners();
  }

  // Separate from [errorMessage] for the same reason as
  // [phoneChangeErrorMessage] — a failed delete shouldn't surface inside
  // any other action's error slot on this screen.
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

  /// UC402 A2 steps 3–8. Bio removed 6 Sep at Foo's request — it wasn't
  /// used anywhere in the app — so this now only saves [fullName].
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
    phoneChangeErrorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.sendPhoneChangeOtp(newE164Phone);
      isSaving = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isSaving = false;
      phoneChangeErrorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// UC402 A13. On success (M12), [profile]'s `hasGoogleLinked` flips —
  /// the screen doesn't need a separate refresh.
  Future<bool> linkGoogleAccount() async {
    isSaving = true;
    errorMessage = null;
    // BUG FIX (6 Sep, Foo: "google link error can go to the name field"):
    // this never reset `fieldError`, so if the Full Name save had failed
    // earlier and left `fieldError == 'fullName'` sitting there, a LATER
    // Google-link failure would set `errorMessage` but leave that stale
    // `fieldError` in place — and since the screen shows the Full Name
    // field's error text whenever `fieldError == 'fullName'`, the Google
    // error would render inside the Full Name field instead of the
    // banner below the Google row. Same fix applied to unlinkGoogleAccount.
    fieldError = null;
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
    fieldError = null; // see the comment in linkGoogleAccount() above
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

  // --- Added at Foo's request — NOT in the written spec ----------------------

  /// Moved here (off the Profile home screen, away from Logout) 6 Sep at
  /// Foo's request — deleting the account doesn't belong next to logging
  /// out of it. Irreversible-reading, though the account is actually
  /// soft-deleted server-side; the caller must confirm with the tourist
  /// before calling this. Returns true on success; the caller should then
  /// navigate away (there is no profile left to show).
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
