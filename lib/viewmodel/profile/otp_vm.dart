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
/// FIXED 2 Sep (Foo: "after 5 attempts also will not block if the user
/// keys in the correct OTP"). Two separate bugs were behind that:
///
///  1. [showCaptcha] only ever gated [resend]. Nothing consulted it before
///     verifying, so the Verify button happily accepted a correct code
///     after any number of failures. [canAttempt] now gates [verify]
///     itself, and the screen disables the button on the same signal.
///  2. The counter was a plain instance field, so backing out of the OTP
///     screen and re-entering it built a fresh `OtpVm` with the count back
///     at zero — five failures could be reset by pressing Back. The count
///     now lives in [_failedByPhone], keyed by phone number and shared by
///     every `OtpVm` in the process.
///
/// Scope, stated honestly: [_failedByPhone] is in-memory, so a full app
/// restart still clears it. Surviving a restart means persisting the count
/// (server-side, next to `record_failed_login`, or in local storage) —
/// deliberately not done here, since the spec frames this counter as a
/// client-side abuse brake rather than an account-level lock like the
/// password lockout, which IS server-side and IS restart-proof.
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

  /// Failed-OTP counts keyed by E.164 phone number, shared across every
  /// [OtpVm] built during this app run — see the note on the class. Static
  /// so that leaving and re-entering the OTP screen for the SAME number
  /// resumes the same count instead of starting over.
  static final Map<String, int> _failedByPhone = <String, int>{};

  /// Test-only: lets a widget test start from a known state.
  @visibleForTesting
  static void resetAllAttemptCounters() => _failedByPhone.clear();

  int get failedAttempts => _failedByPhone[e164Phone] ?? 0;

  bool get showCaptcha => failedAttempts >= Module5Constants.maxFailedOtpAttempts;

  /// False once the gate has tripped: [verify] refuses and the screen's
  /// Verify button goes dead until a CAPTCHA solve clears the count.
  bool get canAttempt => !showCaptcha;

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
    // REQ_501_12 / REQ_502_21: once five attempts have failed, no further
    // attempt is accepted until the CAPTCHA is solved — including a
    // CORRECT code. The screen also disables its Verify button on
    // [canAttempt], so reaching this guard means something bypassed the UI.
    if (!canAttempt) {
      errorMessage = _captchaRequiredMessage;
      notifyListeners();
      throw OtpFailure(_captchaRequiredMessage);
    }
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
      // A correct code clears the strike count for this number.
      _failedByPhone.remove(e164Phone);
      isVerifying = false;
      notifyListeners();
      return result;
    } on OtpFailure catch (e) {
      _failedByPhone[e164Phone] = failedAttempts + 1;
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

  /// Shown when an attempt is made while the CAPTCHA gate is up. Not a
  /// spec message (M1–M21 have no entry for this case — the spec describes
  /// the gate's behaviour but never gives copy for it), so it is written
  /// here rather than pulled from a message catalog.
  static const String _captchaRequiredMessage =
      'Too many incorrect codes. Complete the verification below before trying again.';

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
      _failedByPhone.remove(e164Phone);
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
