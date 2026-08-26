import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

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

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    if (!Validators.passwordsMatch(newPassword, confirmPassword)) {
      isLoading = false;
      errorMessage = ProfileMessages.m18NewPasswordsDoNotMatch;
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
      notifyListeners();
      return false;
    }
  }
}
