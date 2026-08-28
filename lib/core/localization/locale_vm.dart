import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../model/repositories/adapters/profile_adapter.dart';
import '../../model/repositories/interfaces/profile_repository.dart';
import 'app_localizations.dart';

/// App-wide language state (UC402 A4, REQ_201_2–5) — read once at the
/// `MaterialApp` root (`main.dart`) and applied by setting
/// `AppLocalizations.currentCode`, exactly mirroring how `AccessibilityVm`
/// applies REQ_503_6's Visual Assistance scale via `MediaQuery`. The two
/// are deliberately parallel: a `ChangeNotifier` constructed once, refreshed
/// after a relevant save, and watched via `context.watch<T>()` so the widget
/// tree rebuilds on change.
///
/// Only Module 5's own screens read `AppLocalizations.t()` directly right
/// now. For the language switch to visibly affect AR/Itinerary/Nearby too,
/// each of those modules' screens needs to (a) add its own keys to
/// `AppLocalizations`'s five maps and (b) call `AppLocalizations.t()` for
/// its literal strings while watching this same `LocaleVm` — see the doc
/// comment at the top of `app_localizations.dart` for the exact steps. This
/// class already broadcasts the change app-wide; it's each module's own
/// screens that need to start listening for it.
class LocaleVm extends ChangeNotifier {
  final ProfileRepository _profileRepository;

  LocaleVm({
    ProfileRepository? profileRepository,
  }) : _profileRepository = profileRepository ?? SupabaseProfileRepositoryAdapter() {
    refresh();
    // Guests have no stored `preferred_language` — refresh() itself resets
    // to the default when logged out, so this single listener covers
    // login, logout, AND switching accounts (same pattern as
    // AccessibilityVm's own authStateChanges subscription).
    _profileRepository.authStateChanges.listen((_) => refresh());
  }

  /// Re-reads the current tourist's preferred language and applies it.
  /// Call this after `LanguageVm.save()` succeeds (see `language_screen.dart`)
  /// so the switch takes effect immediately, instead of waiting for the next
  /// login/app restart.
  Future<void> refresh() async {
    if (!_profileRepository.isLoggedIn) {
      _apply(Module5Constants.defaultLanguageCode);
      return;
    }
    try {
      final profile = await _profileRepository.fetchProfile();
      _apply(profile.preferredLanguage);
    } catch (_) {
      // Best-effort: a failed refresh just leaves the language as it was —
      // never worth surfacing an error banner for a background sync.
    }
  }

  void _apply(String? code) {
    final resolved = Module5Constants.supportedLanguages.containsKey(code)
        ? code!
        : Module5Constants.defaultLanguageCode;
    if (resolved != AppLocalizations.currentCode) {
      AppLocalizations.currentCode = resolved;
      notifyListeners();
    }
  }
}
