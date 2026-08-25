import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dto/profile_dto.dart';

/// Thin wrapper around the Supabase Auth SDK + the `profiles` table's auth-
/// adjacent columns. Deliberately dumb: every method here is a near-direct
/// pass-through to `supabase_flutter`, with Supabase's own exceptions left
/// to propagate. All spec-mapping (which alt-flow, which verbatim message,
/// lockout bookkeeping) happens one layer up, in
/// `SupabaseAuthRepositoryAdapter` — this class has no knowledge of
/// UC400–403 at all, only of Supabase.
class AuthRemoteDataSource {
  final SupabaseClient _client;

  AuthRemoteDataSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  bool get isLoggedIn => _client.auth.currentSession != null;

  Stream<bool> get authStateChanges =>
      _client.auth.onAuthStateChange.map((s) => s.session != null);

  bool get currentUserHasGoogleIdentity =>
      currentUser?.identities?.any((i) => i.provider == 'google') ?? false;

  // --- Username lookup (pre-auth, via RPC — see 0002_auth_functions.sql) ---

  /// Returns null if no account has this username (UC401 A5 / M4).
  Future<({String userId, String phone, DateTime? lockedUntil})?> resolveUsername(
    String username,
  ) async {
    final rows = await _client.rpc('resolve_username', params: {
      'p_username': username,
    }) as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final phone = row['phone'] as String?;
    final userId = row['user_id'] as String?;
    if (phone == null || userId == null) return null;
    final lockedUntilRaw = row['locked_until'] as String?;
    return (
      userId: userId,
      phone: phone,
      lockedUntil: lockedUntilRaw == null ? null : DateTime.parse(lockedUntilRaw),
    );
  }

  Future<({int attempts, DateTime? lockedUntil})> recordFailedLogin(
    String userId,
  ) async {
    final rows = await _client.rpc('record_failed_login', params: {
      'p_user_id': userId,
    }) as List<dynamic>;
    final row = rows.first as Map<String, dynamic>;
    final lockedUntilRaw = row['locked_until'] as String?;
    return (
      attempts: row['failed_login_attempts'] as int? ?? row['attempts'] as int? ?? 0,
      lockedUntil: lockedUntilRaw == null ? null : DateTime.parse(lockedUntilRaw),
    );
  }

  Future<void> resetFailedLoginCounter(String userId) async {
    await _client.from('profiles').update({
      'failed_login_attempts': 0,
      'locked_until': null,
    }).eq('id', userId);
  }

  /// UC403 A1's precondition check: null = phone not registered at all;
  /// otherwise tells the caller whether that account has a password set
  /// (a phone-only account exists but isn't eligible for UC403 either).
  Future<({String userId, bool hasPassword})?> phoneAccountStatus(
    String e164Phone,
  ) async {
    final rows = await _client.rpc('phone_account_status', params: {
      'p_phone': e164Phone,
    }) as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    return (
      userId: row['user_id'] as String,
      hasPassword: row['has_password'] as bool? ?? false,
    );
  }

  // --- OTP: phone registration / login / reset (all share one mechanism) ---

  Future<void> sendOtp(String e164Phone, {required bool shouldCreateUser}) {
    return _client.auth.signInWithOtp(
      phone: e164Phone,
      shouldCreateUser: shouldCreateUser,
    );
  }

