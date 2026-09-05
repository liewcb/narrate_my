import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_assistant/global_ai_assistant.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/place_image.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';
import '../../model/entities/recommendation.dart';
import '../../viewmodel/bookmark_vm.dart';
import '../profile/auth/login_screen.dart';
import 'nearby_ar_site_details_screen.dart';

Future<void> showNearbyRecommendationDetails(
  BuildContext context,
  Recommendation recommendation, {
  ARSite? arSite,
  Coordinates? userLocation,
  VoidCallback? onOpenAr,
}) {
  context.read<GlobalAiAssistantController>().selectPlace(
    _placeFromRecommendation(recommendation),
    source: 'recommendation',
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.78,
      child: ChangeNotifierProvider(
        create: (_) => BookmarkVm()..load(recommendation.placeId),
        child: NearbyRecommendationDetailsScreen(
          recommendation: recommendation,
          arSite: arSite,
          userLocation: userLocation,
          onOpenAr: onOpenAr,
        ),
      ),
    ),
  );
}

Place _placeFromRecommendation(Recommendation recommendation) => Place(
  placeId: recommendation.placeId,
  placeName: recommendation.name,
  placeAddress: recommendation.address,
  placeLatitude: recommendation.latitude,
  placeLongitude: recommendation.longitude,
  placeRating: recommendation.rating ?? 0,
  placeTypes: [recommendation.category],
  category: recommendation.category,
);

class NearbyRecommendationDetailsScreen extends StatelessWidget {
  final Recommendation recommendation;
  final ARSite? arSite;
  final Coordinates? userLocation;
  final VoidCallback? onOpenAr;

  const NearbyRecommendationDetailsScreen({
    super.key,
    required this.recommendation,
    this.arSite,
    this.userLocation,
    this.onOpenAr,
  });

  Place get _bookmarkPlace => _placeFromRecommendation(recommendation);

  Future<void> _handleBookmark(
    BuildContext context,
    BookmarkVm viewModel,
  ) async {
    final result = await viewModel.toggleBookmark(
      _bookmarkPlace,
      itemType: 'attraction',
    );
    if (!context.mounted) return;

    switch (result) {
      case BookmarkResult.loginRequired:
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
        if (shouldLogin != true) {
          viewModel.clearPendingBookmark();
          return;
        }
        if (context.mounted) {
          final loggedIn = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(returnOnSuccess: true),
            ),
          );
          if (loggedIn == true && context.mounted) {
            await viewModel.retryPendingBookmark();
          }
        }
        return;
      case BookmarkResult.added ||
          BookmarkResult.removed ||
          BookmarkResult.alreadyBookmarked ||
          BookmarkResult.failed:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarkViewModel = context.watch<BookmarkVm>();

    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.moduleBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ATTRACTION DETAILS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              recommendation.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CategoryChip(label: recommendation.category),
                if (arSite != null) const ARAvailableBadge(),
              ],
            ),
            const SizedBox(height: 20),
            _AttractionImage(recommendation: recommendation),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    recommendation.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ),
                if (recommendation.rating != null) ...[
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.star_rounded,
                    color: AppColors.gold,
                    size: 18,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    recommendation.rating!.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    icon: Icons.near_me_outlined,
                    label: 'DISTANCE',
                    value: '${recommendation.distanceKm.toStringAsFixed(1)} km',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    icon: Icons.schedule_rounded,
                    label: 'EST. TRAVEL',
                    value:
                        '~${recommendation.estimatedTravelMinutes} min by car',
                    accent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              recommendation.reason,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSoft,
                height: 1.55,
              ),
            ),
            if (arSite != null && userLocation != null) ...[
              const SizedBox(height: 22),
              ARAvailabilityPanel(
                site: arSite!,
                userLocation: userLocation!,
                onOpenAr: onOpenAr == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onOpenAr!();
                      },
              ),
            ],
            const SizedBox(height: 24),
            _BookmarkButton(
              isBookmarked: bookmarkViewModel.isBookmarked,
              isLoading:
                  bookmarkViewModel.isChecking || bookmarkViewModel.isSaving,
              onPressed: () => _handleBookmark(context, bookmarkViewModel),
            ),
            if (bookmarkViewModel.statusMessage != null) ...[
              const SizedBox(height: 10),
              _BookmarkStatusMessage(
                message: bookmarkViewModel.statusMessage!,
                isError: bookmarkViewModel.errorMessage != null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookmarkStatusMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const _BookmarkStatusMessage({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.error : AppColors.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  final bool isBookmarked;
  final bool isLoading;
  final VoidCallback onPressed;

  const _BookmarkButton({
    required this.isBookmarked,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isBookmarked ? AppColors.primary : AppColors.accent;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(
                isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
        label: Text(isBookmarked ? 'Bookmarked' : 'Bookmark'),
      ),
    );
  }
}

class _AttractionImage extends StatelessWidget {
  final Recommendation recommendation;

  const _AttractionImage({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 8.5,
      child: PlaceImage(
        imageUrl: recommendation.imageUrl,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;

  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5F1),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0xFFBFE4DA)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: accent ? AppColors.accent : AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
