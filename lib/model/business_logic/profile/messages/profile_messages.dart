/// UC402 Manage User Profile — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`. (M1–M21 all confirmed directly
/// against the spec text — none of these are approximations.)
///
/// RENAMED (per team format, 25 Aug): was `Uc402Messages` in
/// `uc402_messages.dart` — message catalogs are named by what they're for,
/// not by UC number, so this no longer needs to correspond to your UC.
///
/// TRANSLATED (UC402 A4 / REQ_201_2–5): see the doc comment in
/// `register_messages.dart` — same getter-over-`AppLocalizations.t()`
/// pattern, zero impact on call sites.
library;

import '../../../../core/localization/app_localizations.dart';

class ProfileMessages {
  ProfileMessages._();

  static String get m1ScreenSubtitle => AppLocalizations.t('profile.m1');

  static String get m2UpdatedSuccessfully => AppLocalizations.t('profile.m2');

  static String get m3UnableToLoad => AppLocalizations.t('profile.m3');

  static String get m4CorrectHighlighted => AppLocalizations.t('profile.m4');

  static String get m5ChangesDiscarded => AppLocalizations.t('profile.m5');

  static String get m6UnableToUpdate => AppLocalizations.t('profile.m6');

  static String get m7SessionExpired => AppLocalizations.t('profile.m7');

  static String get m8InvalidPhoneFormat => AppLocalizations.t('profile.m8');

  static String get m9PhoneAlreadyRegistered => AppLocalizations.t('profile.m9');

  static String get m10InvalidOrExpiredOtp => AppLocalizations.t('profile.m10');

  static String get m11OtpSent => AppLocalizations.t('profile.m11');

  static String get m12GoogleLinkedSuccessfully => AppLocalizations.t('profile.m12');

  static String get m13UnableToLinkGoogle => AppLocalizations.t('profile.m13');

  static String get m14GoogleAlreadyLinked => AppLocalizations.t('profile.m14');

  static String get m15PasswordChangedSuccessfully => AppLocalizations.t('profile.m15');

  static String get m16CurrentPasswordIncorrect => AppLocalizations.t('profile.m16');

  static String get m17InvalidPassword => AppLocalizations.t('profile.m17');

  static String get m18NewPasswordsDoNotMatch => AppLocalizations.t('profile.m18');

  static String get m19ConfirmUnlinkGoogle => AppLocalizations.t('profile.m19');

  static String get m20GoogleUnlinked => AppLocalizations.t('profile.m20');

  static String get m21MustVerifyPhoneBeforeUnlink => AppLocalizations.t('profile.m21');

  // --- Added at Foo's request — NOT in the spec text, so NOT verbatim
  // against `collab temporary workfile 33.pdf` like M1–M21 above. Account
  // deletion and profile-picture upload are app-level CRUD-completeness
  // additions, not written requirements.

  static String get m22ConfirmDeleteAccount => AppLocalizations.t('profile.m22');

  static String get m23AccountDeleted => AppLocalizations.t('profile.m23');

  static String get m24UnableToDeleteAccount => AppLocalizations.t('profile.m24');

  static String get m25UnableToUpdatePhoto => AppLocalizations.t('profile.m25');

  // Added 8 Sep at Foo's request — "add username and password afterward"
  // for phone-OTP/Google-only accounts, not in the spec's M1-M21.
  static String get m26UsernamePasswordSet => AppLocalizations.t('profile.m26');

  // Added 8 Sep at Foo's request ("since add the password now ... so
  // changes the error message when user unlink the only verification
  // method") — M21 above is kept verbatim as the spec's original wording
  // (phone-only), but since a password now also counts as a valid
  // alternative login method, the guard's actual message uses this
  // updated text instead. See profile_adapter.dart's unlink guard.
  static String get m27MustHaveAnotherLoginMethod => AppLocalizations.t('profile.m27');
}
