// test_openrouter_cohere.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/api_keys.dart';

class AIService {
  /// 1. OpenRouter (Free Tier)
  static Future<String?> callOpenRouter({
    required String prompt,
    String model = 'openrouter/free',
  }) async {
    final apiKey = ApiKeys.openRouterApiKey.trim();

    if (apiKey.isEmpty) {
      print('❌ OpenRouter API key is empty. Check api_keys.dart.');
      return null;
    }

    final url = Uri.parse(
      'https://openrouter.ai/api/v1/chat/completions',
    );

    try {
      final response = await http
          .post(
        url,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['choices']?[0]?['message']?['content'] as String?;
      }

      print('❌ OpenRouter Error (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      print('❌ OpenRouter Exception: $e');
      return null;
    }
  }

  /// 2. Cohere API (v2 Chat)
  // static Future<String?> callCohere({
  //   required String prompt,
  //   String model = 'command-r-08-2024',
  // }) async {
  //   final apiKey = ApiKeys.cohereApiKey.trim();
  //   final Uri url = Uri.parse('https://api.cohere.com/v2/chat');
  //
  //   try {
  //     final response = await http
  //         .post(
  //       url,
  //       headers: {
  //         'Authorization': 'Bearer $apiKey',
  //         'Content-Type': 'application/json',
  //       },
  //       body: jsonEncode({
  //         'model': model,
  //         'messages': [
  //           {'role': 'user', 'content': prompt}
  //         ],
  //       }),
  //     )
  //         .timeout(const Duration(seconds: 15));
  //
  //     if (response.statusCode == 200) {
  //       final data = jsonDecode(response.body);
  //       return data['message']?['content']?[0]?['text'];
  //     } else {
  //       print('❌ Cohere Error (${response.statusCode}): ${response.body}');
  //       return null;
  //     }
  //   } catch (e) {
  //     print('❌ Cohere Exception: $e');
  //     return null;
  //   }
  // }

  /// Fallback Runner
  static Future<String> generate(String prompt) async {
    print('🚀 [1/2] Trying OpenRouter (Free)...');
    String? response = await callOpenRouter(prompt: prompt);

    if (response != null && response.trim().isNotEmpty) {
      return '🟢 [OpenRouter Success]:\n$response';
    }

    print('\n🔄 OpenRouter failed. [2/2] Switching to Cohere Fallback...');
    // response = await callCohere(prompt: prompt);
    if (response != null && response.trim().isNotEmpty) {
      return '🟢 [Cohere Success]:\n$response';
    }

    return '❌ Both OpenRouter and Cohere failed.';
  }
}

void main() async {
  const prompt = 'What is the best time to visit Batu Caves? Give a short 2-sentence summary.';

  print('==================================================');
  print('🧪 TESTING OPENROUTER & COHERE INTEGRATION');
  print('==================================================\n');

  final result = await AIService.generate(prompt);

  print('\n---------------- RESULT ----------------');
  print(result);
  print('----------------------------------------');
}