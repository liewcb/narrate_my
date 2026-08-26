import 'package:flutter/foundation.dart';

import '../../model/business_logic/ai_travel_assistant_service/ai_travel_assistant_service.dart';
import '../../model/entities/ai_attraction_context.dart';
import '../../model/entities/ai_chat_message.dart';
import '../../model/repositories/adapters/ai_travel_assistant_repository_adapter.dart';
import '../../model/repositories/interfaces/ai_travel_assistant_repository.dart';

/// ChangeNotifier for UC500's chat state and Gemini requests.
class AiTravelAssistantViewModel extends ChangeNotifier {
  AiTravelAssistantViewModel({
    AiTravelAssistantRepository? repository,
    AiAttractionContext? initialContext,
  })  : _service = AiTravelAssistantService(
    repository ?? SupabaseAiTravelAssistantRepositoryAdapter(),
  ),
        _attractionContext = initialContext {
    _messages = [_greeting()];
  }

  final AiTravelAssistantService _service;

  late List<AiChatMessage> _messages;
  AiAttractionContext? _attractionContext;
  bool _isSending = false;
  String? _errorMessage;

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  AiAttractionContext? get attractionContext => _attractionContext;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;

  Future<void> sendQuestion(String question) async {
    if (_isSending) return;

    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      _addSystemMessage('Please type a question before sending.');
      return;
    }

    // Keep only the prior messages as history. The Edge Function receives the
    // new question separately, so it is not sent twice to Gemini.
    final historyBeforeQuestion = List<AiChatMessage>.from(_messages);

    _messages.add(
      AiChatMessage(
        text: normalizedQuestion,
        sender: AiChatMessageSender.tourist,
      ),
    );
    _isSending = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final answer = await _service.answerQuestion(
        question: normalizedQuestion,
        conversationHistory: historyBeforeQuestion,
        attractionContext: _attractionContext,
      );
      _messages.add(
        AiChatMessage(
          text: answer,
          sender: AiChatMessageSender.assistant,
        ),
      );
    } on AiAssistantValidationException catch (error) {
      _errorMessage = error.message;
      _addSystemMessage(error.message, shouldNotify: false);
    } catch (_) {
      const message = 'I’m unable to answer right now. Please try again later.';
      _errorMessage = message;
      _addSystemMessage(message, shouldNotify: false);
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void resetConversation() {
    _messages = [_greeting()];
    _attractionContext = null;
    _errorMessage = null;
    notifyListeners();
  }

  void setAttractionContext(AiAttractionContext? context) {
    _attractionContext = context;
    notifyListeners();
  }

  void _addSystemMessage(String message, {bool shouldNotify = true}) {
    _messages.add(
      AiChatMessage(text: message, sender: AiChatMessageSender.system),
    );
    if (shouldNotify) notifyListeners();
  }

  AiChatMessage _greeting() => AiChatMessage(
    text: 'Here’s Manja, Your AI Travel Assistant!',
    sender: AiChatMessageSender.assistant,
  );
}
