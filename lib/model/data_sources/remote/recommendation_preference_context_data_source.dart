import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_manager.dart';

/// Supplies only the small amount of authenticated preference context needed
/// to keep the phone cache separate between users and preference values.
/// The Edge Function remains the authority that applies these preferences to
/// the prompt; this fingerprint is only used for cache invalidation.
class RecommendationPreferenceContextDataSource {
  final SupabaseClient _supabase;

  RecommendationPreferenceContextDataSource({SupabaseClient? client})
    : _supabase = client ?? DatabaseManager().remote.client;

  Future<String?> getCacheIdentity() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'guest:default';

    try {
      final row = await _supabase
          .from('preferences')
          .select('''
            attraction_interests,
            food_cuisine_interests,
            dietary_preferences,
            dietary_restrictions,
            accessibility_preferences,
            category_exclusions
          ''')
          .eq('user_id', userId)
          .maybeSingle();
      final fingerprint = row == null ? 'default' : _fingerprint(row);
      return 'user:$userId:$fingerprint';
    } catch (_) {
      // A signed-in user must never accidentally reuse a cache created for a
      // different preference revision. Skipping the phone cache is safer;
      // the Edge Function can still use its preference-hashed shared cache.
      return null;
    }
  }

  String _fingerprint(Map<String, dynamic> row) {
    const keys = [
      'attraction_interests',
      'food_cuisine_interests',
      'dietary_preferences',
      'dietary_restrictions',
      'accessibility_preferences',
      'category_exclusions',
    ];
    final canonical = <String, List<String>>{};
    for (final key in keys) {
      final values =
          (row[key] as List<dynamic>? ?? const [])
              .map((value) => value.toString().trim().toLowerCase())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      canonical[key] = values;
    }

    // FNV-1a is sufficient here: this is a deterministic local cache key,
    // not an authentication or security hash.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(jsonEncode(canonical))) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
