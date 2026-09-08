/// Input validation shared by every UC400–403 screen. Kept as pure
/// functions (no Flutter/Supabase imports) so viewmodels and, later, unit
/// tests can call them without any widget or network context.
library;

class Validators {
  Validators._();

  /// C1 (UC400): phone numbers must follow E.164 — a leading `+`, country
  /// code, then more digits, no spaces/dashes/parens. The Register screen's
  /// country-code chip + local-number field should be concatenated into one
  /// E.164 string (e.g. `+60123456789`) before calling this.
  ///
  /// BUG FIX (6 Sep, Foo: "why 456 also can accept as a number"): the
  /// original `\d{1,14}` let through anything with as few as 2 total
  /// digits after the `+` — e.g. `+60456` (country code + 3 junk digits)
  /// matched. No real E.164 number is that short; requiring at least 8
  /// digits total after the `+` (still capped at the E.164 max of 15)
  /// rejects obviously-fake short input while still accepting every real
  /// country's numbers.
  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

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
  /// explicit format rule beyond uniqueness.
  ///
  /// RELAXED (8 Sep, Foo: "for the username i want can symbol but no need
  /// strict like password, just ensure a 3-20 letter long and accept
  /// symbol tgen ok"): used to be a strict letter-start,
  /// alphanumeric/underscore-only regex (which is why e.g. "admin123@"
  /// was rejected). Now just a length check (3–20 chars) with symbols
  /// allowed — the only thing still disallowed is internal whitespace,
  /// since a username with spaces in it isn't practical to log in with.
  static bool isValidUsernameFormat(String username) {
    final trimmed = username.trim();
    if (trimmed.length < 3 || trimmed.length > 20) return false;
    if (trimmed.contains(RegExp(r'\s'))) return false;
    return true;
  }

  /// OTP entry — Supabase phone OTPs are 6 digits by default.
  static bool isValidOtpFormat(String otp) =>
      RegExp(r'^\d{6}$').hasMatch(otp.trim());

  static bool isNotEmpty(String value) => value.trim().isNotEmpty;
}
