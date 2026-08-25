/// Module 5 (User Profile & Language Management) constants — the numeric
/// and enumerated rules pulled directly from the locked FR/UC spec
/// (REQ_501–504), so they live in ONE place instead of being repeated as
/// magic numbers across viewmodels.
///
/// NOTE: this repo also has `lib/core/utils/app_constants.dart` (an older,
/// unrelated file holding a generic `appName`/`defaultPadding`/`apiTimeout`
/// trio used elsewhere). That file is left untouched — other modules may
/// depend on it. This file is specifically Module 5's rulebook; the
/// duplication is a pre-existing scaffold quirk, not something introduced
/// here. Worth the team consolidating later, not touched now to avoid
/// breaking other modules' imports.
library;

class Module5Constants {
  Module5Constants._();

  // --- OTP (REQ_501_6, REQ_501_9, C3 across UC400/401/403) ---
  static const otpValidityMinutes = 5;
  static const otpResendCooldownMinutes = 2;

  // --- Login lockout (REQ_502_17, REQ_502_22) ---
  static const maxFailedLoginAttempts = 5;
  static const lockoutDurationMinutes = 30;

  // --- OTP abuse / CAPTCHA (REQ_501_12, REQ_502_21) ---
  static const maxFailedOtpAttempts = 5;

  // --- Password complexity (REQ_501_13, REQ_504_5, REQ_503_19) ---
  static const passwordMinLength = 8;

  // --- Session (REQ_502_14) ---
  static const sessionInactivityDays = 60;

  // --- Supported languages (C2 of UC402 — spec's official list) ---
  // Keys are ISO 639-1 codes stored in `profiles.preferred_language`.
  static const supportedLanguages = <String, LanguageOption>{
    'en': LanguageOption(code: 'en', englishName: 'English', nativeName: 'English'),
    'zh': LanguageOption(code: 'zh', englishName: 'Mandarin', nativeName: '中文'),
    'ms': LanguageOption(code: 'ms', englishName: 'Malay', nativeName: 'Bahasa Melayu'),
    'es': LanguageOption(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
    'hi': LanguageOption(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
  };

  static const defaultLanguageCode = 'en';
}

class LanguageOption {
  final String code;
  final String englishName;
  final String nativeName;

  const LanguageOption({
    required this.code,
    required this.englishName,
    required this.nativeName,
  });
}
