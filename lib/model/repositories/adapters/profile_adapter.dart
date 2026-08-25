import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../business_logic/profile_business_logic/messages/login_messages.dart';
import '../../business_logic/profile_business_logic/messages/password_reset_messages.dart';
import '../../business_logic/profile_business_logic/messages/profile_messages.dart';
import '../../business_logic/profile_business_logic/messages/register_messages.dart';
import '../../business_logic/profile_business_logic/validators.dart';
import '../../data_sources/remote/auth_remote_data_source.dart';
import '../../data_sources/remote/profile_remote_data_source.dart';
import '../../dto/preferences_dto.dart';
import '../../entities/bookmark.dart';
import '../../entities/preferences.dart';
import '../../entities/profile.dart';
import '../interfaces/profile_repository.dart';

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

  Future<Profile> _googleSignIn() async {
    try {
      await _authDataSource.signInWithGoogleAndAwaitSession(
        redirectTo: _googleRedirectUrl,
      );
      // Awaited deliberately so a failure fetching the profile row right
      // after sign-in is still caught here and mapped to
      // GoogleSignInFailure, rather than escaping uncaught.
      return await _fetchCurrentProfile();
    } catch (_) {
      throw GoogleSignInFailure(RegisterMessages.m3GoogleSignInFailed);
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
    } on AuthException {
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
      throw ServerFailure('Registration could not be completed. Please try again.');
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
    } on AuthException {
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
      throw _mapSendOtpException(e);
    }
  }

  @override
  Future<void> verifyCaptcha(String token) async {
    Map<String, dynamic> result;
    try {
      result = await _authDataSource.verifyCaptcha(token);
    } catch (_) {
      throw ServerFailure('CAPTCHA verification failed. Please try again.');
    }
    if (result['success'] != true) {
      throw ServerFailure('CAPTCHA verification failed. Please try again.');
    }
  }

  // --- Reset Password (UC403) ---------------------------------------------------

  @override
  Future<void> sendPasswordResetOtp(String e164Phone) async {
    if (!Validators.isValidPhone(e164Phone)) {
      throw ValidationFailure(PasswordResetMessages.m4PhoneNotRegistered, field: 'phone');
    }
    final status = await _authDataSource.phoneAccountStatus(e164Phone);
    // A1: not registered at all, OR registered but not via Username &
    // Password — both collapse to the same M4 message.
    if (status == null || !status.hasPassword) {
      throw AccountNotFoundFailure(PasswordResetMessages.m4PhoneNotRegistered);
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
      final user = Supabase.instance.client.auth.currentUser;
      return dto.toEntity(
        phone: user?.phone,
        hasGoogleLinked:
            user?.identities?.any((i) => i.provider == 'google') ?? false,
        createdAt: user == null ? null : DateTime.tryParse(user.createdAt),
      );
    } catch (_) {
      throw ServerFailure(ProfileMessages.m3UnableToLoad);
    }
  }

  @override
  Future<Profile> updatePersonalInfo({String? fullName, String? bio}) async {
    final userId = _requireUserId();
    try {
      final dto = await _profileDataSource.updatePersonalInfo(
        userId,
        fullName: fullName,
        bio: bio,
      );
      final user = Supabase.instance.client.auth.currentUser;
      return dto.toEntity(
        phone: user?.phone,
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
      if (_looksLikeIdentityAlreadyLinked(e)) {
        // REQ_503_16: the Google identity itself is already linked to a
        // DIFFERENT NarrateMy account.
        throw GoogleSignInFailure(ProfileMessages.m14GoogleAlreadyLinked);
      }
      throw GoogleSignInFailure(ProfileMessages.m13UnableToLinkGoogle);
    } catch (_) {
      throw GoogleSignInFailure(ProfileMessages.m13UnableToLinkGoogle);
    }
    return _fetchCurrentProfile();
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
      throw NoRemainingLoginMethodFailure(ProfileMessages.m21MustVerifyPhoneBeforeUnlink);
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
    final user = Supabase.instance.client.auth.currentUser;
    return dto.toEntity(
      phone: user?.phone,
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
      phone: user.phone,
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
}
