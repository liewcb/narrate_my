import 'dart:convert';
import '../entities/ar_placement.dart';

/// Data Transfer Object corresponding to `AttractionDTO` in the architecture diagram.
/// Maps the `Attraction` table in Supabase containing cultural descriptions,
/// 3D model assets (.glb), and official video narration URLs.
class AttractionDTO {
  final String attractionId;
  final String markerId;
  final String name;
  final String attractionContent;
  final String? model3dUrl;
  final String? videoUrl;
  final String? videoUrlBackup;
  final String? sourceUrl;
  final List<String> labels;

  const AttractionDTO({
    required this.attractionId,
    required this.markerId,
    required this.name,
    required this.attractionContent,
    this.model3dUrl,
    this.videoUrl,
    this.videoUrlBackup,
    this.sourceUrl,
    this.labels = const [],
  });

  /// Factory constructor to parse raw Supabase JSON payload
  factory AttractionDTO.fromJson(Map<String, dynamic> json) {
    return AttractionDTO(
      attractionId: json['attraction_id']?.toString() ?? '',
      markerId: json['marker_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Heritage Landmark',
      attractionContent: json['attraction_content']?.toString() ?? '',
      model3dUrl: json['model_3d_url'] as String?,
      videoUrl: json['video_url'] as String?,
      videoUrlBackup: json['video_url_backup'] as String?,
      sourceUrl: json['source_url'] as String?,
      labels: _parseLabels(json['labels']),
    );
  }

  /// Serializes AttractionDTO to Map
  Map<String, dynamic> toJson() {
    return {
      'attraction_id': attractionId,
      'marker_id': markerId,
      'name': name,
      'attraction_content': attractionContent,
      'model_3d_url': model3dUrl,
      'video_url': videoUrl,
      'video_url_backup': videoUrlBackup,
      'source_url': sourceUrl,
      'labels': labels,
    };
  }

  /// Converts this DTO into the domain entity [StoryScript]
  StoryScript toStoryScript({String? fallbackLandmarkName}) {
    final landmark = (name.trim().isNotEmpty)
        ? name.trim()
        : (fallbackLandmarkName ?? 'Heritage Landmark');

    List<String> paragraphs = [];
    if (attractionContent.trim().isNotEmpty) {
      paragraphs = _splitIntoBiteSizedPages(attractionContent);
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
      if (validModel3d.startsWith('http://') || validModel3d.startsWith('https://')) {
        // Remote network URL - keep as is
      } else if (validModel3d.startsWith('assets/')) {
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

    final validVideoUrlBackup = (videoUrlBackup != null && videoUrlBackup!.trim().isNotEmpty)
        ? videoUrlBackup!.trim()
        : null;

    return StoryScript(
      id: attractionId.isNotEmpty ? attractionId : 'story_$markerId',
      markerId: markerId,
      landmarkName: landmark,
      initialGreeting: hasContent
          ? "Hello I'm Manja! Ready to tell you an amazing story!"
          : "The attraction content is currently unavailable.",
      narrationParagraphs: paragraphs,
      model3dPath: validModel3d,
      videoUrl: validVideoUrl,
      videoUrlBackup: validVideoUrlBackup,
    );
  }

  static List<String> _splitIntoBiteSizedPages(String text) {
    final rawParagraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final List<String> pages = [];
    for (final p in rawParagraphs) {
      if (p.length > 280) {
        final sentences = p.split(RegExp(r'(?<=[.!?。！？])\s+'));
        String currentChunk = '';
        for (final s in sentences) {
          if ((currentChunk + s).length > 200 && currentChunk.isNotEmpty) {
            pages.add(currentChunk.trim());
            currentChunk = '$s ';
          } else {
            currentChunk += '$s ';
          }
        }
        if (currentChunk.trim().isNotEmpty) {
          pages.add(currentChunk.trim());
        }
      } else {
        pages.add(p);
      }
    }
    return pages.isNotEmpty ? pages : [text];
  }

  static List<String> _parseLabels(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
      return [raw];
    }
    return const [];
  }
}
