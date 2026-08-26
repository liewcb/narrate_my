import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../../core/widgets/app_bottom_navigation.dart';

/// Full-screen in-app YouTube Video Player Screen
/// Matches design mockups in Portrait, and adapts to Immersive Fullscreen in Landscape (0 overflow).
/// If videoUrl is not found in database or failed to retrieve, displays an Error Message.
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
  YoutubePlayerController? _controller;
  bool _hasError = false;
  bool _isLoading = false;

  static const _navItems = [
    BottomNavItem(
      icon: Icons.camera_alt_outlined,
      selectedIcon: Icons.camera_alt,
      label: 'AR',
    ),
    BottomNavItem(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: 'Itinerary',
    ),
    BottomNavItem(
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
      label: 'Nearby',
    ),
    BottomNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initYoutubePlayer();
  }

  void _initYoutubePlayer() {
    final rawUrl = widget.videoUrl;
    final videoId = (rawUrl != null && rawUrl.trim().isNotEmpty)
        ? YoutubePlayer.convertUrlToId(rawUrl)
        : null;

    if (videoId == null) {
      _hasError = true;
      return;
    }

    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
        showLiveFullscreenButton: true,
        forceHD: false,
        useHybridComposition: true,
        controlsVisibleAtStart: false,
        hideThumbnail: true,
        loop: false,
      ),
    )..addListener(_listener);
  }

  void _listener() {
    if (mounted) {
      if (_controller != null && _controller!.value.hasError && !_hasError) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentOrange = Color(0xFFD67D4A);

    if (_hasError || _controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1A1B),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top Bar: Landmark Badge + Close Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: accentOrange,
                        borderRadius: BorderRadius.circular(20),
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
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),

              // Error state centered
              Expanded(
                child: Center(
                  child: _buildUnavailableState(accentOrange),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNavBar(
          items: _navItems,
          currentIndex: 0,
          onTap: (index) {
            Navigator.of(context).pop();
          },
        ),
      );
    }

    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller!,
        showVideoProgressIndicator: true,
        bufferIndicator: const SizedBox.shrink(),
        progressIndicatorColor: accentOrange,
        progressColors: const ProgressBarColors(
          playedColor: accentOrange,
          handleColor: Colors.amberAccent,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
        onReady: () {
          _controller?.play();
        },
      ),
      builder: (context, player) {
        return OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            // 🎬 1. LANDSCAPE CINEMA FULLSCREEN MODE (Zero overflow, Max video area)
            if (isLandscape) {
              return Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: player),

                    // Floating Exit Button (Top Right)
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

                    // Floating Landmark Badge (Top Left)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: SafeArea(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: accentOrange.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                widget.landmarkName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 📱 2. PORTRAIT MOCKUP MODE (Standard clean card + standard bottom nav)
            return Scaffold(
              backgroundColor: const Color(0xFF0F1A1B),
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Top Bar: Landmark Badge + Close Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Orange Landmark Badge
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

                          // Close Button (Circular)
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 20),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Main Center Content
                    Expanded(
                      child: Center(
                        child: _buildPortraitPlayer(player, widget.landmarkName),
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: AppBottomNavBar(
                items: _navItems,
                currentIndex: 0,
                onTap: (index) {
                  Navigator.of(context).pop();
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Portrait Player Viewport with zero overflow guarantee
  Widget _buildPortraitPlayer(Widget player, String landmarkName) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: player,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            landmarkName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Video Unavailable State
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
                label: Text(_isLoading ? "Retrying..." : "Retry"),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fallback overlay wrapper for backward compatibility
class VideoPlayerOverlay extends StatelessWidget {
  const VideoPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
