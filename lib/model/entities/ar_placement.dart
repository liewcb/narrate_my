import 'package:ar_flutter_plugin_plus/datatypes/node_types.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

/// Placement lifecycle state machine
enum PlacementState {
  initializing,
  scanning,
  placing,
  placed,
  error,
}

/// Storytelling narration playback state
enum StoryPlaybackState {
  stopped,
  playing,
  paused,
}

/// Karaoke-style subtitle model for real-time word-by-word follow-along highlighting
class KaraokeSubtitle {
  final String fullText;
  final int spokenCharCount;

  const KaraokeSubtitle({
    required this.fullText,
    required this.spokenCharCount,
  });

  String get spoken => fullText.substring(0, spokenCharCount.clamp(0, fullText.length));
  String get remaining => fullText.substring(spokenCharCount.clamp(0, fullText.length));

  factory KaraokeSubtitle.initial(String text) => KaraokeSubtitle(fullText: text, spokenCharCount: 0);
  factory KaraokeSubtitle.completed(String text) => KaraokeSubtitle(fullText: text, spokenCharCount: text.length);
}

/// Domain model representing a narration story script for landmark interpretation
class StoryScript {
  final String id;
  final String markerId;
  final String landmarkName;
  final String initialGreeting;
  final List<String> narrationParagraphs;
  final String? model3dPath;
  final String? videoUrl;

  const StoryScript({
    required this.id,
    required this.markerId,
    required this.landmarkName,
    required this.initialGreeting,
    required this.narrationParagraphs,
    this.model3dPath,
    this.videoUrl,
  });

  static StoryScript defaultForMarker(String markerId, String name) {
    return StoryScript(
      id: 'default_$markerId',
      markerId: markerId,
      landmarkName: name,
      initialGreeting: "Hello I'm Manja! Ready to tell you an amazing story!",
      narrationParagraphs: const [
        "The attraction content is currently unavailable.",
      ],
      model3dPath: null,
      videoUrl: null,
    );
  }
}

/// Multilingual Voice Option entity supporting English, Malay, Mandarin, Hindi, Spanish
class TTSLanguageOption {
  final String code;
  final String name;
  final String flag;

  const TTSLanguageOption({
    required this.code,
    required this.name,
    required this.flag,
  });

  static const List<TTSLanguageOption> allLanguages = [
    TTSLanguageOption(
      code: 'en-US',
      name: 'English',
      flag: '🇬🇧',
    ),
    TTSLanguageOption(
      code: 'ms-MY',
      name: 'Bahasa Melayu',
      flag: '🇲🇾',
    ),
    TTSLanguageOption(
      code: 'zh-CN',
      name: 'Mandarin (中文)',
      flag: '🇨🇳',
    ),
    TTSLanguageOption(
      code: 'hi-IN',
      name: 'Hindi (हिन्दी)',
      flag: '🇮🇳',
    ),
    TTSLanguageOption(
      code: 'es-ES',
      name: 'Spanish (Español)',
      flag: '🇪🇸',
    ),
  ];

  static TTSLanguageOption fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return allLanguages.first; // Default to English
    final lower = code.toLowerCase().trim();
    if (lower == 'zh' || lower.startsWith('zh')) {
      return allLanguages.firstWhere((l) => l.code == 'zh-CN', orElse: () => allLanguages.first);
    }
    if (lower == 'ms' || lower.startsWith('ms')) {
      return allLanguages.firstWhere((l) => l.code == 'ms-MY', orElse: () => allLanguages.first);
    }
    if (lower == 'es' || lower.startsWith('es')) {
      return allLanguages.firstWhere((l) => l.code == 'es-ES', orElse: () => allLanguages.first);
    }
    if (lower == 'hi' || lower.startsWith('hi')) {
      return allLanguages.firstWhere((l) => l.code == 'hi-IN', orElse: () => allLanguages.first);
    }
    if (lower == 'en' || lower.startsWith('en')) {
      return allLanguages.firstWhere((l) => l.code == 'en-US', orElse: () => allLanguages.first);
    }
    return allLanguages.first;
  }
}

/// Configuration for the 3D Avatar Node to place
class ARAvatarConfig {
  final String modelUri;
  final NodeType nodeType;
  final vector.Vector3 scale;
  final vector.Vector3 position;
  final vector.Vector3 eulerAngles;

  const ARAvatarConfig({
    required this.modelUri,
    required this.nodeType,
    required this.scale,
    required this.position,
    required this.eulerAngles,
  });

  factory ARAvatarConfig.defaultManja({
    String modelUri = 'assets/images/3dmodel/manja.glb',
    NodeType nodeType = NodeType.localGLB,
    double yawDegrees = -15.0, // Calibrated so Manja faces directly forward towards user
  }) {
    return ARAvatarConfig(
      modelUri: modelUri,
      nodeType: nodeType,
      scale: vector.Vector3(0.01, 0.01, 0.01),
      position: vector.Vector3(0, 0, 0),
      eulerAngles: vector.Vector3(
        vector.radians(-90),
        vector.radians(yawDegrees),
        0,
      ),
    );
  }

  ARAvatarConfig copyWithRotation(double newYawDegrees) {
    return ARAvatarConfig(
      modelUri: modelUri,
      nodeType: nodeType,
      scale: scale,
      position: position,
      eulerAngles: vector.Vector3(
        vector.radians(-90),
        vector.radians(newYawDegrees),
        0,
      ),
    );
  }
}
