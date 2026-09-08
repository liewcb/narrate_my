import 'package:flutter/foundation.dart';

import '../../core/errors/failures.dart';
import '../../model/business_logic/profile/messages/login_messages.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile/profile_adapter.dart';
import '../../model/repositories/interfaces/profile/profile_repository.dart';

/// Backs UC401 Login Account — Google (A1), phone+OTP (A2), and
/// Username & Password (A3).
class LoginVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  LoginVm({ProfileRepository? profileRepository})
      : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter();

  bool isLoading = false;
  String? errorMessage;

  /// Which tab/field [errorMessage] belongs to ('phone', 'username', or
  /// 'google') — without this, a Phone-tab error and a Username-tab error
  /// were indistinguishable to the screen, so an error from one tab was
  /// rendered under BOTH tabs' fields. The screen must check this before
  /// showing [errorMessage] under any particular field.
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

  /// Added at Foo's request — NOT in the written spec. Call when the screen
  /// detects the app returning to the foreground with [isLoading] still
  /// true and no session ever arrived (the tourist backed out of Google's
  /// account chooser). Ends the wait immediately — [signInWithGoogle]'s own
  /// `catch` above then reports it the same way any other Google failure
  /// would.
  void cancelGoogleSignIn() => _profileRepository.cancelPendingGoogleAuth();

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
    // BUG FIX (6 Sep, Foo: "even empty also will show ... no account was
    // found"): submitting with either field blank went straight to the
    // network and came back reading like a real (if wrong) account
    // lookup, when nothing was actually looked up. Checked locally first,
    // same as Register's Username tab.
    if (username.trim().isEmpty || password.isEmpty) {
      isLoading = false;
      errorMessage = LoginMessages.m9UsernameAndPasswordRequired;
      fieldError = 'username';
      notifyListeners();
      return null;
    }
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
