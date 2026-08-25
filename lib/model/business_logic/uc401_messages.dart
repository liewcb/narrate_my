/// UC401 Login Account — message catalog, copied VERBATIM from
/// `collab temporary workfile 33.pdf`.
library;

class Uc401Messages {
  Uc401Messages._();

  static const m1LoginSuccessful =
      "Login successful. Start enjoying your trip with NarrateMy.";

  static const m2OtpSent =
      "A one-time password (OTP) has been sent to your phone number. "
      "Please enter it within 5 minutes.";

  static const m3GoogleSignInFailed = "Unable to sign in with Google. Please try again.";

  static const m4AccountNotFound =
      "No account was found. Please check your login details or register a new account.";

  static const m5InvalidOrExpiredOtp =
      "The OTP entered is incorrect or has expired. Please try again.";

  static const m6InvalidCredentials = "The Username or password entered is incorrect.";

  static const m7AccountLocked =
      "Too many failed login attempts. Your account has been locked for 30 minutes. "
      "Please try again later or reset your password.";

  static const m8TooManyOtpRequests =
      "Too many OTP requests or verification attempts have been made. Please try again later.";
}
