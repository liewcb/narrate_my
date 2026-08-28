import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dto/bookmark_dto.dart';
import '../../dto/preferences_dto.dart';
import '../../dto/profile_dto.dart';

/// Thin wrapper around the `profiles`/`preferences`/`bookmarks` tables for
/// the already-authenticated tourist. Like `AuthRemoteDataSource`, this
/// class has no knowledge of UC402's alt-flows or verbatim messages — all
/// of that lives one layer up in `SupabaseProfileRepositoryAdapter`.
class ProfileRemoteDataSource {
  final SupabaseClient _client;

  ProfileRemoteDataSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<ProfileDto> fetchProfileRow(String userId) async {
    final row =
        await _client.from('profiles').select().eq('id', userId).single();
    return ProfileDto.fromJson(row);
  }

  /// REQ_503_3/11: Personal Info's own atomic UPDATE — only touches
  /// full_name/bio, never any other column.
  Future<ProfileDto> updatePersonalInfo(
    String userId, {
    String? fullName,
    String? bio,
  }) async {
    final row = await _client
        .from('profiles')
        .update({'full_name': fullName, 'bio': bio})
        .eq('id', userId)
        .select()
        .single();
    return ProfileDto.fromJson(row);
  }

  /// REQ_503_9/11: Language's own atomic UPDATE — only touches
  /// preferred_language.
  ///
  /// The trailing `.select().single()` is deliberate, not decoration: a
  /// Supabase `.update()` called without `.select()` does NOT throw when
  /// zero rows are affected (e.g. an RLS policy silently denies the write,
  /// or the row doesn't exist) — it just "succeeds" having written
  /// nothing. Forcing a `.select().single()` makes a no-op update surface
  /// as a real `PostgrestException` instead of a save that looks
  /// successful in the UI but never actually changed anything.
  Future<void> updateLanguage(String userId, String languageCode) async {
    await _client
        .from('profiles')
        .update({'preferred_language': languageCode})
        .eq('id', userId)
        .select()
        .single();
  }

  Future<PreferencesDto> fetchPreferencesRow(String userId) async {
    final row = await _client
        .from('preferences')
        .select()
        .eq('user_id', userId)
        .single();
    return PreferencesDto.fromJson(row);
  }

  /// REQ_503_11: Preferences' own atomic UPDATE — all 5 category columns
  /// in one statement, isolated from profiles' Personal Info/Language
  /// columns entirely (different table).
  ///
  /// Same `.select().single()` reasoning as [updateLanguage] above: without
  /// it, a save that RLS silently rejects (or that targets a missing
  /// `preferences` row) would report success to the ViewModel while the
  /// database stays unchanged — exactly the "I saved but nothing changed"
  /// symptom this was written to fix.
  Future<void> updatePreferencesRow(String userId, Map<String, dynamic> updateJson) async {
    await _client
        .from('preferences')
        .update(updateJson)
        .eq('user_id', userId)
        .select()
        .single();
  }

  Future<List<BookmarkDTO>> fetchBookmarkRows(String userId) async {
    final rows = await _client
        .from('bookmarks')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => BookmarkDTO.fromSupabase(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteBookmark(String userId, String bookmarkId) {
    return _client
        .from('bookmarks')
        .delete()
        .eq('id', bookmarkId)
        .eq('user_id', userId); // belt-and-suspenders alongside RLS
  }

  // --- Added at Foo's request — NOT in the written UC402 spec ---------------

  /// Uploads to the `avatars` Storage bucket (0007_avatar_storage.sql)
  /// under `{userId}/avatar.<ext>`, overwriting any previous upload at that
  /// EXACT path (`upsert: true`). A prior upload with a DIFFERENT extension
  /// is left behind as an orphan file in Storage — acceptable for this
  /// assignment's scope, flagged here rather than silently ignored.
  /// Returns the public URL (the bucket is public-read, see 0007) with a
  /// cache-busting query param appended, since the underlying object path
  /// is reused on every re-upload and `NetworkImage` would otherwise keep
  /// showing the old cached bytes for the same URL.
  Future<String> uploadAvatar(String userId, Uint8List bytes, String fileExt) async {
    final path = '$userId/avatar.$fileExt';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Column-scoped atomic update, same `.select().single()` reasoning as
  /// [updateLanguage]/[updatePreferencesRow] above.
  Future<void> updateAvatarUrl(String userId, String avatarUrl) async {
    await _client
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', userId)
        .select()
        .single();
  }

  /// The one-time Mandatory Details save (full name + date of birth) —
  /// deliberately its own column-scoped UPDATE, separate from
  /// [updatePersonalInfo]'s full_name/bio pair, since this is a different
  /// flow (post-registration onboarding, not the editable Personal Info
  /// section) writing a different column set.
  Future<void> completeMandatoryDetailsRow(
    String userId, {
    required String fullName,
    required DateTime dateOfBirth,
  }) async {
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
        })
        .eq('id', userId)
        .select()
        .single();
  }

  /// See `AuthRemoteDataSource.deleteOwnAccount` — account deletion itself
  /// lives there (it's an `auth.users` operation via RPC), not here.
}
