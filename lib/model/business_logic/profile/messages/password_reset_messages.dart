/// UC403 Reset Password — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`.
///
/// RENAMED (per team format, 25 Aug): was `Uc403Messages` in
/// `uc403_messages.dart` — message catalogs are named by what they're for,
/// not by UC number, so this no longer needs to correspond to your UC.
///
/// TRANSLATED (UC402 A4 / REQ_201_2–5): see the doc comment in
/// `register_messages.dart` — same getter-over-`AppLocalizations.t()`
/// pattern, zero impact on call sites.
library;

import '../../../../core/localization/app_localizations.dart';

class PasswordResetMessages {
  PasswordResetMessages._();

  static String get m1EnterPhone => AppLocalizations.t('passwordReset.m1');

  static String get m2OtpSent => AppLocalizations.t('passwordReset.m2');

  static String get m3ResetSuccessfully => AppLocalizations.t('passwordReset.m3');

  static String get m4PhoneNotRegistered => AppLocalizations.t('passwordReset.m4');

  static String get m5InvalidOrExpiredOtp => AppLocalizations.t('passwordReset.m5');

  static String get m6InvalidPassword => AppLocalizations.t('passwordReset.m6');

  static String get m7PasswordsDoNotMatch => AppLocalizations.t('passwordReset.m7');

  static String get m8TooManyRequests => AppLocalizations.t('passwordReset.m8');
}
