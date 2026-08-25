import 'dart:typed_data';

import '../../entities/bookmark.dart';
import '../../entities/preferences.dart';
import '../../entities/profile.dart';

/// UC400 Register, UC401 Login, UC402 Manage User Profile, and UC403 Reset
/// Password — all in one repository, matching the team's architecture
/// diagram (exactly one Repository/RepositoryAdapter per module, no
/// separate AuthRepository). Merged from a former AuthRepository/
/// ProfileRepository split on 25 Aug at Foo's request, once the diagram
/// comparison showed the split wasn't how the team drew it — see
/// `module5-handover.md`'s "Architecture diagram vs. code" note for the
/// history and why the split existed in the first place (it was added
/// when Delete Account was built).
///
/// Every method throws a typed subclass of `AuthFailure`
/// (`lib/core/errors/failures.dart`) whose `.message` is always one of the
/// verbatim spec messages from `uc40X_messages.dart` — callers (ViewModels)
/// should never need to construct their own error text.
abstract class ProfileRepository {
  // --- Registration (UC400) ------------------------------------------------

  /// UC400 A1. Opens the Google OAuth flow. On success, if the Google
  /// identity is already registered (A6), signs into the EXISTING account
  /// instead of creating a duplicate — matches spec exactly ("does not
  /// create a duplicate account... signs the tourist into the existing
  /// account"). Returns the resulting profile either way.
  Future<Profile> registerOrSignInWithGoogle();

  /// UC400 A2 steps 1–4: validates phone format (A7) and that it isn't
  /// already registered (A11), then sends the OTP.
  Future<void> sendPhoneRegistrationOtp(String e164Phone);

  /// UC400 A2 steps 6–9: verifies the OTP (A8) and creates the account.
  Future<Profile> verifyPhoneRegistrationOtp({
    required String e164Phone,
    required String otp,
  });

  /// UC400 A3 steps 1–6: validates username availability (A9), password
  /// complexity (A10) and confirmation match (A14), and phone not already
  /// registered (A11), then sends the OTP.
  Future<void> sendUsernameRegistrationOtp({
    required String username,
    required String password,
    required String e164Phone,
  });

  /// UC400 A3 steps 8–11: verifies the OTP (A8), creates the account with
  /// phone+password, and persists [username] onto the profile row.
  Future<Profile> verifyUsernameRegistrationOtp({
    required String username,
    required String e164Phone,
    required String otp,
  });

  // --- Login (UC401) --------------------------------------------------------

  /// UC401 A1. A4 (failed/cancelled) surfaces as [GoogleSignInFailure].
  Future<Profile> loginWithGoogle();

  /// UC401 A2 steps 1–3: verifies the phone IS registered (A5), then sends
  /// the OTP.
  Future<void> sendPhoneLoginOtp(String e164Phone);

  /// UC401 A2 steps 5–6: verifies the OTP (A6).
  Future<Profile> verifyPhoneLoginOtp({
    required String e164Phone,
    required String otp,
  });

  /// UC401 A3: checks lockout (A8) before attempting, validates credentials
  /// (A7), resets the failed-attempt counter on success (REQ_502_18).
  Future<Profile> loginWithUsernamePassword({
    required String username,
    required String password,
  });

  /// Shared OTP resend for any of the flows above, subject to the 2-minute
  /// cooldown (C3) — cooldown timing itself is tracked by the OTP
  /// ViewModel; this just re-issues the send.
  Future<void> resendOtp(String e164Phone);

  /// UC400 A8 / REQ_501_12 / REQ_502_21: after 5 consecutive failed OTP
  /// attempts, [token] (from the hCaptcha widget) must verify successfully
  /// — via the `verify-captcha` Supabase Edge Function, which holds the
  /// hCaptcha SECRET key server-side — before another OTP resend/re-entry
  /// is allowed. Throws on a failed/invalid solve.
  Future<void> verifyCaptcha(String token);

  // --- Reset Password (UC403) -----------------------------------------------

  /// Basic Flow steps 3–6: verifies the phone belongs to a Username &
  /// Password account (A1), applies OTP rate limiting (A5), sends the OTP.
  Future<void> sendPasswordResetOtp(String e164Phone);

  /// Basic Flow steps 8–10 (A2): verifies the OTP. Per the spec's own step
  /// ordering, this authenticates the tourist (proving phone ownership)
  /// BEFORE the new-password fields are ever shown — [resetPassword] below
  /// then runs against that now-authenticated session, not a bare token.
  Future<void> verifyPasswordResetOtp({
    required String e164Phone,
    required String otp,
  });

  /// Basic Flow steps 11–13 (A3 weak password, A4 mismatch): sets the new
  /// password on the session established by [verifyPasswordResetOtp], and
  /// clears any existing login lockout (REQ_502_19).
  Future<void> resetPassword(String newPassword);

  // --- Profile retrieval / editing (UC402) ------------------------------------

  /// Basic Flow step 2 / A1: loads the current section values, pre-filled
  /// for editing. Throws [SessionExpiredFailure] if there is no active
  /// session (A8).
  Future<Profile> fetchProfile();

