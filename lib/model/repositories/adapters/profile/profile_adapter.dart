import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../../business_logic/profile/messages/login_messages.dart';
import '../../../business_logic/profile/messages/otp_messages.dart';
import '../../../business_logic/profile/messages/password_reset_messages.dart';
import '../../../business_logic/profile/messages/profile_messages.dart';
import '../../../business_logic/profile/messages/register_messages.dart';
import '../../../business_logic/profile/validators.dart';
import '../../../data_sources/remote/auth_remote_data_source.dart';
import '../../../data_sources/remote/profile_remote_data_source.dart';
import '../../../dto/preferences_dto.dart';
import '../../../entities/bookmark.dart';
import '../../../entities/preferences.dart';
import '../../../entities/profile.dart';
import '../../interfaces/profile/profile_repository.dart';

/// NOTE ON FILENAME: kept as `profile_adapter.dart` (not
/// `profile_repository_adapter.dart`) for the same reason as before the
/// 25 Aug merge — see the class doc comment.
///
/// Real Supabase-backed [ProfileRepository]. Merged from the former
/// `SupabaseAuthRepositoryAdapter` + `SupabaseProfileRepositoryAdapter`
/// split on 25 Aug, to match the team's architecture diagram (exactly one
/// Repository/RepositoryAdapter per module — see
/// `module5-handover.md`'s "Architecture diagram vs. code" note).
/// Internally still talks to two data sources — [AuthRemoteDataSource]
/// for `auth.users`-level operations, [ProfileRemoteDataSource] for
/// `profiles`/`preferences`/`bookmarks` table operations — that split is
/// an implementation detail below the diagram's Repository layer, not a
/// public contract; every method here is otherwise unchanged from the
/// two adapters it replaces.
///
/// IMPORTANT — not compiler/runtime-checked against a live Supabase
/// project from the sandbox this was written in (no Flutter SDK, no
/// network to your project). Exception-message pattern matching below
/// (`_looksLikeRateLimit` etc.) is best-effort based on Supabase's
/// documented/typical error text, NOT verified against a real response —
/// re-check these against your project's actual error messages once you
/// can hit real error paths.
class SupabaseProfileRepositoryAdapter implements ProfileRepository {
  final AuthRemoteDataSource _authDataSource;
  final ProfileRemoteDataSource _profileDataSource;

  /// Custom URL scheme the Google OAuth flow redirects back into the app
  /// on. Must be registered as a deep link (AndroidManifest.xml
  /// intent-filter / iOS URL scheme) AND added to Supabase Dashboard →
  /// Auth → URL Configuration → Redirect URLs.
  static const _googleRedirectUrl = 'io.supabase.narratemy://login-callback/';

  SupabaseProfileRepositoryAdapter({
    AuthRemoteDataSource? authDataSource,
    ProfileRemoteDataSource? profileDataSource,
  })  : _authDataSource = authDataSource ?? AuthRemoteDataSource(),
        _profileDataSource = profileDataSource ?? ProfileRemoteDataSource();

  /// BUG FIX (6 Sep, Foo: "when user log in with google then no phone
  /// number right, the change phone number shall become add phone
  /// number"): Supabase's `User.phone` is `''` (empty string), not `null`,
  /// when no phone identity exists — every `.toEntity(phone: ...)` call
  /// below was passing that empty string straight through, so
  /// Personal Info's `vm.profile?.phone == null` check was always false
  /// for a Google-only account and showed "Change"/the raw empty string
  /// instead of "Add"/"Not set".
  String? _normalizePhone(String? phone) => (phone == null || phone.isEmpty) ? null : phone;

