/// Custom failure classes for consistent error handling across the app.
abstract class Failure {
  final String message;
  Failure(this.message);
}

class NetworkFailure extends Failure {
  NetworkFailure([String message = "No Internet Connection"]) : super(message);
}

class ServerFailure extends Failure {
  ServerFailure([String message = "Server Error Occurred"]) : super(message);
}

class CacheFailure extends Failure {
  CacheFailure([String message = "Cache Error Occurred"]) : super(message);
}

// --- Module 5 (Auth + Profile) failures -----------------------------------
//
// Each of these maps directly to a UC400–403 alternative flow. ViewModels
// catch these (never a raw Exception) and read `.message` — which is
// always one of the verbatim spec messages from `uc40X_messages.dart` — to
// show the user, so the same failure type renders correctly no matter
// which screen threw it.

/// Base type for every Module 5 auth/profile failure. Lets a `catch (e)`
/// block distinguish "an auth-domain problem I have a specific message
/// for" from an unexpected error it should just rethrow/log.
abstract class AuthFailure extends Failure {
  AuthFailure(super.message);
}

/// UC401 A7 / UC400 A9 A10 A11 A14 style: the tourist's input was rejected
/// by a validation rule (bad phone format, weak password, mismatched
/// confirmation, username taken, etc). Carries an optional [field] so a
/// form can highlight the specific input, matching UC402 M4's "correct the
/// highlighted information."
class ValidationFailure extends AuthFailure {
  final String? field;
  ValidationFailure(super.message, {this.field});
}

/// UC401 A5 / UC403 A1: no account matches the given phone/username/Google
/// identity.
class AccountNotFoundFailure extends AuthFailure {
  AccountNotFoundFailure(super.message);
}

/// UC401 A7: the account was found, but the submitted password (or OTP,
/// for the OTP-based flows — see [OtpFailure] for the OTP-specific
/// variant) did not match.
class InvalidCredentialsFailure extends AuthFailure {
  InvalidCredentialsFailure(super.message);
}

/// UC401 A6 / UC400 A8 / UC403 A2: OTP was wrong or the 5-minute window
/// expired. [attemptsRemaining] lets the OTP screen show "2 attempts left
/// before verification is blocked" style copy before the CAPTCHA gate
/// trips at 5 (REQ_501_12 / REQ_502_21).
class OtpFailure extends AuthFailure {
  final int? attemptsRemaining;
  OtpFailure(super.message, {this.attemptsRemaining});
}

/// UC401 A8: 5 consecutive failed Username & Password attempts trip a
/// 30-minute lockout (REQ_502_17). [lockedUntil] lets the UI show a
/// countdown instead of a static message.
class LockedOutFailure extends AuthFailure {
  final DateTime? lockedUntil;
  LockedOutFailure(super.message, {this.lockedUntil});
}

/// UC400 A12 / UC401 A9 / UC403 A5: Supabase's own OTP volume/IP rate
/// limit rejected the request — REQ_501_10/11 deliberately says to rely on
/// Supabase's built-in limiting rather than a custom one, so this failure
/// is just surfacing what Supabase already returned.
class RateLimitedFailure extends AuthFailure {
  RateLimitedFailure(super.message);
}

/// UC402 A8: the Supabase session expired/was revoked server-side
/// mid-use. The screen that catches this should invoke UC401 Login,
/// exactly as the spec's alt-flow return-target says.
class SessionExpiredFailure extends AuthFailure {
  SessionExpiredFailure(super.message);
}

/// UC402 A7: the section's UPDATE was sent but Supabase failed to persist
/// it (network drop mid-request, RLS rejection, constraint violation,
/// etc). Distinct from [ValidationFailure] — the input was fine, the save
/// itself failed — because UC402 A7's retry target is "resubmit the same
/// values," not "go fix the form."
class ProfileUpdateFailure extends AuthFailure {
  ProfileUpdateFailure(super.message);
}

/// UC402 A21: blocks unlinking the only remaining login method on an
/// account (would otherwise leave the tourist unable to sign back in).
class NoRemainingLoginMethodFailure extends AuthFailure {
  NoRemainingLoginMethodFailure(super.message);
}

/// UC400 A11 / UC402 A9: the phone number being registered/added is
/// already linked to a different account.
class PhoneAlreadyRegisteredFailure extends AuthFailure {
  PhoneAlreadyRegisteredFailure(super.message);
}

/// UC400 A9: the chosen username is already taken.
class UsernameTakenFailure extends AuthFailure {
  UsernameTakenFailure(super.message);
}

/// UC400 A5 / UC401 A4 / UC402 A5 (Google linking): Google Sign-In failed,
/// was cancelled, or (for linking) the Google identity is already linked
/// to a different NarrateMy account (UC402 M14).
class GoogleSignInFailure extends AuthFailure {
  GoogleSignInFailure(super.message);
}

/// Fallback for an unexpected Supabase/server error encountered mid-flow
/// that isn't a rate limit, an invalid OTP, or any of the other specific
/// cases above (e.g. an OTP send request failing for some other reason).
/// Kept as an [AuthFailure] — rather than the generic [ServerFailure] —
/// so it's still caught by every ViewModel's `on AuthFailure catch (e)`
/// handler instead of slipping past uncaught.
class UnexpectedAuthFailure extends AuthFailure {
  UnexpectedAuthFailure(super.message);
}