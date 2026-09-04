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
  bool _isSummarizing = false;
  String? _errorMessage;
  String? _conversationSummary;
  String? _summaryErrorMessage;

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  AiAttractionContext? get attractionContext => _attractionContext;
  bool get isSending => _isSending;
  bool get isSummarizing => _isSummarizing;
  String? get errorMessage => _errorMessage;
  String? get conversationSummary => _conversationSummary;
  String? get summaryErrorMessage => _summaryErrorMessage;
  bool get canSummarize =>
      _messages.any((message) => message.sender == AiChatMessageSender.tourist);

  Future<void> sendQuestion(String question) async {
    if (_isSending || _isSummarizing) return;

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
    _conversationSummary = null;
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

  /// Generates a read-only recap without adding the recap itself to chat
  /// history. It is intentionally held only in memory for this session.
  Future<void> generateSummary() async {
    if (_isSending || _isSummarizing) return;

    if (!canSummarize) {
      _summaryErrorMessage =
      'Send at least one question before creating a conversation summary.';
      notifyListeners();
      return;
    }

    const summaryQuestion =
        'Summarise this travel conversation in 3 to 5 concise factual bullet '
        'points. Include useful travel information, the tourist’s preferences '
        'or decisions, and any unresolved question. Do not invent facts.';

    _isSummarizing = true;
    _summaryErrorMessage = null;
    notifyListeners();

    try {
      debugPrint('Summary: starting Edge Function request');

      _conversationSummary = await _service.answerQuestion(
        question: summaryQuestion,
        conversationHistory: List<AiChatMessage>.from(_messages),
        attractionContext: _attractionContext,
      );

      debugPrint('Summary: Edge Function response received');
    } on AiAssistantValidationException catch (error, stackTrace) {
      debugPrint('AI summary validation failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      _summaryErrorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AI summary request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _summaryErrorMessage =
      'I’m unable to create a summary right now. Please try again later.';
    } finally {
      _isSummarizing = false;
      notifyListeners();
    }
  }

  void resetConversation() {
    _messages = [_greeting()];
    _attractionContext = null;
    _errorMessage = null;
    _conversationSummary = null;
    _summaryErrorMessage = null;
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

