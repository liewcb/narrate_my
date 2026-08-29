import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Business logic service matching `VideoPlaybackService` in architecture diagram.
/// Validates video URLs, extracts YouTube video IDs, and handles playback business rules.
class VideoPlaybackService {
  const VideoPlaybackService();

  /// Extracts a valid YouTube Video ID from any standard YouTube URL
  String? extractVideoId(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    return YoutubePlayer.convertUrlToId(rawUrl);
  }

  /// Checks if the provided video URL is valid and playable
  bool isValidVideoUrl(String? rawUrl) {
    return extractVideoId(rawUrl) != null;
  }
}
