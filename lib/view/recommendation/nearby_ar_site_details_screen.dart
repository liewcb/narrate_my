import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../model/entities/ar_site.dart';
import '../../model/entities/coordinates.dart';

Future<void> showNearbyArSiteDetails(
  BuildContext context, {
  required ARSite site,
  required Coordinates userLocation,
  VoidCallback? onOpenAr,
}) {
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
                  const Expanded(
                    child: Text(
                      'AR LOCATION',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
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
              Text(
                site.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
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
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_in_ar_rounded, color: Color(0xFF7048B7), size: 17),
          SizedBox(width: 6),
          Text(
            'AR available',
            style: TextStyle(
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
          '${site.experiences.length} AR ${site.experiences.length == 1 ? 'experience' : 'experiences'}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (site.experiences.isEmpty)
          const Text(
            'AR experience information has not been linked yet.',
            style: TextStyle(color: AppColors.inkFaint),
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
            label: Text(canOpenAr ? 'Open AR' : 'Visit location to unlock AR'),
          ),
        ),
      ],
    );
  }

  String _availabilityMessage(bool canOpenAr, double? nearestDistance) {
    if (canOpenAr) {
      return 'You are within an AR activation area. Open the AR camera to '
          'interact with this location.';
    }
    if (nearestDistance == null) {
      return 'Visit this location to use its AR experiences.';
    }
    return 'AR works on site. The nearest activation point is '
        '${_formatDistance(nearestDistance)} away.';
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
                      ? 'Available now'
                      : '${_formatDistance(distance)} away',
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
