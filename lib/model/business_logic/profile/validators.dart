/// Input validation shared by every UC400–403 screen. Kept as pure
/// functions (no Flutter/Supabase imports) so viewmodels and, later, unit
/// tests can call them without any widget or network context.
library;

class Validators {
  Validators._();

  /// C1 (UC400): phone numbers must follow E.164 — a leading `+`, country
  /// code, then 1–14 more digits, no spaces/dashes/parens. The Register
  /// screen's country-code chip + local-number field should be concatenated
  /// into one E.164 string (e.g. `+60123456789`) before calling this.
  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{1,14}$');

  static bool isValidPhone(String phone) => _e164.hasMatch(phone.trim());

  /// C2 (UC400) / REQ_504_5 / REQ_503_19: at least 8 characters, at least
  /// one letter, at least one number. No other complexity rule is in the
  /// spec — don't invent extra requirements (symbols, casing) beyond this.
  static bool isValidPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasNumber;
  }

  static bool passwordsMatch(String password, String confirmation) =>
      password == confirmation;

  /// REQ_501_14: username uniqueness itself can only be checked against
  /// the database (see `resolve_username` RPC) — this only validates the
  /// *format* is reasonable before that round trip. Spec doesn't define an
  /// explicit format rule beyond uniqueness, so this applies a conservative,
  /// common-sense shape: 3–20 chars, letters/numbers/underscore, must start
  /// with a letter.
  static final RegExp _username = RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,19}$');

  static bool isValidUsernameFormat(String username) =>
      _username.hasMatch(username.trim());

  /// OTP entry — Supabase phone OTPs are 6 digits by default.
  static bool isValidOtpFormat(String otp) =>
      RegExp(r'^\d{6}$').hasMatch(otp.trim());

  static bool isNotEmpty(String value) => value.trim().isNotEmpty;
}
