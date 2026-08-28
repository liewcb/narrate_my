import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';

abstract class AiTravelAssistantRepository {
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  });
}
