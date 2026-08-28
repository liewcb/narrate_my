import 'package:flutter/foundation.dart';

import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';

/// App-wide accessibility state, read once at the `MaterialApp` root
/// (`main.dart`) and applied via a `MediaQuery` text-scale override — this
/// is the one Accessibility Preference (REQ_503_6) that can be made to do
/// something real without touching any other teammate's module: turning on
/// Visual Assistance scales text everywhere, automatically, because every
/// `Text` widget in the app already reads its scale from `MediaQuery`.
///
/// Hearing Assistance would mean captions alongside the AR module's audio
/// narration — that lives in whoever owns AR playback, not here, so it
/// stays a stored preference only for now. Wheelchair Accessible / Mobility
/// Assistance affect which recommendations get surfaced (Module 3/4's
/// territory) — also stored-preference-only, with no app-wide behavior of
/// their own.
class AccessibilityVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  /// How much larger text gets when Visual Assistance is on — a flat
  /// multiplier on top of whatever text-scale the device/OS already
  /// requests, so a tourist who also has a system-level "larger text"
  /// setting isn't fighting two separate overrides.
  static const double visualAssistanceScale = 1.3;

  bool visualAssistanceEnabled = false;

  AccessibilityVm({
    ProfileRepository? profileRepository,
  }) : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    refresh();
    // Guests have no stored preferences at all — refresh() itself resets
    // visualAssistanceEnabled to false when logged out, so this single
    // listener covers login, logout, AND switching accounts.
    _profileRepository.authStateChanges.listen((_) => refresh());
  }

  /// Re-reads the current tourist's Accessibility Preferences. Call this
  /// after `PreferencesVm.save()` succeeds (Preferences screen and the
  /// onboarding screen both do) so a toggle takes effect immediately,
  /// instead of waiting for the next login.
  Future<void> refresh() async {
    if (!_profileRepository.isLoggedIn) {
      if (visualAssistanceEnabled) {
        visualAssistanceEnabled = false;
        notifyListeners();
      }
      return;
    }
    try {
      final preferences = await _profileRepository.fetchPreferences();
      final enabled = preferences.accessibilityPreferences.contains('Visual Assistance');
      if (enabled != visualAssistanceEnabled) {
        visualAssistanceEnabled = enabled;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: a failed refresh just leaves text scale as it was —
      // never worth surfacing an error banner for a background sync.
    }
  }
}
