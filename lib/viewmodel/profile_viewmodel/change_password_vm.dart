import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/repositories/adapters/profile/profile_adapter.dart';
import '../../model/repositories/interfaces/profile/profile_repository.dart';

/// Backs UC402 A16–A18 (C6): change password for an account that already
/// has one. Kept separate from [PersonalInfoVm] since it's a distinct
/// confirmation-gated action (current password re-check, M15/M16/M17/M18),
/// not part of the section's normal Save.
class ChangePasswordVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  ChangePasswordVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  /// Added 8 Sep at Foo's request ("the error message for my module
  /// change it under the field") — 'currentPassword', 'newPassword', or
  /// 'confirmPassword'; null falls back to a single banner (should not
  /// happen in practice here, since every failure this screen can hit is
  /// tied to one of the three fields, but kept for consistency with the
  /// other password screens).
  String? fieldError;

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    isLoading = true;
    errorMessage = null;
    fieldError = null;
    notifyListeners();
    if (!Validators.passwordsMatch(newPassword, confirmPassword)) {
      isLoading = false;
      errorMessage = ProfileMessages.m18NewPasswordsDoNotMatch;
      fieldError = 'confirmPassword';
      notifyListeners();
      return false;
    }
    try {
      await _profileRepository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      // BUG FIX (8 Sep, same as RegisterVm's sendUsernameOtp): dispatch by
      // failure type/field so M16 (wrong current password) highlights the
      // Current Password field and M17 (weak new password) highlights the
      // New Password field, instead of both landing in one shared banner.
      // [InvalidCredentialsFailure] doesn't carry a field (see
      // failures.dart); [ValidationFailure] already does — the adapter
      // tags M17 as 'newPassword'.
      if (e is ValidationFailure) {
        fieldError = e.field;
      } else if (e is InvalidCredentialsFailure) {
        fieldError = 'currentPassword';
      } else {
        fieldError = null;
      }
      notifyListeners();
      return false;
    }
  }
}