  Future<AuthResponse> verifyOtp({
    required String e164Phone,
    required String otp,
  }) {
    return _client.auth.verifyOTP(
      phone: e164Phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  // --- Username & Password ---------------------------------------------------

  Future<AuthResponse> signUpWithPhonePassword({
    required String e164Phone,
    required String password,
  }) {
    return _client.auth.signUp(phone: e164Phone, password: password);
  }

  Future<AuthResponse> signInWithPhonePassword({
    required String e164Phone,
    required String password,
  }) {
    return _client.auth.signInWithPassword(phone: e164Phone, password: password);
  }

  /// Persists the chosen username onto the now-existing `profiles` row
  /// (created by the `handle_new_user` trigger the moment `auth.users`
  /// got a row from signUp/verifyOTP). Also flips `has_password`.
  Future<void> setUsernameAndPasswordFlag(String userId, String username) {
    return _client.from('profiles').update({
      'username': username,
      'has_password': true,
    }).eq('id', userId);
  }

  // --- Google -----------------------------------------------------------------

  /// Launches the OAuth browser/webview flow and waits for the resulting
  /// sign-in to land via [authStateChanges]. Supabase itself decides
  /// new-account-vs-existing-account (it signs into the existing account
  /// if that Google identity is already linked, per UC400 A6) — nothing
  /// extra to orchestrate here for that part.
  Future<void> signInWithGoogleAndAwaitSession({
    required String redirectTo,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<AuthState> sub;
    sub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
      if (!launched) {
        throw const AuthException('Could not launch Google sign-in.');
      }
      await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  // --- CAPTCHA (UC400 A8) --------------------------------------------------------

  /// Invokes the `verify-captcha` Edge Function (server-side hCaptcha
  /// `siteverify` call — the secret key never ships in this app). Returns
  /// the function's raw JSON body; `SupabaseAuthRepositoryAdapter` decides
  /// what `success: false` (or a non-2xx response) means.
  Future<Map<String, dynamic>> verifyCaptcha(String token) async {
    final response = await _client.functions.invoke(
      'verify-captcha',
      body: {'token': token},
    );
    final data = response.data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'success': false};
  }

  // --- Google account linking (UC402 A13/A20) -----------------------------------
  //
  // Distinct from `signInWithGoogleAndAwaitSession` above: the tourist is
  // ALREADY authenticated here, so this adds a Google identity onto the
  // existing session rather than creating/signing into one.
  //
  // NOTE: `linkIdentity`'s completion signal is less commonly documented
  // than plain sign-in's — waiting on `AuthChangeEvent.userUpdated` is this
  // adapter's best-effort read of the Supabase Flutter SDK's behavior, not
  // something verified against a live project. If linking silently hangs
  // on your Supabase project, check the SDK version's actual event name
  // first before assuming the redirect/deep-link wiring is at fault.

  Future<void> linkGoogleAndAwaitUpdate({
    required String redirectTo,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<AuthState> sub;
    sub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.userUpdated && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      final launched = await _client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
      if (!launched) {
        throw const AuthException('Could not launch Google linking.');
      }
      await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> unlinkGoogleIdentity() async {
    final identities = _client.auth.currentUser?.identities ?? const [];
    UserIdentity? google;
    for (final identity in identities) {
      if (identity.provider == 'google') {
        google = identity;
        break;
      }
    }
    if (google == null) {
      throw const AuthException('No linked Google identity found.');
    }
    await _client.auth.unlinkIdentity(google);
  }

  // --- Phone change (UC402 A9) --------------------------------------------------
  //
  // Mirrors Supabase's email-change pattern: `updateUser` with a new phone
  // sends an OTP to that NEW number (the tourist is already authenticated,
  // so this is a distinct code path from sign-up/sign-in's
  // `signInWithOtp`); `verifyOTP(type: OtpType.phoneChange, ...)` confirms
  // it and commits the change onto the session's `auth.users` row.

  Future<UserResponse> sendPhoneChangeOtp(String newE164Phone) {
    return _client.auth.updateUser(UserAttributes(phone: newE164Phone));
  }

  Future<AuthResponse> verifyPhoneChangeOtp({
    required String newE164Phone,
    required String otp,
  }) {
    return _client.auth.verifyOTP(
      phone: newE164Phone,
      token: otp,
      type: OtpType.phoneChange,
    );
  }

  // --- Password reset (UC403) --------------------------------------------------

  Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() => _client.auth.signOut();

  // --- Account deletion (added at Foo's request, not in the spec) --------------

  /// Calls the `delete_own_account` SECURITY DEFINER RPC (see
  /// `0006_delete_account_and_dob.sql`) — a normal `authenticated`-role
  /// client cannot delete `auth.users` rows directly, and the service-role
  /// Admin API that could must never ship inside this app.
  Future<void> deleteOwnAccount() => _client.rpc('delete_own_account');

  // --- Profile fetch (shared with ProfileRemoteDataSource's needs) -------------

  Future<ProfileDto> fetchProfileRow(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return ProfileDto.fromJson(row);
  }
}
