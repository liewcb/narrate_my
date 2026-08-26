import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/register_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC400 Register Account — both the phone-tab (A2) and the
/// username-tab (A3) branches, plus the shared Google entry point (A1).
///
/// The screen owns which tab is active; this ViewModel only exposes one
/// method per branch and reports back either a typed result (so the screen
/// knows where to navigate) or [errorMessage]/[fieldError] for inline
/// display — it never shows UI itself.
class RegisterVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  RegisterVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  /// Set alongside [errorMessage] when the failure is attributable to one
  /// specific field (username taken, weak password, phone format) so the
  /// form can highlight it instead of just showing a banner.
  String? fieldError;

  void _startSubmit() {
    isLoading = true;
    errorMessage = null;
    fieldError = null;
    notifyListeners();
  }

  void _finishWithError(AuthFailure e, {String? field}) {
    isLoading = false;
    errorMessage = e.message;
    fieldError = field ?? (e is ValidationFailure ? e.field : null);
    notifyListeners();
  }

  /// UC400 A1. Returns the created/existing [Profile] on success (Supabase
  /// itself decides new-vs-existing per A6), or null with [errorMessage]
  /// set on failure/cancellation.
  Future<Profile?> registerWithGoogle() async {
    _startSubmit();
    try {
      final profile = await _profileRepository.registerOrSignInWithGoogle();
      isLoading = false;
      notifyListeners();
      return profile;
    } on AuthFailure catch (e) {
      _finishWithError(e);
      return null;
    } catch (_) {
      _finishWithError(GoogleSignInFailure(RegisterMessages.m3GoogleSignInFailed));
      return null;
    }
  }

  /// UC400 A2, steps 1–4. On success the OTP has been sent — the screen
  /// should navigate to the OTP screen with `OtpFlow.registerPhone` and
  /// this same [e164Phone]. Returns true on success.
  Future<bool> sendPhoneOtp(String e164Phone) async {
    _startSubmit();
    try {
      await _profileRepository.sendPhoneRegistrationOtp(e164Phone);
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      _finishWithError(e, field: 'phone');
      return false;
    }
  }

  /// UC400 A3, steps 1–6. Validates the confirmation match locally (M10 —
  /// the only check the repository layer can't do, since it never sees the
  /// confirmation field) before delegating. On success the screen should
  /// navigate to the OTP screen with `OtpFlow.registerUsername`, this
  /// [e164Phone], and [username] as the flow's `pendingUsername`.
  Future<bool> sendUsernameOtp({
    required String username,
    required String password,
    required String confirmPassword,
    required String e164Phone,
  }) async {
    _startSubmit();
    if (!Validators.passwordsMatch(password, confirmPassword)) {
      _finishWithError(
        ValidationFailure(RegisterMessages.m10PasswordsDoNotMatch, field: 'confirmPassword'),
      );
      return false;
    }
    try {
      await _profileRepository.sendUsernameRegistrationOtp(
        username: username,
        password: password,
        e164Phone: e164Phone,
      );
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      _finishWithError(e);
      return false;
    }
  }
}
