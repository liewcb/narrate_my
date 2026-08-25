/// Domain entity for a tourist's account + Personal Info (UC402).
/// Deliberately excludes Preferences and Bookmarks — those are separate
/// entities/tables per REQ_503_11's independent-atomic-save requirement.
class Profile {
  final String id;
  final String? username; // null for Google/phone-only accounts (C3: immutable once set)
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final String? phone; // E.164, from Supabase Auth (auth.users.phone), not the profiles table
  final String preferredLanguage; // ISO 639-1 code, see Module5Constants.supportedLanguages
  final bool hasPassword; // drives "Change Password" visibility (C6)
  final bool hasGoogleLinked; // drives link vs. unlink affordance (C5)
  final DateTime? createdAt;
  // Added at Foo's request — not part of the written spec's Profile fields.
  // Captured exactly once, via the non-skippable Mandatory Details step
  // right after registration (see `mandatory_details_screen.dart`); null
  // means that step hasn't been completed yet (e.g. an account created
  // before this feature existed), which is exactly the signal Google
  // Sign-In's register-vs-login branch uses to decide whether to route
  // through that step.
  final DateTime? dateOfBirth;

  const Profile({
    required this.id,
    this.username,
    this.fullName,
    this.bio,
    this.avatarUrl,
    this.phone,
    this.preferredLanguage = 'en',
    this.hasPassword = false,
    this.hasGoogleLinked = false,
    this.createdAt,
    this.dateOfBirth,
  });

  Profile copyWith({
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
    String? phone,
    String? preferredLanguage,
    bool? hasPassword,
    bool? hasGoogleLinked,
    DateTime? dateOfBirth,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      hasPassword: hasPassword ?? this.hasPassword,
      hasGoogleLinked: hasGoogleLinked ?? this.hasGoogleLinked,
      createdAt: createdAt,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    );
  }

  /// UC402 C5: unlinking Google is only allowed if another login method
  /// remains. A username+password account, or a still-verified phone,
  /// counts as "another method" alongside Google.
  bool get hasNonGoogleLoginMethod => hasPassword || phone != null;

  /// Added at Foo's request: has this account completed the mandatory
  /// Name + Date of Birth step? Used right after Google Sign-In to tell a
  /// brand-new registration apart from a returning login (both go through
  /// the same `registerOrSignInWithGoogle()` call — see
  /// `register_screen.dart`'s `_handleGoogle`).
  bool get hasCompletedMandatoryDetails =>
      fullName != null && fullName!.isNotEmpty && dateOfBirth != null;
}
