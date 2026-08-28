import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A single accessibility-preference row: an optional leading emoji, a
/// title, a one-line description, and a trailing toggle switch — the
/// design canvas's treatment for the Accessibility Preferences section
/// (distinct from the plain [FilterChip] sections used for Food/Dietary,
/// which have no per-option description or emoji to show).
class TogglePreferenceTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? emoji;
  final bool value;
  final ValueChanged<bool> onChanged;

  const TogglePreferenceTile({
    super.key,
    required this.title,
    this.subtitle,
    this.emoji,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? AppColors.accentSoft.withValues(alpha: 0.5) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? AppColors.accent : AppColors.moduleBorder),
      ),
      child: Row(
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