  /// UC402 A2 steps 3–8 (REQ_503_3): saves full name + bio as their own
  /// atomic update. Does NOT touch phone/password/Google linking — see
  /// the Personal Info sub-flows below.
  Future<Profile> updatePersonalInfo({String? fullName, String? bio});

  /// UC402 A3 step 1: loads the current preference values, pre-filled.
  Future<Preferences> fetchPreferences();

  /// UC402 A3 steps 3–5 (REQ_503_11): saves ALL five preference categories
  /// as one atomic update to the `preferences` row — still independent
  /// from Personal Info and Language, which live on a different table/
  /// different columns entirely.
  Future<void> updatePreferences(Preferences preferences);

  /// UC402 A4 (REQ_503_9, REQ_503_11): saves the selected language as its
  /// own atomic update to `profiles.preferred_language`.
  Future<void> updateLanguage(String languageCode);

  /// UC402 A22 step 2 (REQ_503_21).
  Future<List<Bookmark>> fetchBookmarks();

  /// UC402 A22 steps 5–7 (REQ_503_22).
  Future<void> removeBookmark(String bookmarkId);

  // --- Personal Info sub-flows (UC402) ----------------------------------------
  //
  // These operate on `auth.users` via the Supabase Auth SDK (OTP
  // re-verification / session reauthentication), not the `profiles` table
  // — kept as their own methods rather than folded into
  // [updatePersonalInfo], even though they're triggered from the same
  // Personal Info screen.

  /// UC402 A9 steps 1–4: validates format (A10) and that [newE164Phone]
  /// isn't already linked to a different account (A11), then sends an OTP
  /// to the NEW number. Verified via the shared `OtpVm`
  /// (`OtpFlow.changePhone`), which calls [verifyPhoneChangeOtp].
  Future<void> sendPhoneChangeOtp(String newE164Phone);

  /// UC402 A9 steps 6–9 (A12 invalid/expired): verifies the OTP and commits
  /// the new phone number onto the current session's `auth.users` row.
  Future<void> verifyPhoneChangeOtp({
    required String newE164Phone,
    required String otp,
  });

  /// UC402 A16–A18 (C6): changes the password for an account that already
  /// has one, verifying [currentPassword] first (M16) rather than an OTP,
  /// since the tourist is already authenticated via an active session.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// UC402 A13 (C5): links a Google account to the currently authenticated
  /// session. Only valid when the account has no Google identity linked
  /// yet — the screen shouldn't offer this action otherwise, but the
  /// adapter guards it too (M14 if the caller does anyway, or if the
  /// Google identity turns out to already be linked to a DIFFERENT
  /// account, per REQ_503_16's "verifying the Google identity is not
  /// already linked").
  Future<Profile> linkGoogleAccount();

  /// UC402 A20/A21 (C5): unlinks the currently-linked Google account.
  /// Throws [NoRemainingLoginMethodFailure] (M21) if this would leave the
  /// account with no other valid login method (REQ_503_20) — checked
  /// before the caller even shows the confirmation prompt (M19), matching
  /// the spec's own step ordering (A20 step 2 precedes step 3).
  Future<void> unlinkGoogleAccount();

  // --- Added at Foo's request — NOT in the written spec ---------------------

  /// Uploads [bytes] (already picked/read by the caller — this repository
  /// has no knowledge of image pickers or platform APIs) to Storage and
  /// saves the resulting URL as its own atomic update to
  /// `profiles.avatar_url`, same column-scoped pattern as every other save
  /// here. [fileExt] (e.g. `jpg`, `png`) becomes part of the storage path.
  Future<Profile> updateAvatar({required Uint8List bytes, required String fileExt});

  /// One-time step, not an editable Personal Info field: saves the
  /// mandatory Name + Date of Birth collected immediately after
  /// registration. Also a column-scoped atomic update
  /// (`full_name` + `date_of_birth`), separate from [updatePersonalInfo]'s
  /// `full_name` + `bio` so REQ_503_11's independent-atomic-save pattern
  /// stays consistent even for this added flow.
  Future<Profile> completeMandatoryDetails({
    required String fullName,
    required DateTime dateOfBirth,
  });

  /// Permanently deletes the tourist's `auth.users` row, which cascades to
  /// their `profiles`/`preferences`/`bookmarks` rows too (see
  /// `0006_delete_account_and_dob.sql`). Irreversible; the caller must
  /// confirm with the tourist before calling this. The session is no
  /// longer valid after this succeeds — the caller should treat it like a
  /// logout (no separate [logout] call is needed/possible against a
  /// deleted user).
  Future<void> deleteAccount();

  // --- Session ---------------------------------------------------------------

  Future<void> logout();

  bool get isLoggedIn;

  /// Emits whenever the Supabase auth session changes (sign in/out, token
  /// refresh) — the auth-gate widget listens to this to decide whether to
  /// show the auth flow or the main app shell.
  Stream<bool> get authStateChanges;
}
