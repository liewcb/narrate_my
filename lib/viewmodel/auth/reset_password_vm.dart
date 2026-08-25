import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/uc403_messages.dart';
import '../../model/business_logic/validators.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC403 Reset Password. Two stages, split across two screens
/// (Forgot Password → phone entry, Reset Password → new password), each
/// with its own method here; the OTP step in between is handled by the
/// shared `OtpVm` (`OtpFlow.resetPassword`).
class ResetPasswordVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  ResetPasswordVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  void _startSubmit() {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
  }

  /// Forgot Password screen, Basic Flow steps 3–6 (A1, A5). On success the
  /// screen navigates to the OTP screen with `OtpFlow.resetPassword` and
  /// this same [e164Phone].
  Future<bool> sendResetOtp(String e164Phone) async {
    _startSubmit();
    if (!Validators.isValidPhone(e164Phone)) {
      isLoading = false;
      errorMessage = Uc403Messages.m4PhoneNotRegistered;
      notifyListeners();
      return false;
    }
    try {
      await _profileRepository.sendPasswordResetOtp(e164Phone);
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Reset Password screen, Basic Flow steps 11–13 (A3 weak password, A4
  /// mismatch). Relies on the session `OtpVm` already established by
  /// verifying the reset OTP — must be called after that step succeeds.
  Future<bool> resetPassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    _startSubmit();
    if (!Validators.passwordsMatch(newPassword, confirmPassword)) {
      isLoading = false;
      errorMessage = Uc403Messages.m7PasswordsDoNotMatch;
      notifyListeners();
      return false;
    }
    if (!Validators.isValidPassword(newPassword)) {
      isLoading = false;
      errorMessage = Uc403Messages.m6InvalidPassword;
      notifyListeners();
      return false;
    }
    try {
      await _profileRepository.resetPassword(newPassword);
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
