import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../model/entities/profile.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// Which of the four UC400/401/403 flows this OTP screen is verifying for.
/// A single `OtpScreen`/`OtpVm` pair is shared across all of them — only
/// which repository call [verify] makes, and what the screen does
/// afterwards, differs.
enum OtpFlow { registerPhone, registerUsername, loginPhone, resetPassword, changePhone }

/// Shared OTP-entry logic for UC400 A2/A3, UC401 A2, and UC403's middle
/// step. Owns the 5-minute-validity countdown is NOT tracked here (Supabase
/// enforces expiry server-side and returns [OtpFailure] on an expired
/// code — re-showing M6/M5's "incorrect or has expired" covers both cases
/// identically, matching the spec's own wording), the 2-minute resend
/// cooldown (C3, REQ_501_9), and the failed-attempt counter that gates the
/// CAPTCHA at 5 attempts (REQ_501_12/REQ_502_21 — the counter is
/// deliberately client-side/ephemeral per the spec's own framing).
///
/// NOTE: [showCaptcha] going true is currently a dead end — Phase 5 wires
/// an actual hCaptcha widget + `verify-captcha` Edge Function call in here
/// (gating [resend] on a solve). Until then this VM just stops offering
/// resend and leaves [showCaptcha] for the screen to render a placeholder.
class OtpVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  final OtpFlow flow;
  final String e164Phone;

  /// Only used for [OtpFlow.registerUsername] — the username chosen on the
  /// Register screen, applied to the profile once the OTP verifies.
  final String? pendingUsername;

  OtpVm({
    required this.flow,
    required this.e164Phone,
    this.pendingUsername,
    ProfileRepository? profileRepository,
  }) : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    assert(
      flow != OtpFlow.registerUsername || pendingUsername != null,
      'OtpFlow.registerUsername requires pendingUsername',
    );
    _startCooldown();
  }

  bool isVerifying = false;
  bool isResending = false;
  String? errorMessage;

  int failedAttempts = 0;
  bool get showCaptcha => failedAttempts >= Module5Constants.maxFailedOtpAttempts;

  int resendCooldownSeconds = Module5Constants.otpResendCooldownMinutes * 60;
  bool get canResend => resendCooldownSeconds <= 0 && !showCaptcha;
  Timer? _cooldownTimer;

  void _startCooldown() {
    resendCooldownSeconds = Module5Constants.otpResendCooldownMinutes * 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      resendCooldownSeconds--;
      if (resendCooldownSeconds <= 0) {
        timer.cancel();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Attempts to verify [code]. Returns the resulting [Profile] for the
  /// three flows that end in an authenticated session
  /// (registerPhone/registerUsername/loginPhone); for [OtpFlow.resetPassword]
  /// there is no profile yet (the tourist still needs to set a new
  /// password), so it returns null on success too — check [errorMessage]
  /// (still null) to distinguish "resetPassword succeeded" from a real
  /// failure.
  Future<Profile?> verify(String code) async {
    isVerifying = true;
    errorMessage = null;
    notifyListeners();
    try {
      Profile? result;
      switch (flow) {
        case OtpFlow.registerPhone:
          result = await _profileRepository.verifyPhoneRegistrationOtp(
            e164Phone: e164Phone,
            otp: code,
          );
          break;
        case OtpFlow.registerUsername:
          result = await _profileRepository.verifyUsernameRegistrationOtp(
            username: pendingUsername!,
            e164Phone: e164Phone,
            otp: code,
          );
          break;
        case OtpFlow.loginPhone:
          result = await _profileRepository.verifyPhoneLoginOtp(
            e164Phone: e164Phone,
            otp: code,
          );
          break;
        case OtpFlow.resetPassword:
          await _profileRepository.verifyPasswordResetOtp(e164Phone: e164Phone, otp: code);
          result = null;
          break;
        case OtpFlow.changePhone:
          await _profileRepository.verifyPhoneChangeOtp(newE164Phone: e164Phone, otp: code);
          result = null;
          break;
      }
      isVerifying = false;
      notifyListeners();
      return result;
    } on OtpFailure catch (e) {
      failedAttempts++;
      isVerifying = false;
      errorMessage = e.message;
      notifyListeners();
      rethrow;
    } on AuthFailure catch (e) {
      isVerifying = false;
      errorMessage = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// C3 / REQ_501_9: re-issues the OTP once the cooldown has elapsed.
  Future<bool> resend() async {
    if (!canResend) return false;
    isResending = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _profileRepository.resendOtp(e164Phone);
      isResending = false;
      _startCooldown();
      return true;
    } on AuthFailure catch (e) {
      isResending = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  /// REQ_501_12 / REQ_502_21: called once the hCaptcha widget reports a
  /// solved [token]. A successful verify resets [failedAttempts] to 0 —
  /// the spec only requires the CAPTCHA to gate the *next* resend/re-entry
  /// after tripping at 5, not a permanent lock, so clearing the counter
  /// lets the normal 5-strikes rule apply fresh rather than re-triggering
  /// on every attempt from here on.
  Future<bool> verifyCaptcha(String token) async {
    try {
      await _profileRepository.verifyCaptcha(token);
      failedAttempts = 0;
      errorMessage = null;
      notifyListeners();
      return true;
    } on AuthFailure catch (e) {
      errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
