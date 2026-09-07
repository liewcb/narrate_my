import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_assistant/global_ai_assistant.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/google_maps_directions_button.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';

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
      heightFactor: 0.72,
      child: Material(
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
                    tooltip: AppLocalizations.t('recommendation.closeDetailsTooltip'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
              Text(
                site.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  fontSize: site.experiences.length > 1 ? 21 : null,
                ),
              ),
              if (site.experiences.length > 1) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 16,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          AppLocalizations.t(
                            'recommendation.arSharedLocationNotice',
                          ).replaceFirst('{count}', '${site.experiences.length}'),
                          style: const TextStyle(
                            color: AppColors.accentDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const ARAvailableBadge(),
              if (site.address != null) ...[
                const SizedBox(height: 14),
                Text(
                  site.address!,
                  style: const TextStyle(color: AppColors.inkSoft),
                ),
              ],
              const SizedBox(height: 22),
              GoogleMapsDirectionsButton(
                destinationName: site.name,
                latitude: site.latitude,
                longitude: site.longitude,
                googlePlaceId: site.googlePlaceIds.isEmpty
                    ? null
                    : site.googlePlaceIds.first,
              ),
              const SizedBox(height: 16),
              ARAvailabilityPanel(
                site: site,
                userLocation: userLocation,
                onOpenAr: onOpenAr,
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
              : AppLocalizations.t('recommendation.arExperienceCountMany')
                    .replaceFirst('{count}', '${site.experiences.length}'),
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
