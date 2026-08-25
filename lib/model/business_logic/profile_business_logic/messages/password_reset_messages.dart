/// UC403 Reset Password — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`.
///
/// RENAMED (per team format, 25 Aug): was `Uc403Messages` in
/// `uc403_messages.dart` — message catalogs are named by what they're for,
/// not by UC number, so this no longer needs to correspond to your UC.
library;

class PasswordResetMessages {
  PasswordResetMessages._();

  static const m1EnterPhone = "Enter your registered phone number to reset your password.";

  static const m2OtpSent =
      "A one-time password (OTP) has been sent to your phone number. "
      "Please enter it within 5 minutes.";

  static const m3ResetSuccessfully = "Your password has been reset successfully. You may now log in.";

  static const m4PhoneNotRegistered = "This phone number is not registered.";

  static const m5InvalidOrExpiredOtp =
      "The OTP entered is incorrect or has expired. Please try again.";

  static const m6InvalidPassword =
      "Password must contain at least 8 characters, including at least one letter and one number.";

  static const m7PasswordsDoNotMatch = "The passwords entered do not match. Please try again.";

  static const m8TooManyRequests = "Too many requests. Please try again later.";
}
