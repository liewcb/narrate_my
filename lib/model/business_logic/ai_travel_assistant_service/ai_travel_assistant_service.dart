import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';
import '../../repositories/interfaces/ai_travel_assistant_repository.dart';

/// UC500 business rules that do not belong to the widget or transport layer.
class AiTravelAssistantService {
  const AiTravelAssistantService(this._repository);

  static const englishOnlyMessage =
      'Please resubmit your question in English.';
  static const englishOnlyToken = '__ENGLISH_ONLY__';

  final AiTravelAssistantRepository _repository;

  /// Validates before the ViewModel adds the tourist message or calls Supabase.
  String validateQuestion(String question) {
    final normalizedQuestion = question.trim();

    if (normalizedQuestion.isEmpty) {
      throw const AiAssistantValidationException(
        'Please type a question before sending.',
      );
    }

    if (normalizedQuestion.length > 200) {
      throw const AiAssistantValidationException(
        'Please shorten your question to 200 characters or fewer.',
      );
    }

    if (_containsUnsupportedScript(normalizedQuestion)) {
      throw const AiAssistantValidationException(englishOnlyMessage);
    }

    return normalizedQuestion;
  }

  Future<String> answerQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    final normalizedQuestion = validateQuestion(question);

    final answer = await _repository.askQuestion(
      question: normalizedQuestion,
      conversationHistory: conversationHistory,
      attractionContext: attractionContext,
    );

    // The Edge Function uses this private token when it detects a language
    // that cannot be identified locally (for example, a Latin-script language).
    if (answer.trim() == englishOnlyToken) {
      throw const AiAssistantValidationException(englishOnlyMessage);
    }

    return answer;
  }

  bool _containsUnsupportedScript(String text) {
    for (final rune in text.runes) {
      final isUnsupported =
          (rune >= 0x0370 && rune <= 0x03FF) || // Greek
              (rune >= 0x0400 && rune <= 0x052F) || // Cyrillic
              (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
              (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
              (rune >= 0x0750 && rune <= 0x077F) ||
              (rune >= 0x08A0 && rune <= 0x08FF) ||
              (rune >= 0x0900 && rune <= 0x0D7F) || // Indic scripts
              (rune >= 0x0E00 && rune <= 0x0E7F) || // Thai/Lao
              (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
              (rune >= 0x3040 && rune <= 0x30FF) || // Japanese Kana
              (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
              (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified
              (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul syllables
              (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility
              (rune >= 0x20000 && rune <= 0x2FA1F); // CJK extensions

      if (isUnsupported) return true;
    }

    return false;
  }
}

class AiAssistantValidationException implements Exception {
  const AiAssistantValidationException(this.message);

  final String message;
}
