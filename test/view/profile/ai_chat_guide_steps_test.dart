import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/view/profile/widgets/ai_chat_guide_steps.dart';

void main() {
  test('AI Chat guide contains five available screenshots', () {
    expect(aiChatGuideSteps, hasLength(5));

    for (final step in aiChatGuideSteps) {
      expect(
        File(step.imageAsset).existsSync(),
        isTrue,
        reason: 'Missing guide image: ${step.imageAsset}',
      );
      expect(step.titleKey, startsWith('ui.aiChatGuide'));
      expect(step.bodyKey, startsWith('ui.aiChatGuide'));
    }
  });
}
