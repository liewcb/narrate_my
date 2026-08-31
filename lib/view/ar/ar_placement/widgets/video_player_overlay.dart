import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../../model/business_logic/ar_placement_service/video_playback_service.dart';

/// Clean, high-performance in-app YouTube Video Player Screen.
/// Optimized with Adaptive Bitrate (forceHD: false), instant poster thumbnail preload,
/// and responsive Flutter controls for ultra-fast startup and smooth playback.
class VideoPlayerScreen extends StatefulWidget {
  final String? videoUrl;
  final String landmarkName;

  const VideoPlayerScreen({
    super.key,
    this.videoUrl,
    required this.landmarkName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final VideoPlaybackService _videoService = const VideoPlaybackService();
  YoutubePlayerController? _controller;
  String? _videoId;
  bool _hasError = false;
  bool _isLoading = false;
  bool _isPlayerReady = false;

  // Custom Controls State
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isDraggingSlider = false;
  double _dragSliderPositionMs = 0.0;

  @override
  void initState() {
    super.initState();
    _initYoutubePlayer();
  }

  void _initYoutubePlayer() {
    _videoId = _videoService.extractVideoId(widget.videoUrl);

    if (_videoId == null) {
      _hasError = true;
      return;
    }

    _controller = YoutubePlayerController(
      initialVideoId: _videoId!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
        showLiveFullscreenButton: false,
        forceHD: false, // ⚡ FAST START: Adaptive bitrate starts playing in < 0.5s
        useHybridComposition: true,
        controlsVisibleAtStart: false,
        hideThumbnail: true,
        hideControls: true, // Hides YouTube HTML iframe controls completely
        disableDragSeek: true,
        loop: false,
      ),
    )..addListener(_listener);
  }

  void _listener() {
    if (!mounted || _controller == null) return;

    final hasError = _controller!.value.hasError;
    final isReady = _controller!.value.isReady;

    if (isReady && !_isPlayerReady) {
      _isPlayerReady = true;
      _startHideTimer();
    }

    if (hasError && !_hasError) {
      setState(() {
        _hasError = true;
      });
    } else {
      setState(() {});
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_controller?.value.isPlaying == true) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_isDraggingSlider) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _showControls = true;
      });
      _hideTimer?.cancel();
    } else {
      _controller!.play();
      setState(() {
        _showControls = true;
      });
      _startHideTimer();
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final currentMs = _controller!.value.position.inMilliseconds;
    final targetMs = (currentMs + (seconds * 1000)).clamp(
      0,
      _controller!.metadata.duration.inMilliseconds,
    );
    _controller!.seekTo(Duration(milliseconds: targetMs));
    _startHideTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_listener);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);

    if (_hasError || _controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1A1B),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, accentOrange),
              Expanded(
                child: Center(
                  child: _buildUnavailableState(accentOrange),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller!,
        showVideoProgressIndicator: false,
        topActions: const [],
        bottomActions: const [],
        onReady: () {
          _isPlayerReady = true;
          _controller?.play();
          _startHideTimer();
          if (mounted) setState(() {});
        },
      ),
      builder: (context, player) {
        return OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            // 🎬 1. LANDSCAPE CINEMA FULLSCREEN MODE
            if (isLandscape) {
              return Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: player),
                    _buildThumbnailPlaceholder(accentOrange),
                    _buildCustomControlsOverlay(isLandscape: true, accentOrange: accentOrange),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SafeArea(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 22),
                            tooltip: 'Close Video',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 📱 2. PORTRAIT IMMERSIVE MODE
            return Scaffold(
              backgroundColor: const Color(0xFF0F1A1B),
              body: SafeArea(
                child: Column(
                  children: [
                    // Top Bar: Landmark Badge + Close Button
                    _buildTopBar(context, accentOrange),

                    // Main Video Player Card with Custom Controls & Poster Preload
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RepaintBoundary(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      player,
                                      _buildThumbnailPlaceholder(accentOrange),
                                      _buildCustomControlsOverlay(isLandscape: false, accentOrange: accentOrange),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF142121).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.smart_display_outlined, color: accentOrange, size: 20),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        widget.landmarkName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Instant Poster Thumbnail Preloader: Shows video poster immediately while iframe loads
  Widget _buildThumbnailPlaceholder(Color accentOrange) {
    final thumbUrl = _videoId != null ? 'https://img.youtube.com/vi/$_videoId/hqdefault.jpg' : null;

    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _isPlayerReady ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: _isPlayerReady,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbUrl != null)
                Image.network(
                  thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: Color(0xFF0F1A1B)),
                )
              else
                const ColoredBox(color: Color(0xFF0F1A1B)),
              Container(
                color: Colors.black.withValues(alpha: 0.4),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: accentOrange,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Loading video...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomControlsOverlay({
    required bool isLandscape,
    required Color accentOrange,
  }) {
    if (_controller == null) return const SizedBox.shrink();

    final isPlaying = _controller!.value.isPlaying;
    final isBuffering = _controller!.value.playerState == PlayerState.buffering;
    final position = _controller!.value.position;
    final duration = _controller!.metadata.duration;

    final totalMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final currentMs = _isDraggingSlider
        ? _dragSliderPositionMs.clamp(0.0, totalMs)
        : position.inMilliseconds.toDouble().clamp(0.0, totalMs);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // Center Play/Pause & Quick Skip Controls
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rewind 10s
                        IconButton(
                          iconSize: isLandscape ? 36 : 28,
                          color: Colors.white,
                          icon: const Icon(Icons.replay_10_rounded),
                          tooltip: 'Rewind 10s',
                          onPressed: () => _seekRelative(-10),
                        ),
                        const SizedBox(width: 16),

                        // Main Big Play/Pause Button
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: isLandscape ? 68 : 56,
                            height: isLandscape ? 68 : 56,
                            decoration: BoxDecoration(
                              color: accentOrange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accentOrange.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: isBuffering
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: isLandscape ? 38 : 32,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Forward 10s
                        IconButton(
                          iconSize: isLandscape ? 36 : 28,
                          color: Colors.white,
                          icon: const Icon(Icons.forward_10_rounded),
                          tooltip: 'Forward 10s',
                          onPressed: () => _seekRelative(10),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Progress Bar & Time
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Slider Scrubbing Bar
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: accentOrange,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: accentOrange,
                            overlayColor: accentOrange.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: currentMs,
                            min: 0.0,
                            max: totalMs,
                            onChangeStart: (val) {
                              _isDraggingSlider = true;
                              _hideTimer?.cancel();
                            },
                            onChanged: (val) {
                              setState(() {
                                _dragSliderPositionMs = val;
                              });
                            },
                            onChangeEnd: (val) {
                              _isDraggingSlider = false;
                              _controller?.seekTo(Duration(milliseconds: val.toInt()));
                              _startHideTimer();
                            },
                          ),
                        ),

                        // Time & Fullscreen Icon Row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(Duration(milliseconds: currentMs.toInt()))} / ${_formatDuration(duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  isLandscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                tooltip: isLandscape ? 'Exit Fullscreen' : 'Fullscreen',
                                onPressed: () {
                                  _controller?.toggleFullScreenMode();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Color accentOrange) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: accentOrange,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  widget.landmarkName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableState(Color accentOrange) {
    final hasUrl = widget.videoUrl != null && widget.videoUrl!.trim().isNotEmpty;
    const errorMessage = "The related video is currently unavailable. Please try again later.";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.videocam_off_outlined,
              color: Colors.redAccent,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Video Unavailable",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (hasUrl)
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentOrange,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  final retryVideoId = YoutubePlayer.convertUrlToId(widget.videoUrl!) ?? "";
                  if (retryVideoId.isNotEmpty) {
                    _controller?.load(retryVideoId);
                  } else {
                    setState(() {
                      _hasError = true;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 600), () {
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  });
                },
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text("Retry Playback"),
              ),
            ),
        ],
      ),
    );
  }
}
