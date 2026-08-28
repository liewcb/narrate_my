/// UC401 Login Account — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`.
///
/// RENAMED (per team format, 25 Aug): was `Uc401Messages` in
/// `uc401_messages.dart` — message catalogs are named by what they're for,
/// not by UC number, so this no longer needs to correspond to your UC.
///
/// TRANSLATED (UC402 A4 / REQ_201_2–5): see the doc comment in
/// `register_messages.dart` — same getter-over-`AppLocalizations.t()`
/// pattern, zero impact on call sites.
library;

import '../../../../core/localization/app_localizations.dart';

class LoginMessages {
  LoginMessages._();

  static String get m1LoginSuccessful => AppLocalizations.t('login.m1');

  static String get m2OtpSent => AppLocalizations.t('login.m2');

  static String get m3GoogleSignInFailed => AppLocalizations.t('login.m3');

  static String get m4AccountNotFound => AppLocalizations.t('login.m4');

  static String get m5InvalidOrExpiredOtp => AppLocalizations.t('login.m5');

  static String get m6InvalidCredentials => AppLocalizations.t('login.m6');

  static String get m7AccountLocked => AppLocalizations.t('login.m7');

  static String get m8TooManyOtpRequests => AppLocalizations.t('login.m8');
}
