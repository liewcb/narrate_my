/// A single step in a module's guided walkthrough: an illustrative image
/// plus a title/body looked up from [AppLocalizations] so every module's
/// guide follows the app's language setting automatically.
///
/// Shared across modules — AR's steps live in `ar_guide_steps.dart`; a
/// future module (Itinerary, Nearby, ...) adds its own `<module>_guide_
/// steps.dart` file of these and registers itself with [kGuidanceModules]
/// in `guidance_screen.dart`. Nothing in `guide_walkthrough_screen.dart`
/// needs to change.
class GuideStep {
  final String imageAsset;
  final String titleKey;
  final String bodyKey;

  const GuideStep({
    required this.imageAsset,
    required this.titleKey,
    required this.bodyKey,
  });
}