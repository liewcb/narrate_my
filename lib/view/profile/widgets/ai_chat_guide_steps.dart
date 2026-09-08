import 'guide_step.dart';

/// AI Chat walkthrough: open Manja, start a conversation, ask a question,
/// use verified place actions, and review the saved conversation summary.
const List<GuideStep> aiChatGuideSteps = [
  GuideStep(
    imageAsset: 'assets/images/guides/ai chat/open_ai_chat.jpg',
    titleKey: 'ui.aiChatGuideOpenTitle',
    bodyKey: 'ui.aiChatGuideOpenBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ai chat/empty_chat.jpg',
    titleKey: 'ui.aiChatGuideStartTitle',
    bodyKey: 'ui.aiChatGuideStartBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ai chat/ask_question.jpg',
    titleKey: 'ui.aiChatGuideAskTitle',
    bodyKey: 'ui.aiChatGuideAskBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ai chat/verified_place_actions.jpg',
    titleKey: 'ui.aiChatGuideActionsTitle',
    bodyKey: 'ui.aiChatGuideActionsBody',
  ),
  GuideStep(
    imageAsset: 'assets/images/guides/ai chat/conversation_summary.jpg',
    titleKey: 'ui.aiChatGuideSummaryTitle',
    bodyKey: 'ui.aiChatGuideSummaryBody',
  ),
];
