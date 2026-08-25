import 'package:flutter/material.dart';

import '../../model/business_logic/profile_business_logic/preference_options.dart';
import '../../core/theme/app_theme.dart';

/// A single selectable photo tile for an attraction/activity category, used
/// in both the Initial Preferences (onboarding) screen and the Preferences
/// screen's "Attraction & Activity Interests" section.
///
/// Uses the real category photo from [kAttractionCategoryImages] when one
/// exists (bundled under `assets/images/attractions/`, declared in
/// `pubspec.yaml`); falls back to a tinted-gradient background with a
/// [kAttractionCategoryIcons] icon for any category without a photo yet.
class AttractionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AttractionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageAsset = kAttractionCategoryImages[label];
    final icon = kAttractionCategoryIcons[label] ?? Icons.place;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageAsset != null)
                    Image.asset(imageAsset, fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: selected
                              ? [AppColors.accent, AppColors.accentDark]
                              : [AppColors.surface2, AppColors.accentSoft],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 34,
                          color: selected ? AppColors.bg : AppColors.accentDark,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            (selected ? AppColors.accentDark : AppColors.ink)
                                .withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A grid of [AttractionTile]s — [crossAxisCount] is 2 on the onboarding
/// screen's 6-tile picker and 3 on the fuller Preferences screen list.
class AttractionTileGrid extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final int crossAxisCount;

  const AttractionTileGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, i) {
        final option = options[i];
        return AttractionTile(
          label: option,
          selected: selected.contains(option),
          onTap: () => onToggle(option),
        );
      },
    );
  }
}
