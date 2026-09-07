import 'package:flutter_test/flutter_test.dart';
import 'package:narrate_my/model/business_logic/ai_travel_assistant_service/ai_travel_assistant_service.dart';
import 'package:narrate_my/model/entities/ai_attraction_context.dart';
import 'package:narrate_my/model/entities/ai_chat_message.dart';
import 'package:narrate_my/model/repositories/interfaces/ai_assist/ai_travel_assistant_repository.dart';

class _FakeRepository implements AiTravelAssistantRepository {
  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async => 'answer';
}

class _RecordingRepository implements AiTravelAssistantRepository {
  String? receivedQuestion;

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    receivedQuestion = question;
    return 'answer';
  }
}

void main() {
  final service = AiTravelAssistantService(_FakeRepository());

  test('accepts the five supported language scripts', () {
    expect(service.validateQuestion('Where is Batu Caves?'), isNotEmpty);
    expect(service.validateQuestion('请介绍黑风洞'), isNotEmpty);
    expect(service.validateQuestion('Di manakah Batu Caves?'), isNotEmpty);
    expect(service.validateQuestion('¿Dónde está Batu Caves?'), isNotEmpty);
    expect(service.validateQuestion('बातू गुफाएँ कहाँ हैं?'), isNotEmpty);
  });

  test('rejects a clearly unsupported script', () {
    expect(
      () => service.validateQuestion('Где находится это место?'),
      throwsA(
        isA<AiAssistantValidationException>().having(
          (error) => error.message,
          'message',
          AiTravelAssistantService.supportedLanguagesMessage,
        ),
      ),
    );
  });

  test('keeps an instructed repository request within 200 characters', () async {
    final repository = _RecordingRepository();
    final instructedService = AiTravelAssistantService(repository);
    const question = 'Suggest some restaurants nearby me';

    await instructedService.answerQuestion(
      question: question,
      conversationHistory: const [],
      requestInstruction:
          'Nearby origin: user GPS (3.20100, 101.72000). '
          'Ignore any selected attraction. Verified nearby places only: '
          'A Restaurant With A Very Long Name; Another Restaurant With A Very '
          'Long Name; A Third Restaurant With A Very Long Name.',
    );

    expect(repository.receivedQuestion, isNotNull);
    expect(repository.receivedQuestion!.length, lessThanOrEqualTo(200));
    expect(repository.receivedQuestion, endsWith('User question: $question'));
    expect(repository.receivedQuestion, contains('user GPS'));
  });
}
