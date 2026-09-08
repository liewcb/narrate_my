import 'guide_step.dart';

/// AR module's walkthrough: Exploration -> Placement -> Narrations.
///
/// The Narrations section allows users to explore different narrations,
/// watch related videos, and receive recommendations about the attraction.
const List<GuideStep> arGuideSteps = [
  GuideStep(
    imageAsset: 'assets/images/guides/ar_exploration.jpeg',
    titleKey: 'ui.arGuideExplorationTitle',
    bodyKey: 'ui.arGuideExplorationBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ar_placement.jpeg',
    titleKey: 'ui.arGuidePlacementTitle',
    bodyKey: 'ui.arGuidePlacementBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ar_narrations.jpeg',
    titleKey: 'ui.arGuideNarrationsTitle',
    bodyKey: 'ui.arGuideNarrationsBody',
  ),
];