  String _requireUserId() {
    final id = _profileDataSource.currentUserId;
    if (id == null) {
      // UC402 A8: no active session — the screen that catches this should
      // invoke UC401 Login, per the spec's alt-flow return-target.
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    return id;
  }

  // --- Registration ----------------------------------------------------------

  @override
  Future<Profile> registerOrSignInWithGoogle() => _googleSignIn();

  @override
  Future<Profile> loginWithGoogle() => _googleSignIn();

  @override
  void cancelPendingGoogleAuth() => _authDataSource.cancelPendingGoogleAuth();

  Future<Profile> _googleSignIn() async {
    try {
      await _authDataSource.signInWithGoogleAndAwaitSession(
        redirectTo: _googleRedirectUrl,
      );
      await _backfillFromGoogleIdentity();
      // Awaited deliberately so a failure fetching the profile row right
      // after sign-in is still caught here and mapped to
      // GoogleSignInFailure, rather than escaping uncaught.
      return await _fetchCurrentProfile();
    } catch (e) {
      // DIAGNOSTIC ("login page should bring in the Google account"
      // report): if this never completes, the two most likely causes are
      // on the Supabase side: (1) Authentication → Providers → Google
      // isn't configured with a real Client ID/Secret yet, or (2)
      // io.supabase.narratemy://login-callback/ isn't in Authentication →
      // URL Configuration → Redirect URLs (Supabase silently refuses to
      // hand the session back to a redirect URL it doesn't recognize,
      // which looks exactly like this call hanging until timeout). Check
      // the debug console next time this is tapped.
      debugPrint('signInWithGoogle failed: $e');
      throw GoogleSignInFailure(RegisterMessages.m3GoogleSignInFailed);
    }
  }

  /// A tourist who signs in with Google already told Google their name and
  /// picture, so asking for them again is busywork. Supabase copies the
  /// provider's claims onto `auth.users.user_metadata`; this lifts the two
  /// useful ones onto the `profiles` row.
  ///
  /// Only fills a column that is currently EMPTY, so it never overwrites a
  /// name the tourist edited or a photo they uploaded — which also makes
  /// it safe to run on every Google sign-in rather than only the first.
  ///
  /// Best-effort by design: wrapped so a failure here can never turn a
  /// perfectly good sign-in into GoogleSignInFailure. Google's key names
  /// differ by provider and have changed over time, so both spellings of
  /// each are checked.
  Future<void> _backfillFromGoogleIdentity() async {
    try {
      final user = _authDataSource.currentUser;
      if (user == null) return;
      final meta = user.userMetadata ?? const <String, dynamic>{};

      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = meta[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final googleName = pick(['full_name', 'name']);
      final googleAvatar = pick(['avatar_url', 'picture']);
      if (googleName == null && googleAvatar == null) return;

      final dto = await _profileDataSource.fetchProfileRow(user.id);
      final nameIsEmpty = dto.fullName == null || dto.fullName!.trim().isEmpty;
      final avatarIsEmpty = dto.avatarUrl == null || dto.avatarUrl!.trim().isEmpty;
      if (!nameIsEmpty && !avatarIsEmpty) return;

      await _profileDataSource.backfillOAuthProfile(
        user.id,
        fullName: nameIsEmpty ? googleName : null,
        avatarUrl: avatarIsEmpty ? googleAvatar : null,
      );
    } catch (e) {
      debugPrint('Google profile backfill skipped: $e');
    }
  }

  @override
  Future<void> sendPhoneRegistrationOtp(String e164Phone) async {
    if (!Validators.isValidPhone(e164Phone)) {
      throw ValidationFailure(RegisterMessages.m5InvalidPhoneFormat, field: 'phone');
    }
    final existing = await _authDataSource.phoneAccountStatus(e164Phone);
    if (existing != null) {
      throw PhoneAlreadyRegisteredFailure(RegisterMessages.m4PhoneAlreadyRegistered);
    }
    try {
      await _authDataSource.sendOtp(e164Phone, shouldCreateUser: true);
    } on AuthException catch (e) {
      // When the ONLY problem is that no SMS provider is configured/
      // reachable in this environment (not the phone number itself),
      // don't surface that to the tourist at all — proceed as if the OTP
      // was sent, same as every check above already passed. The OTP
      // screen opens as normal; there's just no real code behind it yet.
      if (_looksLikeProviderError(e)) return;
      throw _mapSendOtpException(e);
    }
  }

  @override
  Future<Profile> verifyPhoneRegistrationOtp({
    required String e164Phone,
    required String otp,
  }) async {
    if (!Validators.isValidOtpFormat(otp)) {
      throw OtpFailure(RegisterMessages.m6InvalidOrExpiredOtp);
    }
    try {
      await _authDataSource.verifyOtp(e164Phone: e164Phone, otp: otp);
    } on AuthException catch (e) {
      // DIAGNOSTIC (Foo: OTP verify shows "invalid data" instead of the
      // usual message) — logging the RAW Supabase error here so the real
      // reason shows up in `flutter run`'s console instead of being
      // silently swallowed by the generic message below. The leading
      // suspect is Supabase's own native "Enable CAPTCHA protection"
      // toggle (Dashboard -> Authentication -> Attack Protection) being
      // ON: this app deliberately does NOT wire a captcha_token into
      // signInWithOtp/verifyOTP (it implements its own separate 5-failed-
      // attempt gate via the `verify-captcha` Edge Function instead), so
      // if that native toggle is on, EVERY phone OTP call is rejected by
      // Supabase itself before it ever reaches this app's own logic.
      debugPrint('verifyPhoneRegistrationOtp failed: AuthException(${e.statusCode}): ${e.message}');
      throw OtpFailure(RegisterMessages.m6InvalidOrExpiredOtp);
    }
    return _fetchCurrentProfile();
  }

  @override
  Future<void> sendUsernameRegistrationOtp({
    required String username,
    required String password,
    required String e164Phone,
  }) async {
    if (!Validators.isValidUsernameFormat(username)) {
      throw ValidationFailure(RegisterMessages.m7UsernameTaken, field: 'username');
    }
    if (!Validators.isValidPassword(password)) {
      throw ValidationFailure(RegisterMessages.m8InvalidPassword, field: 'password');
    }
    if (!Validators.isValidPhone(e164Phone)) {
      throw ValidationFailure(RegisterMessages.m5InvalidPhoneFormat, field: 'phone');
    }
    final existingUsername = await _authDataSource.resolveUsername(username);
    if (existingUsername != null) {
      throw UsernameTakenFailure(RegisterMessages.m7UsernameTaken);
    }
    final existingPhone = await _authDataSource.phoneAccountStatus(e164Phone);
    if (existingPhone != null) {
      throw PhoneAlreadyRegisteredFailure(RegisterMessages.m4PhoneAlreadyRegistered);
    }
    try {
      await _authDataSource.signUpWithPhonePassword(
        e164Phone: e164Phone,
        password: password,
      );
    } on AuthException catch (e) {
      // See the matching comment in sendPhoneRegistrationOtp above.
      if (_looksLikeProviderError(e)) return;
      throw _mapSendOtpException(e);
    }
  }

  @override
  Future<Profile> verifyUsernameRegistrationOtp({
    required String username,
    required String e164Phone,
    required String otp,
  }) async {
    if (!Validators.isValidOtpFormat(otp)) {
      throw OtpFailure(RegisterMessages.m6InvalidOrExpiredOtp);
    }
    final AuthResponse response;
    try {
      response = await _authDataSource.verifyOtp(e164Phone: e164Phone, otp: otp);
    } on AuthException {
      throw OtpFailure(RegisterMessages.m6InvalidOrExpiredOtp);
    }
    final userId = response.user?.id;
    if (userId == null) {
      throw ServerFailure(RegisterMessages.m16RegistrationIncomplete);
    }
    await _authDataSource.setUsernameAndPasswordFlag(userId, username);
    return _fetchCurrentProfile();
  }

  // --- Login -------------------------------------------------------------------

  @override
  Future<void> sendPhoneLoginOtp(String e164Phone) async {
    if (!Validators.isValidPhone(e164Phone)) {
      throw ValidationFailure(LoginMessages.m4AccountNotFound, field: 'phone');
    }
    final status = await _authDataSource.phoneAccountStatus(e164Phone);
    if (status == null) {
      throw AccountNotFoundFailure(LoginMessages.m4AccountNotFound);
    }
    try {
      await _authDataSource.sendOtp(e164Phone, shouldCreateUser: false);
    } on AuthException catch (e) {
      // See the matching comment in sendPhoneRegistrationOtp above.
      if (_looksLikeProviderError(e)) return;
      throw _mapSendOtpException(e, useUc401Messages: true);
    }
  }

  @override
  Future<Profile> verifyPhoneLoginOtp({
    required String e164Phone,
    required String otp,
  }) async {
    if (!Validators.isValidOtpFormat(otp)) {
      throw OtpFailure(LoginMessages.m5InvalidOrExpiredOtp);
    }
    try {
      await _authDataSource.verifyOtp(e164Phone: e164Phone, otp: otp);
    } on AuthException catch (e) {
      // See the matching diagnostic comment in verifyPhoneRegistrationOtp.
      debugPrint('verifyPhoneLoginOtp failed: AuthException(${e.statusCode}): ${e.message}');
      throw OtpFailure(LoginMessages.m5InvalidOrExpiredOtp);
    }
    return _fetchCurrentProfile();
  }

  @override
  Future<Profile> loginWithUsernamePassword({
    required String username,
    required String password,
  }) async {
    final resolved = await _authDataSource.resolveUsername(username);
    if (resolved == null) {
      throw AccountNotFoundFailure(LoginMessages.m4AccountNotFound);
    }
    if (resolved.lockedUntil != null && resolved.lockedUntil!.isAfter(DateTime.now())) {
      throw LockedOutFailure(LoginMessages.m7AccountLocked, lockedUntil: resolved.lockedUntil);
    }
    try {
      await _authDataSource.signInWithPhonePassword(
        e164Phone: resolved.phone,
        password: password,
      );
    } on AuthException {
      // REQ_502_17: increment the shared, race-safe counter; A8 fires once
      // this crosses 5.
      final result = await _authDataSource.recordFailedLogin(resolved.userId);
      if (result.lockedUntil != null && result.lockedUntil!.isAfter(DateTime.now())) {
        throw LockedOutFailure(LoginMessages.m7AccountLocked, lockedUntil: result.lockedUntil);
      }
      throw InvalidCredentialsFailure(LoginMessages.m6InvalidCredentials);
    }
    // REQ_502_18: successful auth resets the counter. Safe as a plain
    // owner-scoped update — the client is authenticated by this point.
    await _authDataSource.resetFailedLoginCounter(resolved.userId);
    return _fetchCurrentProfile();
  }

  @override
  Future<void> resendOtp(String e164Phone) async {
    try {
      await _authDataSource.sendOtp(e164Phone, shouldCreateUser: false);
    } on AuthException catch (e) {
      // See the matching comment in sendPhoneRegistrationOtp above.
      if (_looksLikeProviderError(e)) return;
      throw _mapSendOtpException(e);
    }
  }

  @override
  Future<void> verifyCaptcha(String token) async {
    Map<String, dynamic> result;
    try {
      result = await _authDataSource.verifyCaptcha(token);
    } catch (_) {
      throw ServerFailure(OtpMessages.captchaVerificationFailed);
    }
    if (result['success'] != true) {
      throw ServerFailure(OtpMessages.captchaVerificationFailed);
    }
  }

  // --- Reset Password (UC403) ---------------------------------------------------

  @override
  Future<void> sendPasswordResetOtp(String e164Phone) async {
    if (!Validators.isValidPhone(e164Phone)) {
      throw ValidationFailure(PasswordResetMessages.m4PhoneNotRegistered, field: 'phone');
    }
    final status = await _authDataSource.phoneAccountStatus(e164Phone);
    // A1: genuinely not registered at all — M4, the spec's verbatim text.
    if (status == null) {
      throw AccountNotFoundFailure(PasswordResetMessages.m4PhoneNotRegistered);
    }
    // BUG FIX (8 Sep, Foo: "forget password does not work for number that
    // register only with phone number... will show the phone number is not
    // registered, which is not accurate"): this used to collapse BOTH cases
    // — genuinely unregistered, and registered-but-no-password (a
    // phone/OTP-only account) — into the same M4 "not registered" message.
    // The phone number IS registered in the second case; there's just no
    // password to reset because the tourist never set one, so M4 was
    // actively misleading. Splits out its own message (not in the spec's
    // verbatim M1–M8, added the same way `RegisterMessages.m11+` were).
    if (!status.hasPassword) {
      throw ValidationFailure(
        PasswordResetMessages.m9PhoneNoPassword,
        field: 'phone',
      );
    }
    try {
      await _authDataSource.sendOtp(e164Phone, shouldCreateUser: false);
    } on AuthException catch (e) {
      if (_looksLikeRateLimit(e)) {
        throw RateLimitedFailure(PasswordResetMessages.m8TooManyRequests);
      }
      rethrow;
    }
  }

  @override
  Future<void> verifyPasswordResetOtp({
    required String e164Phone,
    required String otp,
  }) async {
    if (!Validators.isValidOtpFormat(otp)) {
      throw OtpFailure(PasswordResetMessages.m5InvalidOrExpiredOtp);
    }
    try {
      // Per spec's own step ordering, this call is what authenticates the
      // tourist (proves phone ownership) BEFORE the new-password fields
      // are shown — resetPassword() below relies on this session.
      await _authDataSource.verifyOtp(e164Phone: e164Phone, otp: otp);
    } on AuthException {
      throw OtpFailure(PasswordResetMessages.m5InvalidOrExpiredOtp);
    }
  }

  @override
  Future<void> resetPassword(String newPassword) async {
    if (!Validators.isValidPassword(newPassword)) {
      throw ValidationFailure(PasswordResetMessages.m6InvalidPassword, field: 'password');
    }
    final userId = _authDataSource.currentUser?.id;
    if (userId == null) {
      // Shouldn't happen if verifyPasswordResetOtp succeeded first, but
      // guard against a caller skipping the OTP step.
      throw SessionExpiredFailure(PasswordResetMessages.m5InvalidOrExpiredOtp);
    }
    try {
      await _authDataSource.updatePassword(newPassword);
    } catch (_) {
      throw ServerFailure(PasswordResetMessages.m8TooManyRequests);
    }
    // REQ_502_19: a successful reset clears any active login lockout.
    await _authDataSource.resetFailedLoginCounter(userId);
  }

  // --- Profile retrieval / editing (UC402) --------------------------------------

  @override
  Future<Profile> fetchProfile() async {
    final userId = _requireUserId();
    try {
      final dto = await _profileDataSource.fetchProfileRow(userId);
      final user = _authDataSource.currentUser;
      return dto.toEntity(
        phone: _normalizePhone(user?.phone),
        hasGoogleLinked:
            user?.identities?.any((i) => i.provider == 'google') ?? false,
        createdAt: user == null ? null : DateTime.tryParse(user.createdAt),
      );
    } catch (_) {
      throw ServerFailure(ProfileMessages.m3UnableToLoad);
    }
  }

  @override
  Future<Profile> updatePersonalInfo({String? fullName}) async {
    final userId = _requireUserId();
    try {
      final dto = await _profileDataSource.updatePersonalInfo(
        userId,
        fullName: fullName,
      );
      final user = _authDataSource.currentUser;
      return dto.toEntity(
        phone: _normalizePhone(user?.phone),
        hasGoogleLinked:
            user?.identities?.any((i) => i.provider == 'google') ?? false,
        createdAt: user == null ? null : DateTime.tryParse(user.createdAt),
      );
    } catch (_) {
      // UC402 A7: caller should keep the unsaved values on screen and offer
      // Retry/Cancel — this failure alone doesn't discard anything.
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  @override
  Future<Preferences> fetchPreferences() async {
    final userId = _requireUserId();
    try {
      final dto = await _profileDataSource.fetchPreferencesRow(userId);
      return dto.toEntity();
    } catch (_) {
      throw ServerFailure(ProfileMessages.m3UnableToLoad);
    }
  }

  @override
  Future<void> updatePreferences(Preferences preferences) async {
    final userId = _requireUserId();
    try {
      await _profileDataSource.updatePreferencesRow(
        userId,
        PreferencesDto.toUpdateJson(preferences),
      );
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  @override
  Future<void> updateLanguage(String languageCode) async {
    final userId = _requireUserId();
    try {
      await _profileDataSource.updateLanguage(userId, languageCode);
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  @override
  Future<List<Bookmark>> fetchBookmarks() async {
    final userId = _requireUserId();
    try {
      final rows = await _profileDataSource.fetchBookmarkRows(userId);
      return rows.map((dto) => dto.toEntity()).toList();
    } catch (_) {
      throw ServerFailure(ProfileMessages.m3UnableToLoad);
    }
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    final userId = _requireUserId();
    try {
      await _profileDataSource.deleteBookmark(userId, bookmarkId);
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  // --- Personal Info sub-flows (UC402) ----------------------------------------

  @override
  Future<void> sendPhoneChangeOtp(String newE164Phone) async {
    if (!Validators.isValidPhone(newE164Phone)) {
      throw ValidationFailure(ProfileMessages.m8InvalidPhoneFormat, field: 'phone');
    }
    final existing = await _authDataSource.phoneAccountStatus(newE164Phone);
    if (existing != null) {
      throw PhoneAlreadyRegisteredFailure(ProfileMessages.m9PhoneAlreadyRegistered);
    }
    try {
      await _authDataSource.sendPhoneChangeOtp(newE164Phone);
    } on AuthException catch (e) {
      if (_looksLikeRateLimit(e)) {
        throw RateLimitedFailure(ProfileMessages.m6UnableToUpdate);
      }
      // BUG FIX (6 Sep, Foo: "the sent otp on the phone number change in
      // the personal info fail to redirect user to otp pages"): this was
      // the one send-OTP call site that didn't check
      // `_looksLikeProviderError` — while no SMS provider is configured,
      // every attempt threw the raw Twilio error here instead of
      // proceeding like the other four call sites already do.
      if (_looksLikeProviderError(e)) return;
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> verifyPhoneChangeOtp({
    required String newE164Phone,
    required String otp,
  }) async {
    if (!Validators.isValidOtpFormat(otp)) {
      throw OtpFailure(ProfileMessages.m10InvalidOrExpiredOtp);
    }
    try {
      await _authDataSource.verifyPhoneChangeOtp(newE164Phone: newE164Phone, otp: otp);
    } on AuthException {
      throw OtpFailure(ProfileMessages.m10InvalidOrExpiredOtp);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _authDataSource.currentUser;
    final phone = user?.phone;
    if (user == null || phone == null || phone.isEmpty) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    if (!Validators.isValidPassword(newPassword)) {
      throw ValidationFailure(ProfileMessages.m17InvalidPassword, field: 'newPassword');
    }
    try {
      // C6: verified via the current password, not OTP, since the tourist
      // is already authenticated — re-running sign-in is the simplest way
      // to have Supabase itself confirm it without a separate credential
      // check endpoint.
      await _authDataSource.signInWithPhonePassword(e164Phone: phone, password: currentPassword);
    } on AuthException {
      throw InvalidCredentialsFailure(ProfileMessages.m16CurrentPasswordIncorrect);
    }
    try {
      await _authDataSource.updatePassword(newPassword);
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  @override
  Future<Profile> setUsernameAndPassword({
    required String username,
    required String password,
  }) async {
    final user = _authDataSource.currentUser;
    if (user == null) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    // Same format checks as UC400 A3's Username tab (sendUsernameRegistrationOtp
    // above) — reusing RegisterMessages here even though this isn't the
    // registration flow, since the validation rules and their messages are
    // identical and this app has no separate "manage login methods" catalog.
    if (!Validators.isNotEmpty(username) || !Validators.isValidUsernameFormat(username)) {
      throw ValidationFailure(RegisterMessages.m15UsernameRequired, field: 'username');
    }
    if (!Validators.isValidPassword(password)) {
      throw ValidationFailure(RegisterMessages.m8InvalidPassword, field: 'password');
    }
    final existingUsername = await _authDataSource.resolveUsername(username);
    if (existingUsername != null) {
      throw UsernameTakenFailure(RegisterMessages.m7UsernameTaken);
    }
    try {
      // No current-password re-check (unlike changePassword above) — there
      // is no existing password to verify against. The tourist is already
      // authenticated via their existing session (phone or Google), which
      // is the only credential this action requires.
      await _authDataSource.updatePassword(password);
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
    await _authDataSource.setUsernameAndPasswordFlag(user.id, username);
    return _fetchCurrentProfile();
  }

  @override
  Future<Profile> linkGoogleAccount() async {
    final user = _authDataSource.currentUser;
    if (user == null) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    if (_authDataSource.currentUserHasGoogleIdentity) {
      // C5: linking is only offered when none is linked — guard here too
      // in case the screen's own visibility check is stale.
      throw GoogleSignInFailure(ProfileMessages.m14GoogleAlreadyLinked);
    }
    try {
      await _authDataSource.linkGoogleAndAwaitUpdate(redirectTo: _googleRedirectUrl);
    } on AuthException catch (e) {
      // DIAGNOSTIC ("can't add a Google account" report): the most likely
      // cause is that the Supabase project's "Allow manual linking"
      // setting (Dashboard → Authentication → Sign In / Providers, beta,
      // OFF by default) isn't enabled — `linkIdentity()` then throws an
      // AuthApiException with message "Manual linking is disabled" instead
      // of actually launching the Google flow. Check the debug console
      // next time this is tapped; if the message contains "manual
      // linking", that confirms it.
      debugPrint('linkGoogleAccount failed: AuthException(${e.statusCode}): ${e.message}');
      if (_looksLikeManualLinkingDisabled(e)) {
        // STILL seeing this after enabling "Allow manual linking"? Three
        // things to double-check, in order of likelihood — none of these
        // are things the client code can detect or work around:
        //  1. The toggle was saved on a DIFFERENT Supabase project than
        //     the one this app actually points to. Compare the Project
        //     Ref in the dashboard's URL against `app_config.dart`'s
        //     `supabaseUrl` (the ref is the subdomain, e.g.
        //     `abcdefgh.supabase.co` → ref `abcdefgh`).
        //  2. It's easy to toggle the WRONG setting — Supabase also has
        //     an "allow automatic linking of accounts with the same
        //     email" checkbox (under each provider's own settings),
        //     which is a different feature and does NOT enable this.
        //     The one this needs is specifically labelled "Allow manual
        //     linking" under Authentication → Sign In / Providers (it's
        //     marked beta/experimental, near the bottom of that page).
        //  3. The change can take a minute or two to propagate — try
        //     again after a short wait, and after a full app restart
        //     (not just hot reload) so a stale auth session isn't reused.
        // The raw exception is appended below in debug builds only, so
        // it's visible directly in the on-screen error rather than only
        // in `flutter run`'s console.
        throw GoogleSignInFailure(
          'Google account linking is turned off for this app. Enable '
          '"Allow manual linking" in the Supabase dashboard '
          '(Authentication → Sign In / Providers) and try again.'
          '${kDebugMode ? '\n[debug] ${e.statusCode}: ${e.message}' : ''}',
        );
      }
      if (_looksLikeIdentityAlreadyLinked(e)) {
        // REQ_503_16: the Google identity itself is already linked to a
        // DIFFERENT NarrateMy account.
        throw GoogleSignInFailure(ProfileMessages.m14GoogleAlreadyLinked);
      }
      throw GoogleSignInFailure(ProfileMessages.m13UnableToLinkGoogle);
    } catch (e) {
      debugPrint('linkGoogleAccount failed: $e');
      throw GoogleSignInFailure(ProfileMessages.m13UnableToLinkGoogle);
    }
    return _fetchCurrentProfile();
  }

  bool _looksLikeManualLinkingDisabled(AuthException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('manual linking');
  }

  @override
  Future<void> unlinkGoogleAccount() async {
    final user = _authDataSource.currentUser;
    if (user == null) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    // A21: block before the caller even shows the M19 confirmation prompt.
    final dto = await _profileDataSource.fetchProfileRow(user.id);
    final hasPhone = user.phone != null && user.phone!.isNotEmpty;
    if (!dto.hasPassword && !hasPhone) {
      // Updated 8 Sep at Foo's request: since an account can now gain a
      // username + password AFTER registration too (setUsernameAndPassword
      // above), the spec's verbatim M21 ("verify a phone number") no
      // longer describes the actual rule — password counts as a valid
      // alternative just as much as phone does. See ProfileMessages.m27's
      // doc comment.
      throw NoRemainingLoginMethodFailure(ProfileMessages.m27MustHaveAnotherLoginMethod);
    }
    try {
      await _authDataSource.unlinkGoogleIdentity();
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m6UnableToUpdate);
    }
  }

  // --- Added at Foo's request — NOT in the written spec ---------------------

  Future<Profile> _reloadAfterWrite(String userId) async {
    final dto = await _profileDataSource.fetchProfileRow(userId);
    final user = _authDataSource.currentUser;
    return dto.toEntity(
      phone: _normalizePhone(user?.phone),
      hasGoogleLinked: user?.identities?.any((i) => i.provider == 'google') ?? false,
      createdAt: user == null ? null : DateTime.tryParse(user.createdAt),
    );
  }

  @override
  Future<Profile> updateAvatar({required Uint8List bytes, required String fileExt}) async {
    final userId = _requireUserId();
    try {
      final url = await _profileDataSource.uploadAvatar(userId, bytes, fileExt);
      await _profileDataSource.updateAvatarUrl(userId, url);
      return await _reloadAfterWrite(userId);
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m25UnableToUpdatePhoto);
    }
  }

  @override
  Future<Profile> completeMandatoryDetails({
    required String fullName,
    required DateTime dateOfBirth,
  }) async {
    final userId = _requireUserId();
    try {
      await _profileDataSource.completeMandatoryDetailsRow(
        userId,
        fullName: fullName,
        dateOfBirth: dateOfBirth,
      );
      return await _reloadAfterWrite(userId);
    } catch (_) {
      throw ProfileUpdateFailure(RegisterMessages.m14UnableToSaveDetails);
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _authDataSource.currentUser;
    if (user == null) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    try {
      await _authDataSource.deleteOwnAccount();
    } catch (_) {
      throw ProfileUpdateFailure(ProfileMessages.m24UnableToDeleteAccount);
    }
    // The RPC deletes the auth.users row server-side, which invalidates the
    // session — sign out locally too so the client's own cached session
    // state doesn't linger stale.
    await _authDataSource.signOut();
  }

  bool _looksLikeIdentityAlreadyLinked(AuthException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('already linked') || msg.contains('identity_already_exists');
  }

  // --- Session -------------------------------------------------------------------

  @override
  Future<void> logout() => _authDataSource.signOut();

  @override
  bool get isLoggedIn => _authDataSource.isLoggedIn;

  @override
  Stream<bool> get authStateChanges => _authDataSource.authStateChanges;

  // --- Shared helpers --------------------------------------------------------------

  Future<Profile> _fetchCurrentProfile() async {
    final user = _authDataSource.currentUser;
    if (user == null) {
      throw SessionExpiredFailure(LoginMessages.m4AccountNotFound);
    }
    final dto = await _profileDataSource.fetchProfileRow(user.id);
    return dto.toEntity(
      phone: _normalizePhone(user.phone),
      hasGoogleLinked: _authDataSource.currentUserHasGoogleIdentity,
      createdAt: DateTime.tryParse(user.createdAt),
    );
  }

  AuthFailure _mapSendOtpException(
    AuthException e, {
    bool useUc401Messages = false,
  }) {
    if (_looksLikeRateLimit(e)) {
      return RateLimitedFailure(
        useUc401Messages ? LoginMessages.m8TooManyOtpRequests : RegisterMessages.m9TooManyRequests,
      );
    }
    return UnexpectedAuthFailure(e.message);
  }

  bool _looksLikeRateLimit(AuthException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('rate limit') ||
        msg.contains('too many') ||
        e.statusCode == '429';
  }

  /// Per explicit request: while no SMS provider (Twilio/etc.) is
  /// configured on this Supabase project, sending an OTP fails with a raw
  /// provider error such as "Error sending confirmation OTP to provider:
  /// Authentication Error - invalid username. More information:
  /// https://twilio.com/docs/error/20003" — meaningless and alarming to a
  /// tourist, and not something the phone number they typed caused. This
  /// is caught in every send/resend-OTP call site so the app proceeds as
  /// if the OTP were sent instead of surfacing it. Remove this check (or
  /// let it just stop matching once a provider is configured) if a real
  /// send failure should start being shown again.
  bool _looksLikeProviderError(AuthException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('sending confirmation') ||
        msg.contains('sending otp') ||
        msg.contains('sms provider') ||
        msg.contains('twilio') ||
        msg.contains('error sending') ||
        (msg.contains('provider') && msg.contains('authentication error'));
  }
}
