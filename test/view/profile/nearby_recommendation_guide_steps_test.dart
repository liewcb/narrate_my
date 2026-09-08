import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/view/profile/widgets/nearby_recommendation_guide_steps.dart';

void main() {
  test('Nearby recommendation guide contains six available screenshots', () {
    expect(nearbyRecommendationGuideSteps, hasLength(6));

    for (final step in nearbyRecommendationGuideSteps) {
      expect(
        File(step.imageAsset).existsSync(),
        isTrue,
        reason: 'Missing guide image: ${step.imageAsset}',
      );
      expect(step.titleKey, startsWith('ui.nearbyGuide'));
      expect(step.bodyKey, startsWith('ui.nearbyGuide'));
    }
  });
}
