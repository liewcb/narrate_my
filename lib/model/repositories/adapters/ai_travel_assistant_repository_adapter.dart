import '../../data_sources/remote/ai_travel_assistant_remote_data_source.dart';
import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';
import '../interfaces/ai_travel_assistant_repository.dart';

class SupabaseAiTravelAssistantRepositoryAdapter
    implements AiTravelAssistantRepository {
  SupabaseAiTravelAssistantRepositoryAdapter({
    AiTravelAssistantRemoteDataSource? dataSource,
  }) : _dataSource = dataSource ?? AiTravelAssistantRemoteDataSource();

  final AiTravelAssistantRemoteDataSource _dataSource;

  @override
  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) {
    return _dataSource.askQuestion(
      question: question,
      conversationHistory: conversationHistory,
      attractionContext: attractionContext,
    );
  }
}
