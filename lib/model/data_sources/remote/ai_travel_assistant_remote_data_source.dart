import '../../../core/services/database_manager.dart';
import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';

class AiTravelAssistantRemoteDataSource {
  AiTravelAssistantRemoteDataSource({
    DatabaseManager? databaseManager,
  }) : _databaseManager = databaseManager ?? DatabaseManager();

  final DatabaseManager _databaseManager;

  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    final response = await _databaseManager.remote.client.functions.invoke(
      'ai-travel-assistant',
      body: {
        'question': question,
        'context': attractionContext?.toJson(),
        'history': conversationHistory.map(_historyJson).toList(),
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Invalid AI Assistant response.');
    }

    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const FormatException('AI Assistant returned an empty response.');
    }

    return answer.trim();
  }

  Map<String, String> _historyJson(AiChatMessage message) => {
    'sender': message.sender.name,
    'text': message.text,
  };
}