import 'package:supabase_flutter/supabase_flutter.dart';

import '../../entities/ai_attraction_context.dart';
import '../../entities/ai_chat_message.dart';

/// Thin Supabase Functions client for the AI assistant.
///
/// Flutter never contacts Gemini directly. The Edge Function keeps Gemini's
/// API key in Supabase Secrets and returns only a safe text response.
class AiTravelAssistantRemoteDataSource {
  AiTravelAssistantRemoteDataSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> askQuestion({
    required String question,
    required List<AiChatMessage> conversationHistory,
    AiAttractionContext? attractionContext,
  }) async {
    final response = await _client.functions.invoke(
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
