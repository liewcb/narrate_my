import 'dart:convert';
import '../entities/ar_object.dart';
import '../entities/ar_placement.dart';

/// Raw mapping of a Supabase query result joining `Marker` with its
/// embedded `Attraction` row(s):
///
/// ```
/// supabase.from('Marker').select('*, Attraction(*)')
/// ```
///
/// Kept separate from [ARMarker] so Supabase's on-the-wire JSON shape
/// (snake_case, embedded lists, nullable json labels) never leaks into
/// the rest of the app.
class HeritageSiteDto {
  final String markerId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? targetBearing;
  final int? activationRadius;

  final String? attractionId;
  final String? attractionName;
  final String? attractionContent;
  final String? model3dUrl;
  final String? videoUrl;
  final String? sourceUrl;
  final List<String> labels;

  const HeritageSiteDto({
    required this.markerId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.targetBearing,
    this.activationRadius,
    this.attractionId,
    this.attractionName,
    this.attractionContent,
    this.model3dUrl,
    this.videoUrl,
    this.sourceUrl,
    this.labels = const [],
  });

  static double _parseDouble(dynamic val, {double fallback = 0.0}) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static double? _parseDoubleNullable(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  static int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  static List<String> _parseLabels(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return [raw];
    }
    return const [];
  }

  factory HeritageSiteDto.fromJson(Map<String, dynamic> json) {
    // Embedded Attraction comes back as a List (PostgREST convention for
    // one-to-many via FK), even though in practice each Marker has one.
    final attractionsRaw = json['Attraction'];
    final Map<String, dynamic>? attraction = (attractionsRaw is List && attractionsRaw.isNotEmpty)
        ? attractionsRaw.first as Map<String, dynamic>
        : (attractionsRaw is Map<String, dynamic> ? attractionsRaw : null);

    return HeritageSiteDto(
      markerId: json['marker_id']?.toString() ?? '',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      altitude: _parseDoubleNullable(json['altitude']),
      targetBearing: _parseDoubleNullable(json['target_bearing']),
      activationRadius: _parseInt(json['activation_radius']),
      attractionId: attraction?['attraction_id'] as String?,
      attractionName: attraction?['name'] as String?,
      attractionContent: attraction?['attraction_content'] as String?,
      model3dUrl: attraction?['model_3d_url'] as String?,
      videoUrl: attraction?['video_url'] as String?,
      sourceUrl: attraction?['source_url'] as String?,
      labels: _parseLabels(attraction?['labels']),
    );
  }

  /// Construct directly from an Attraction table row
  factory HeritageSiteDto.fromAttractionJson(Map<String, dynamic> json) {
    return HeritageSiteDto(
      markerId: json['marker_id']?.toString() ?? '',
      latitude: 0.0,
      longitude: 0.0,
      attractionId: json['attraction_id'] as String?,
      attractionName: json['name'] as String?,
      attractionContent: json['attraction_content'] as String?,
      model3dUrl: json['model_3d_url'] as String?,
      videoUrl: json['video_url'] as String?,
      sourceUrl: json['source_url'] as String?,
      labels: _parseLabels(json['labels']),
    );
  }

  ARMarker toEntity({required double fallbackActivationRadiusMeters}) {
    return ARMarker(
      markerId: markerId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      targetBearing: targetBearing,
      activationRadiusMeters: (activationRadius ?? fallbackActivationRadiusMeters).toDouble(),
      name: attractionName ?? 'Unnamed landmark',
      description: (attractionContent != null && attractionContent!.trim().isNotEmpty)
          ? attractionContent
          : "The attraction content is currently unavailable.",
      labels: labels,
    );
  }

  /// Splits long continuous attraction text into readable 3~4 line subtitle pages
  static List<String> _splitIntoBiteSizedPages(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return [];

    // 1. Break by explicit line breaks first (if formatted in DB)
    final rawBlocks = trimmed
        .split(RegExp(r'\r?\n\r?\n|\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final List<String> pages = [];

    for (final block in rawBlocks) {
      // If block is already around 3-4 lines (<= 160 chars), keep intact
      if (block.length <= 160) {
        pages.add(block);
        continue;
      }

      // 2. Split block into sentences (supporting English . ! ? and Chinese 。！？)
      final sentenceRegex = RegExp(r'(?<=[.!?。！？])\s+');
      final sentences = block
          .split(sentenceRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (sentences.length <= 1) {
        // Fallback for long run-on sentences without punctuation: chunk by ~25-30 words
        final words = block.split(RegExp(r'\s+'));
        for (int i = 0; i < words.length; i += 26) {
          final end = (i + 26 < words.length) ? i + 26 : words.length;
          pages.add(words.sublist(i, end).join(' '));
        }
        continue;
      }

      // 3. Group sentences into 3~4 line chunks (~150 to 180 characters per page)
      String currentChunk = '';
      for (final sentence in sentences) {
        if (currentChunk.isEmpty) {
          currentChunk = sentence;
        } else if ((currentChunk.length + sentence.length) <= 170) {
          currentChunk += ' $sentence';
        } else {
          pages.add(currentChunk.trim());
          currentChunk = sentence;
        }
      }
      if (currentChunk.isNotEmpty) {
        pages.add(currentChunk.trim());
      }
    }

    return pages;
  }

  StoryScript toStoryScript({String? fallbackLandmarkName}) {
    final landmark = (attractionName != null && attractionName!.trim().isNotEmpty)
        ? attractionName!
        : (fallbackLandmarkName ?? 'Heritage Landmark');

    List<String> paragraphs = [];
    if (attractionContent != null && attractionContent!.trim().isNotEmpty) {
      paragraphs = _splitIntoBiteSizedPages(attractionContent!);
    }

    final bool hasContent = paragraphs.isNotEmpty;
    if (!hasContent) {
      paragraphs = [
        "The attraction content is currently unavailable.",
      ];
    }

    String? validModel3d = (model3dUrl != null && model3dUrl!.trim().isNotEmpty)
        ? model3dUrl!.trim()
        : null;

    if (validModel3d != null) {
      if (validModel3d.startsWith('assets/')) {
        // already has assets prefix
      } else if (validModel3d.startsWith('3dmodel/')) {
        validModel3d = 'assets/images/$validModel3d';
      } else {
        validModel3d = 'assets/images/3dmodel/$validModel3d';
      }
    }

    final validVideoUrl = (videoUrl != null && videoUrl!.trim().isNotEmpty)
        ? videoUrl!.trim()
        : null;

    return StoryScript(
      id: attractionId ?? 'story_$markerId',
      markerId: markerId,
      landmarkName: landmark,
      initialGreeting: hasContent
          ? "Hello I'm Manja! Ready to tell you an amazing story!"
          : "The attraction content is currently unavailable.",
      narrationParagraphs: paragraphs,
      model3dPath: validModel3d,
      videoUrl: validVideoUrl,
    );
  }
}
