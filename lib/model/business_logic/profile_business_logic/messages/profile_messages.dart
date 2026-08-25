/// UC402 Manage User Profile — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`. (M1–M21 all confirmed directly
/// against the spec text — none of these are approximations.)
///
/// RENAMED (per team format, 25 Aug): was `Uc402Messages` in
/// `uc402_messages.dart` — message catalogs are named by what they're for,
/// not by UC number, so this no longer needs to correspond to your UC.
library;

class ProfileMessages {
  ProfileMessages._();

  static const m1ScreenSubtitle = "Manage your profile, preferences, and preferred language.";

  static const m2UpdatedSuccessfully = "Your profile has been updated successfully.";

  static const m3UnableToLoad = "Unable to load your profile. Please try again.";

  static const m4CorrectHighlighted =
      "Please correct the highlighted information before continuing.";

  static const m5ChangesDiscarded = "Your changes have been discarded.";

  static const m6UnableToUpdate = "Unable to update your profile. Please try again.";

  static const m7SessionExpired = "Your session has expired. Please log in again.";

  static const m8InvalidPhoneFormat = "Please enter a valid phone number.";

  static const m9PhoneAlreadyRegistered =
      "This phone number is already registered to another account.";

  static const m10InvalidOrExpiredOtp =
      "The OTP entered is incorrect or has expired. Please try again.";

  static const m11OtpSent =
      "A one-time password (OTP) has been sent to your phone number. "
      "Please enter it within 5 minutes.";

  static const m12GoogleLinkedSuccessfully =
      "Your Google account has been linked successfully. You can now sign in with Google.";

  static const m13UnableToLinkGoogle = "Unable to link your Google account. Please try again.";

  static const m14GoogleAlreadyLinked =
      "This Google account is already linked to another NarrateMy account.";

  static const m15PasswordChangedSuccessfully = "Your password has been changed successfully.";

  static const m16CurrentPasswordIncorrect = "The current password entered is incorrect.";

  static const m17InvalidPassword =
      "Password must contain at least 8 characters, including at least one letter and one number.";

  static const m18NewPasswordsDoNotMatch = "The new passwords entered do not match.";

  static const m19ConfirmUnlinkGoogle =
      "Are you sure you want to unlink your Google account? "
      "You will no longer be able to sign in with Google.";

  static const m20GoogleUnlinked = "Your Google account has been unlinked.";

  static const m21MustVerifyPhoneBeforeUnlink =
      "You must verify a phone number before unlinking your Google account.";

  // --- Added at Foo's request — NOT in the spec text, so NOT verbatim
  // against `collab temporary workfile 33.pdf` like M1–M21 above. Account
  // deletion and profile-picture upload are app-level CRUD-completeness
  // additions, not written requirements.

  static const m22ConfirmDeleteAccount =
      "Delete your account? This permanently removes your profile, "
      "preferences, and bookmarks, and cannot be undone.";

  static const m23AccountDeleted = "Your account has been deleted.";

  static const m24UnableToDeleteAccount =
      "Unable to delete your account. Please try again.";

  static const m25UnableToUpdatePhoto = "Unable to update your profile picture. Please try again.";
}
