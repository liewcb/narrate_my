import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_assistant/global_ai_assistant.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/google_maps_directions_button.dart';
import '../../core/widgets/place_image.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';
import '../../model/repositories/adapters/ar_exploration/ar_site_place_repository_adapter.dart';
import '../../viewmodel/bookmark_vm.dart';
import '../../viewmodel/recommendation/nearby_ar_site_details_vm.dart';
import '../profile/auth/login_screen.dart';

Future<void> showNearbyArSiteDetails(
  BuildContext context, {
  required ARSite site,
  required Coordinates userLocation,
  VoidCallback? onOpenAr,
}) {
  context.read<GlobalAiAssistantController>().selectArSite(
    site,
    latitude: userLocation.latitude,
    longitude: userLocation.longitude,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BookmarkVm()),
          ChangeNotifierProvider(
            create: (_) =>
                NearbyArSiteDetailsVm(SupabaseARSitePlaceRepositoryAdapter()),
          ),
        ],
        child: _NearbyArSiteDetailsScreen(
          site: site,
          userLocation: userLocation,
          onOpenAr: onOpenAr,
        ),
      ),
    ),
  );
}

class _NearbyArSiteDetailsScreen extends StatefulWidget {
  final ARSite site;
  final Coordinates userLocation;
  final VoidCallback? onOpenAr;

  const _NearbyArSiteDetailsScreen({
    required this.site,
    required this.userLocation,
    this.onOpenAr,
  });

  @override
  State<_NearbyArSiteDetailsScreen> createState() =>
      _NearbyArSiteDetailsScreenState();
}

