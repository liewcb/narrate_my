import 'guide_step.dart';

/// AR module's walkthrough: Exploration -> Placement -> Storytelling,
/// mirroring `lib/view/ar/ar_exploration/`, `.../ar_placement/`, and the
/// `ArStorytellingPanel` widget those screens open.
///
/// To add a step: drop an image in `assets/images/guides/`, add its
/// title/body strings to `AppLocalizations`, and append an entry here.
const List<GuideStep> kArGuideSteps = [
  GuideStep(
    imageAsset: 'assets/images/guides/ar_exploration.jpg',
    titleKey: 'ui.arGuideExplorationTitle',
    bodyKey: 'ui.arGuideExplorationBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ar_placement.jpg',
    titleKey: 'ui.arGuidePlacementTitle',
    bodyKey: 'ui.arGuidePlacementBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ar_storytelling.jpg',
    titleKey: 'ui.arGuideStorytellingTitle',
    bodyKey: 'ui.arGuideStorytellingBody',
  ),
];