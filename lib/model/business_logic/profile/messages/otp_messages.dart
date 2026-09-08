/// Shared across every OTP-driven flow (UC400 A2/A3, UC401 A2, UC403) —
/// added at Foo's request, NOT verbatim spec text.
///
/// BUG FIX ("some of the error message have half english there", 8 Sep):
/// these three strings used to be hardcoded English literals built
/// directly into `OtpVm`/`profile_adapter.dart`. The failure message they
/// got appended to (or replaced) WAS properly translated, so the tourist
/// would see a sentence that mixed languages — e.g. a Chinese OTP error
/// with an English " 4 attempts remaining." tacked onto the end. Moving
/// these into the same getter-over-`AppLocalizations.t()` pattern as every
/// other message catalog fixes that.
library;

import '../../../../core/localization/app_localizations.dart';

class OtpMessages {
  OtpMessages._();

  /// Appended to an OTP failure message when attempts remain. Contains a
  /// literal `{n}` placeholder — callers must `.replaceAll('{n}', ...)`
  /// with the actual remaining-attempts count before display.
  static String get attemptsRemainingTemplate => AppLocalizations.t('otp.attemptsRemaining');

  /// Shown when a verify/resend is attempted while the 5-failed-attempts
  /// CAPTCHA gate (REQ_501_12 / REQ_502_21) is up.
  static String get tooManyIncorrectCodes => AppLocalizations.t('otp.tooManyIncorrectCodes');

  /// Shown when the `verify-captcha` Edge Function call itself fails, or
  /// returns `success: false`.
  static String get captchaVerificationFailed =>
      AppLocalizations.t('otp.captchaVerificationFailed');
}
