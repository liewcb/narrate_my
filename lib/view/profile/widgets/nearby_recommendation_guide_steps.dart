import 'guide_step.dart';

/// Nearby module walkthrough: discover places, inspect their details, use
/// map/AR/bookmark actions, and find saved places again from Profile.
const List<GuideStep> nearbyRecommendationGuideSteps = [
  GuideStep(
    imageAsset:
        'assets/images/guides/nearby recommendation/nearby_recommendation_map.jpg',
    titleKey: 'ui.nearbyGuideMapTitle',
    bodyKey: 'ui.nearbyGuideMapBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/nearby recommendation/details_sheet.jpg',
    titleKey: 'ui.nearbyGuideDetailsTitle',
    bodyKey: 'ui.nearbyGuideDetailsBody',
  ),
  GuideStep(
    imageAsset:
        'assets/images/guides/nearby recommendation/scroll_down_for_actions.jpg',
    titleKey: 'ui.nearbyGuideActionsTitle',
    bodyKey: 'ui.nearbyGuideActionsBody',
  ),
  GuideStep(
    imageAsset:
        'assets/images/guides/nearby recommendation/must_be_within_ar_area_to_trigger_ar_function.jpg',
    titleKey: 'ui.nearbyGuideArTitle',
    bodyKey: 'ui.nearbyGuideArBody',
  ),
  GuideStep(
    imageAsset:
        'assets/images/guides/nearby recommendation/must_login_to_bookmark.jpg',
    titleKey: 'ui.nearbyGuideLoginTitle',
    bodyKey: 'ui.nearbyGuideLoginBody',
  ),
  GuideStep(
    imageAsset:
        'assets/images/guides/nearby recommendation/view_bookmark_under_profile_after_login.jpg',
    titleKey: 'ui.nearbyGuideBookmarksTitle',
    bodyKey: 'ui.nearbyGuideBookmarksBody',
  ),
];