class _NearbyArSiteDetailsScreenState
    extends State<_NearbyArSiteDetailsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadPlace());
  }

  Future<void> _loadPlace() async {
    final detailsViewModel = context.read<NearbyArSiteDetailsVm>();
    await detailsViewModel.load(widget.site);
    if (!mounted) return;
    final place = detailsViewModel.place;
    if (place != null) {
      await context.read<BookmarkVm>().load(place.placeId);
    }
  }

  Future<void> _handleBookmark(BookmarkVm viewModel) async {
    final place = context.read<NearbyArSiteDetailsVm>().place;
    if (place == null) return;
    final result = await viewModel.toggleBookmark(
      place,
      itemType: 'attraction',
    );
    if (!mounted || result != BookmarkResult.loginRequired) return;

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.t('recommendation.loginToBookmarkTitle')),
        content: Text(AppLocalizations.t('recommendation.loginToBookmarkBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.t('recommendation.no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.t('recommendation.logIn')),
          ),
        ],
      ),
    );
    if (shouldLogin != true) {
      viewModel.clearPendingBookmark();
      return;
    }
    if (!mounted) return;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(returnOnSuccess: true),
      ),
    );
    if (loggedIn == true && mounted) {
      await viewModel.retryPendingBookmark();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    final bookmarkViewModel = context.watch<BookmarkVm>();
    final detailsViewModel = context.watch<NearbyArSiteDetailsVm>();
    final place = detailsViewModel.place;
    final address = widget.site.address ?? place?.placeAddress;
    final googlePlaceId =
        place?.placeId ??
        (widget.site.googlePlaceIds.isEmpty
            ? null
            : widget.site.googlePlaceIds.first);

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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.t('recommendation.arLocationLabel'),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.t(
                    'recommendation.closeDetailsTooltip',
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
            Text(
              widget.site.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                height: 1.12,
                fontSize: widget.site.experiences.length > 1 ? 21 : null,
              ),
            ),
            if (widget.site.experiences.length > 1) ...[
              const SizedBox(height: 10),
              _SharedLocationNotice(count: widget.site.experiences.length),
            ],
            const SizedBox(height: 10),
            const ARAvailableBadge(),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 16 / 8.5,
              child: detailsViewModel.isLoading
                  ? Container(
                      decoration: BoxDecoration(
                        color: AppColors.moduleBorder.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    )
                  : PlaceImage(
                      imageUrl: place?.placeImageUrl,
                      borderRadius: BorderRadius.circular(16),
                    ),
            ),
            if (address?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text(address!, style: const TextStyle(color: AppColors.inkSoft)),
            ],
            const SizedBox(height: 22),
            GoogleMapsDirectionsButton(
              destinationName: widget.site.name,
              latitude: widget.site.latitude,
              longitude: widget.site.longitude,
              googlePlaceId: googlePlaceId,
            ),
            const SizedBox(height: 16),
            ARAvailabilityPanel(
              site: widget.site,
              userLocation: widget.userLocation,
              onOpenAr: widget.onOpenAr,
            ),
            const SizedBox(height: 24),
            _ArBookmarkButton(
              isBookmarked: bookmarkViewModel.isBookmarked,
              isLoading:
                  detailsViewModel.isLoading ||
                  bookmarkViewModel.isChecking ||
                  bookmarkViewModel.isSaving,
              isAvailable: place != null,
              onPressed: () => _handleBookmark(bookmarkViewModel),
            ),
            if (bookmarkViewModel.statusMessage != null) ...[
              const SizedBox(height: 10),
              _ArBookmarkStatusMessage(
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

class _SharedLocationNotice extends StatelessWidget {
  final int count;

  const _SharedLocationNotice({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2E8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              AppLocalizations.t(
                'recommendation.arSharedLocationNotice',
              ).replaceFirst('{count}', '$count'),
              style: const TextStyle(
                color: AppColors.accentDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArBookmarkButton extends StatelessWidget {
  final bool isBookmarked;
  final bool isLoading;
  final bool isAvailable;
  final VoidCallback onPressed;

  const _ArBookmarkButton({
    required this.isBookmarked,
    required this.isLoading,
    required this.isAvailable,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isBookmarked ? AppColors.primary : AppColors.accent;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading || !isAvailable ? null : onPressed,
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
        label: Text(
          isBookmarked
              ? AppLocalizations.t('recommendation.bookmarked')
              : AppLocalizations.t('recommendation.bookmark'),
        ),
      ),
    );
  }
}

class _ArBookmarkStatusMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const _ArBookmarkStatusMessage({
    required this.message,
    required this.isError,
  });

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

class ARAvailableBadge extends StatelessWidget {
  const ARAvailableBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EAFE),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFD5C2FA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.view_in_ar_rounded,
            color: Color(0xFF7048B7),
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.t('recommendation.arAvailable'),
            style: const TextStyle(
              color: Color(0xFF7048B7),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ARAvailabilityPanel extends StatelessWidget {
  final ARSite site;
  final Coordinates userLocation;
  final VoidCallback? onOpenAr;

  const ARAvailabilityPanel({
    super.key,
    required this.site,
    required this.userLocation,
    this.onOpenAr,
  });

  @override
  Widget build(BuildContext context) {
    final canOpenAr = site.canOpenArAt(
      userLocation.latitude,
      userLocation.longitude,
    );
    final nearest = site.nearestExperienceTo(
      userLocation.latitude,
      userLocation.longitude,
    );
    final nearestDistance = nearest?.distanceMetersFrom(
      userLocation.latitude,
      userLocation.longitude,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: canOpenAr
                ? const Color(0xFFE8F5F1)
                : const Color(0xFFF7F2FC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                canOpenAr
                    ? Icons.check_circle_rounded
                    : Icons.directions_walk_rounded,
                color: canOpenAr ? AppColors.primary : const Color(0xFF7048B7),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _availabilityMessage(canOpenAr, nearestDistance),
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          site.experiences.length == 1
              ? AppLocalizations.t('recommendation.arExperienceCountOne')
              : AppLocalizations.t(
                  'recommendation.arExperienceCountMany',
                ).replaceFirst('{count}', '${site.experiences.length}'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (site.experiences.isEmpty)
          Text(
            AppLocalizations.t('recommendation.noArInfoLinked'),
            style: const TextStyle(color: AppColors.inkFaint),
          )
        else
          ...site.experiences.map(
            (experience) => _ExperienceRow(
              experience: experience,
              userLocation: userLocation,
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canOpenAr && onOpenAr != null ? onOpenAr : null,
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(
              canOpenAr
                  ? AppLocalizations.t('recommendation.openAr')
                  : AppLocalizations.t('recommendation.visitToUnlockAr'),
            ),
          ),
        ),
      ],
    );
  }

  String _availabilityMessage(bool canOpenAr, double? nearestDistance) {
    if (canOpenAr) {
      return AppLocalizations.t('recommendation.availabilityWithinArea');
    }
    if (nearestDistance == null) {
      return AppLocalizations.t('recommendation.availabilityVisitSite');
    }
    return AppLocalizations.t(
      'recommendation.availabilityNearestPoint',
    ).replaceFirst('{distance}', _formatDistance(nearestDistance));
  }
}

class _ExperienceRow extends StatelessWidget {
  final ARSiteExperience experience;
  final Coordinates userLocation;

  const _ExperienceRow({required this.experience, required this.userLocation});

  @override
  Widget build(BuildContext context) {
    final distance = experience.distanceMetersFrom(
      userLocation.latitude,
      userLocation.longitude,
    );
    final active = distance <= experience.activationRadiusMeters;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.moduleBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.view_in_ar_rounded,
            color: active ? AppColors.primary : const Color(0xFF7048B7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  experience.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? AppLocalizations.t('recommendation.availableNow')
                      : AppLocalizations.t(
                          'recommendation.awayDistance',
                        ).replaceFirst('{distance}', _formatDistance(distance)),
                  style: TextStyle(
                    color: active ? AppColors.primary : AppColors.inkFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
