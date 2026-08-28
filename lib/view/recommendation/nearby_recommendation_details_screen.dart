import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../model/entities/recommendation.dart';

Future<void> showNearbyRecommendationDetails(
  BuildContext context,
  Recommendation recommendation,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.78,
      child: NearbyRecommendationDetailsScreen(recommendation: recommendation),
    ),
  );
}

class NearbyRecommendationDetailsScreen extends StatelessWidget {
  final Recommendation recommendation;

  const NearbyRecommendationDetailsScreen({
    super.key,
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ATTRACTION DETAILS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recommendation.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CategoryChip(label: recommendation.category),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
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
          ],
        ),
      ),
    );
  }
}

class _AttractionImage extends StatelessWidget {
  final Recommendation recommendation;

  const _AttractionImage({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFF8AA98C),
      alignment: Alignment.center,
      child: const Icon(Icons.landscape_rounded, color: Colors.white, size: 52),
    );

    return AspectRatio(
      aspectRatio: 16 / 8.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: recommendation.imageUrl == null
            ? placeholder
            : Image.network(
                recommendation.imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;

  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5F1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFBFE4DA)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
