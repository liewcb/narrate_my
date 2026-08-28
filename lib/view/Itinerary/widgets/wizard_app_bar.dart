// lib/widgets/wizard_app_bar.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart'; // adjust import to your new theme file

/// App bar with a back button, step indicator, and optional actions.
class WizardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int step; // 1..4
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  const WizardAppBar({
    super.key,
    required this.step,
    this.onBackPressed,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: AppColors.bg.withOpacity(0.9),   // was creamBg
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.ink), // was brandCharcoal
            onPressed: onBackPressed ?? () => Navigator.maybePop(context),
            padding: EdgeInsets.zero,
          ),
          const Spacer(),
          Text(
            'Step $step of 4',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.inkFaint,      // was outline
            ),
          ),
          const Spacer(),
          if (actions != null && actions!.isNotEmpty)
            Row(children: actions!)
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// 4-step progress bar with active/inactive dots.
class WizardProgressBar extends StatelessWidget {
  final int activeSteps; // how many steps are completed (active)

  const WizardProgressBar({super.key, required this.activeSteps});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2,
            width: double.infinity,
            color: AppColors.moduleBorder.withOpacity(0.6), // was outlineLight
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              final active = i < activeSteps;
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.primary : AppColors.bg, // was brandGreen / creamBg
                  border: Border.all(
                    color: active ? AppColors.primary : AppColors.moduleBorder,
                    width: 2,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.bg, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}