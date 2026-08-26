import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';
import '../../repositories/interfaces/ai_travel_assistant_repository.dart';

/// UC500 business rules that do not belong to the widget or transport layer.
class AiTravelAssistantService {
  const AiTravelAssistantService(this._repository);

  final AiTravelAssistantRepository _repository;

  Future<String> answerQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) {
    final normalizedQuestion = question.trim();

    if (normalizedQuestion.isEmpty) {
      throw const AiAssistantValidationException(
        'Please type a question before sending.',
      );
    }

    // Avoid an unexpectedly large request while supporting normal questions.
    if (normalizedQuestion.length > 200) {
      throw const AiAssistantValidationException(
        'Please shorten your question to 200 characters or fewer.',
      );
    }

    return _repository.askQuestion(
      question: normalizedQuestion,
      conversationHistory: conversationHistory,
      attractionContext: attractionContext,
    );
  }
}

class AiAssistantValidationException implements Exception {
  const AiAssistantValidationException(this.message);

  final String message;
}
