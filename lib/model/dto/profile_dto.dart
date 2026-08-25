import '../entities/profile.dart';

/// Maps a `public.profiles` row (+ the phone/created_at that only live on
/// the Supabase Auth user, not the table) to the domain [Profile] entity.
class ProfileDto {
  final String id;
  final String? username;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final String preferredLanguage;
  final bool hasPassword;
  // Added at Foo's request (0006_delete_account_and_dob.sql) — not part of
  // the original spec-mapped columns above.
  final DateTime? dateOfBirth;

  ProfileDto({
    required this.id,
    this.username,
    this.fullName,
    this.bio,
    this.avatarUrl,
    required this.preferredLanguage,
    required this.hasPassword,
    this.dateOfBirth,
  });

  factory ProfileDto.fromJson(Map<String, dynamic> json) {
    return ProfileDto(
      id: json['id'] as String,
      username: json['username'] as String?,
      fullName: json['full_name'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'en',
      hasPassword: json['has_password'] as bool? ?? false,
      // Null until 0006_delete_account_and_dob.sql has been run, or for any
      // account that hasn't completed the Mandatory Details step yet.
      dateOfBirth: json['date_of_birth'] == null
          ? null
          : DateTime.tryParse(json['date_of_birth'] as String),
    );
  }

  /// [phone]/[hasGoogleLinked]/[createdAt] come from `auth.users`
  /// (via the Supabase Auth SDK's current session), not this table row —
  /// the caller (AuthRemoteDataSource/ProfileRemoteDataSource) merges them
  /// in here since a client can't query `auth.users` directly over REST.
  Profile toEntity({
    String? phone,
    bool hasGoogleLinked = false,
    DateTime? createdAt,
  }) {
    return Profile(
      id: id,
      username: username,
      fullName: fullName,
      bio: bio,
      avatarUrl: avatarUrl,
      phone: phone,
      preferredLanguage: preferredLanguage,
      hasPassword: hasPassword,
      hasGoogleLinked: hasGoogleLinked,
      createdAt: createdAt,
      dateOfBirth: dateOfBirth,
    );
  }
}
