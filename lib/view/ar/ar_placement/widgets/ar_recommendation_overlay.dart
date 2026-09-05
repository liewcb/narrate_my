import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/place_image.dart';
import '../../../../model/entities/ar_recommendation.dart';
import '../../../../viewmodel/ar/ar_recommendation_vm.dart';
import '../../../../viewmodel/bookmark_vm.dart';
import '../../../profile/auth/login_screen.dart';

/// Camera-overlay presentation for contextual AR recommendations.
///
/// The AR surface stays mounted behind this widget so closing the panel does
/// not restart the placement session or remove the placed avatar.
class ARRecommendationOverlay extends StatelessWidget {
  const ARRecommendationOverlay({super.key});

  static const _orange = Color(0xFFF28A45);
  static const _dark = Color(0xEE102222);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ARRecommendationVm>();
    if (!vm.isVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Material(
        color: _dark,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _orange,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Recommended for you',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: 'Close recommendations',
                      onPressed: vm.close,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 6, 22, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 3,
                      height: 18,
                      child: ColoredBox(color: _orange),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'CONTINUE YOUR EXPERIENCE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _RecommendationBody(viewModel: vm)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationBody extends StatelessWidget {
  final ARRecommendationVm viewModel;

  const _RecommendationBody({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading && viewModel.recommendations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFF28A45)),
            SizedBox(height: 14),
            Text(
              'Finding the best next experiences…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (viewModel.errorMessage != null && viewModel.recommendations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                color: Colors.white70,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                viewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: viewModel.retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: viewModel.retry,
      color: const Color(0xFFF28A45),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
        itemCount: viewModel.recommendations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final recommendation = viewModel.recommendations[index];
          return _ARRecommendationCard(
            key: ValueKey(recommendation.attractionId),
            recommendation: recommendation,
            isExpanded:
                viewModel.expandedAttractionId == recommendation.attractionId,
            onToggle: () =>
                viewModel.toggleExpanded(recommendation.attractionId),
          );
        },
      ),
    );
  }
}

class _ARRecommendationCard extends StatefulWidget {
  final ARRecommendation recommendation;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ARRecommendationCard({
    super.key,
    required this.recommendation,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  State<_ARRecommendationCard> createState() => _ARRecommendationCardState();
}

class _ARRecommendationCardState extends State<_ARRecommendationCard> {
  late final BookmarkVm _bookmarkVm;

  @override
  void initState() {
    super.initState();
    _bookmarkVm = BookmarkVm()..load(widget.recommendation.placeId);
  }

  @override
  void didUpdateWidget(covariant _ARRecommendationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendation.placeId != widget.recommendation.placeId) {
      _bookmarkVm.load(widget.recommendation.placeId);
    }
  }

  @override
  void dispose() {
    _bookmarkVm.dispose();
    super.dispose();
  }

  Future<void> _toggleBookmark() async {
    final result = await _bookmarkVm.toggleBookmark(
      widget.recommendation.toBookmarkPlace(),
      itemType: 'attraction',
    );
    if (!mounted || result != BookmarkResult.loginRequired) return;

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log in to bookmark'),
        content: const Text(
          'You need to log in before you can save attractions to your '
          'bookmarks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (shouldLogin != true) {
      _bookmarkVm.clearPendingBookmark();
      return;
    }

    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(returnOnSuccess: true),
      ),
    );
    if (loggedIn == true && mounted) {
      await _bookmarkVm.retryPendingBookmark();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = widget.recommendation;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFB),
        borderRadius: BorderRadius.circular(20),
        border: widget.isExpanded
            ? Border.all(color: const Color(0xFFF28A45), width: 1.4)
            : null,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1D4B8),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFD56E2E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recommendation.name,
                          maxLines: widget.isExpanded ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF27211D),
                            fontSize: 16,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${recommendation.category}  •  '
                          '${recommendation.travelSummary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF527A79),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF81908E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: widget.isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _ExpandedRecommendation(
              recommendation: recommendation,
              bookmarkVm: _bookmarkVm,
              onBookmark: _toggleBookmark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedRecommendation extends StatelessWidget {
  final ARRecommendation recommendation;
  final BookmarkVm bookmarkVm;
  final VoidCallback onBookmark;

  const _ExpandedRecommendation({
    required this.recommendation,
    required this.bookmarkVm,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceImage(
            imageUrl: recommendation.imageUrl,
            width: double.infinity,
            height: 150,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F2F0),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              recommendation.relationship,
              style: const TextStyle(
                color: Color(0xFF2D6A5E),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.near_me_outlined,
                  label: 'DISTANCE',
                  value: '${recommendation.distanceKm.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Metric(
                  icon: recommendation.isWalkable
                      ? Icons.directions_walk_rounded
                      : Icons.directions_car_outlined,
                  label: 'EST. TRAVEL',
                  value: recommendation.travelSummary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendation.reason,
            style: const TextStyle(
              color: Color(0xFF3D3935),
              height: 1.45,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            recommendation.summary,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6C6863),
              height: 1.42,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: bookmarkVm,
            builder: (context, _) {
              return Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: bookmarkVm.isSaving || bookmarkVm.isChecking
                          ? null
                          : onBookmark,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE47D3D),
                        side: const BorderSide(color: Color(0xFFF28A45)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: bookmarkVm.isSaving || bookmarkVm.isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              bookmarkVm.isBookmarked
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                            ),
                      label: Text(
                        bookmarkVm.isBookmarked ? 'Bookmarked' : 'Bookmark',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (bookmarkVm.statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      bookmarkVm.statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bookmarkVm.errorMessage == null
                            ? const Color(0xFF2D6A5E)
                            : const Color(0xFFC0392B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7E1DB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4A8B85), size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF9A928B),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2D2925),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
