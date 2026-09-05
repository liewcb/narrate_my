import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/login_messages.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Backs UC401 Login Account — Google (A1), phone+OTP (A2), and
/// Username & Password (A3).
class LoginVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  LoginVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  /// Which of the screen's two tabs (or the shared Google button) this
  /// [errorMessage] belongs to — 'phone', 'username', or 'google'. Phone
  /// and Username are two separate forms sharing one `LoginVm`/`TabBarView`,
  /// so without this tag a phone-tab error would also render under the
  /// Username tab (and vice versa) since both were just reading the same
  /// unscoped `errorMessage`. The screen should only display
  /// [errorMessage] where [fieldError] matches that section.
  String? fieldError;

  /// Set only for [LockedOutFailure] (UC401 A8, REQ_502_17) so the screen
  /// can show a countdown instead of a static banner.
  DateTime? lockedUntil;

  void _startSubmit() {
    isLoading = true;
    errorMessage = null;
    fieldError = null;
    lockedUntil = null;
    notifyListeners();
  }

  /// UC401 A1.
  Future<Profile?> signInWithGoogle() async {
    _startSubmit();
    try {
      final profile = await _profileRepository.loginWithGoogle();
      isLoading = false;
      notifyListeners();
      return profile;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      fieldError = 'google';
      notifyListeners();
      return null;
    } catch (_) {
      isLoading = false;
      errorMessage = LoginMessages.m3GoogleSignInFailed;
      fieldError = 'google';
      notifyListeners();
      return null;
    }
  }

  /// UC401 A2, steps 1–3. On success the screen navigates to the OTP screen
  /// with `OtpFlow.loginPhone` and this same [e164Phone].
  Future<bool> sendPhoneOtp(String e164Phone) async {
    _startSubmit();
    try {
      await _profileRepository.sendPhoneLoginOtp(e164Phone);
      isLoading = false;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      fieldError = 'phone';
      notifyListeners();
      return false;
    }
  }

  /// UC401 A3. Returns the logged-in [Profile] on success, or null with
  /// [errorMessage] (and possibly [lockedUntil]) set on failure.
  Future<Profile?> loginWithUsernamePassword({
    required String username,
    required String password,
  }) async {
    _startSubmit();
    try {
      final profile = await _profileRepository.loginWithUsernamePassword(
        username: username,
        password: password,
      );
      isLoading = false;
      notifyListeners();
      return profile;
    } on LockedOutFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      fieldError = 'username';
      lockedUntil = e.lockedUntil;
      notifyListeners();
      return null;
    } on AuthFailure catch (e) {
      isLoading = false;
      errorMessage = e.message;
      fieldError = 'username';
      notifyListeners();
      return null;
    }
  }
}
