import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';
import '../../repositories/interfaces/ai_assist/ai_travel_assistant_repository.dart';

/// UC500 business rules that do not belong to the widget or transport layer.
class AiTravelAssistantService {
  const AiTravelAssistantService(this._repository);

  static const _maximumRepositoryQuestionLength = 200;

  static const supportedLanguagesMessage =
      'Please use English, Mandarin, Malay, Spanish, or Hindi.';

  // Kept for compatibility with the currently deployed Edge Function.
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
      throw const AiAssistantValidationException(supportedLanguagesMessage);
    }

    return normalizedQuestion;
  }

  Future<String> answerQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
    String? requestInstruction,
  }) async {
    final normalizedQuestion = validateQuestion(question);
    final cleanInstruction = requestInstruction?.trim();
    final repositoryQuestion = _buildRepositoryQuestion(
      normalizedQuestion,
      cleanInstruction,
    );

    final answer = await _repository.askQuestion(
      question: repositoryQuestion,
      conversationHistory: conversationHistory,
      attractionContext: attractionContext,
    );

    // The deployed Edge Function still uses this legacy token when it detects
    // an unsupported language that cannot be identified locally.
    if (answer.trim() == englishOnlyToken) {
      throw const AiAssistantValidationException(supportedLanguagesMessage);
    }

    return answer;
  }

  String _buildRepositoryQuestion(String question, String? instruction) {
    if (instruction == null || instruction.isEmpty) return question;

    final suffix = '\nUser question: $question';
    final instructionBudget = _maximumRepositoryQuestionLength - suffix.length;
    if (instructionBudget <= 0) return question;

    final boundedInstruction = instruction.length <= instructionBudget
        ? instruction
        : _truncateAtWordBoundary(instruction, instructionBudget);
    if (boundedInstruction.isEmpty) return question;

    return '$boundedInstruction$suffix';
  }

  String _truncateAtWordBoundary(String value, int maximumLength) {
    if (maximumLength <= 0) return '';
    if (value.length <= maximumLength) return value;

    final shortened = value.substring(0, maximumLength).trimRight();
    final finalSpace = shortened.lastIndexOf(' ');
    return (finalSpace > 0 ? shortened.substring(0, finalSpace) : shortened)
        .trimRight();
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
          // Devanagari (0900-097F) is allowed for Hindi. Other Indic
          // scripts remain outside the assistant's supported set.
          (rune >= 0x0980 && rune <= 0x0D7F) ||
          (rune >= 0x0E00 && rune <= 0x0E7F) || // Thai/Lao
          (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
          (rune >= 0x3040 && rune <= 0x30FF) || // Japanese Kana
          (rune >= 0xAC00 && rune <= 0xD7AF); // Hangul syllables

      if (isUnsupported) return true;
    }

    return false;
  }
}

class AiAssistantValidationException implements Exception {
  const AiAssistantValidationException(this.message);

  final String message;
}
