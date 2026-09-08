import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/register_messages.dart';
import '../../model/business_logic/profile/validators.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile/profile_adapter.dart';
import '../../model/repositories/interfaces/profile/profile_repository.dart';

/// Added at Foo's request — NOT in the written spec ("so shall i follow
/// the normal apps, do add the user can add username and password
/// afterward??", 8 Sep). Backs the new "Set Username & Password" screen
/// for an account that currently has no password
/// (`profile.hasPassword == false` — signed up via phone-OTP or Google
/// only). Local validation mirrors `RegisterVm.sendUsernameOtp`'s
/// Username-tab checks exactly (same messages, same order); the actual
/// save then goes straight onto the already-authenticated session instead
/// of through OTP-gated registration.
class SetPasswordVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  SetPasswordVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  /// 'username' or 'password' — which field the current [errorMessage]
  /// belongs to, so the screen can show it under the right field instead
  /// of a single ambiguous banner.
  String? fieldError;

  Future<Profile?> submit({
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    isLoading = true;
    errorMessage = null;
    fieldError = null;
    notifyListeners();
    if (!Validators.isNotEmpty(username) || !Validators.isValidUsernameFormat(username)) {
      isLoading = false;
      errorMessage = RegisterMessages.m15UsernameRequired;
      fieldError = 'username';
      notifyListeners();
      return null;
    }
    if (!Validators.isValidPassword(password)) {
      isLoading = false;
      errorMessage = RegisterMessages.m8InvalidPassword;
      fieldError = 'password';
      notifyListeners();
      return null;
    }
    if (!Validators.passwordsMatch(password, confirmPassword)) {
      isLoading = false;
      errorMessage = RegisterMessages.m10PasswordsDoNotMatch;
      fieldError = 'password';
      notifyListeners();
      return null;
    }
    try {
      final profile = await _profileRepository.setUsernameAndPassword(
        username: username.trim(),
        password: password,
      );
      isLoading = false;
      notifyListeners();
      return profile;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      fieldError = e is ValidationFailure ? e.field : 'username';
      notifyListeners();
      return null;
    }
  }
}
