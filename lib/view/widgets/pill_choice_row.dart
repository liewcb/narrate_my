import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A row of mutually-exclusive "pill" options — used for Travel Preferences
/// (Relaxed / Balanced / Adventure), the one single-select category in
/// Preferences (everything else there is multi-select chips or toggles).
class PillChoiceRow extends StatelessWidget {
  final List<String> options;
  final Map<String, String>? descriptions;
  final String? selected;
  final ValueChanged<String> onSelected;

  const PillChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.descriptions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((option) {
        final isSelected = option == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: option == options.last ? 0 : 8),
            child: GestureDetector(
              onTap: () => onSelected(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? AppColors.accent : AppColors.moduleBorder),
                ),
                child: Column(
                  children: [
                    Text(
                      option,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: isSelected ? AppColors.bg : AppColors.ink,
                      ),
                    ),
                    if (descriptions?[option] != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        descriptions![option]!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.25,
                          color: isSelected ? AppColors.bg.withValues(alpha: 0.9) : AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
