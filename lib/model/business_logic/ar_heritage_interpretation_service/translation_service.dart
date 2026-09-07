import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../entities/ar_placement.dart';
import '../../../core/config/api_keys.dart';

/// Business logic service matching REQ_201_4:
/// "The system shall translate the attraction content into the determined language before narration generation."
class TranslationService {
  final Map<String, String> _cache = {};

  /// Translates [text] to [targetLangCode] (e.g. 'zh-CN', 'ms', 'es', 'hi', 'en').
  Future<String> translateText(String text, String targetLangCode) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;

    final target = _normalizeLangCode(targetLangCode);
    if (target == 'en') return text;

    final cacheKey = '${target}_${trimmed.hashCode}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 1. Try Google Translate free endpoint
    try {
      final translated = await _translateViaGoogle(trimmed, target);
      if (translated.isNotEmpty) {
        _cache[cacheKey] = translated;
        return translated;
      }
    } catch (e) {
      debugPrint('Google Translate notice: $e');
    }

    // 2. Try B.AI / AI Gateway Fallback
    try {
      final aiTranslated = await _translateViaAi(trimmed, target);
      if (aiTranslated.isNotEmpty) {
        _cache[cacheKey] = aiTranslated;
        return aiTranslated;
      }
    } catch (e) {
      debugPrint('AI Translation notice: $e');
    }

    // 3. Fallback to original text if offline
    return text;
  }

  /// Translates an entire [StoryScript] into [targetLangCode].
  Future<StoryScript> translateStoryScript(StoryScript script, String targetLangCode) async {
    final target = _normalizeLangCode(targetLangCode);
    if (target == 'en') return script;

    try {
      final translatedGreeting = await translateText(script.initialGreeting, target);
      final translatedParagraphs = <String>[];
      for (final p in script.narrationParagraphs) {
        final transP = await translateText(p, target);
        translatedParagraphs.add(transP);
      }

      return StoryScript(
        id: script.id,
        markerId: script.markerId,
        landmarkName: script.landmarkName,
        initialGreeting: translatedGreeting,
        narrationParagraphs: translatedParagraphs,
        model3dPath: script.model3dPath,
        videoUrl: script.videoUrl,
        videoUrlBackup: script.videoUrlBackup,
      );
    } catch (e) {
      debugPrint('translateStoryScript notice: $e');
      return script;
    }
  }

  String _normalizeLangCode(String code) {
    final lower = code.toLowerCase().trim();
    if (lower.startsWith('zh')) return 'zh-CN';
    if (lower.startsWith('ms')) return 'ms';
    if (lower.startsWith('es')) return 'es';
    if (lower.startsWith('hi')) return 'hi';
    if (lower.startsWith('en')) return 'en';
    return 'en';
  }

  Future<String> _translateViaGoogle(String text, String target) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$target&dt=t',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final postBody = 'q=${Uri.encodeQueryComponent(text)}';
      request.write(postBody);
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final buffer = StringBuffer();
          for (final item in decoded[0]) {
            if (item is List && item.isNotEmpty && item[0] != null) {
              buffer.write(item[0].toString());
            }
          }
          return buffer.toString().trim();
        }
      }
    } finally {
      client.close();
    }
    return '';
  }

  Future<String> _translateViaAi(String text, String target) async {
    final apiKey = ApiKeys.baiApiKey.trim();
    if (apiKey.isEmpty) return '';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('https://api.b.ai/v1/chat/completions');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $apiKey');

      final langName = target == 'zh-CN'
          ? 'Simplified Chinese'
          : target == 'ms'
              ? 'Malay'
              : target == 'es'
                  ? 'Spanish'
                  : target == 'hi'
                      ? 'Hindi'
                      : 'English';

      final payload = jsonEncode({
        "model": ApiKeys.baiModel,
        "messages": [
          {
            "role": "system",
            "content":
                "You are a professional translator. Translate the given text accurately into $langName. Return ONLY the translated text without notes or quotes."
          },
          {
            "role": "user",
            "content": text
          }
        ],
        "temperature": 0.3
      });

      request.write(payload);
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        final content = decoded['choices']?[0]?['message']?['content']?.toString().trim();
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
    } finally {
      client.close();
    }
    return '';
  }
}
