import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart'; // adjust import to your new theme file

/// App bar with a back button, step indicator, and optional actions.
class WizardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int step;
  final int totalSteps;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  const WizardAppBar({
    super.key,
    required this.step,
    this.totalSteps = 5, // Default to 5
    this.onBackPressed,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg.withOpacity(0.9),
      // SafeArea automatically pushes the content down below the phone's notch/status bar
      child: SafeArea(
        bottom: false,
        child: Padding(
          // Adjust vertical padding here for visual breathing room (16px looks very clean)
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // 1. LEFT SIDE: Back Button
              SizedBox(
                width: 32, // Fixed width to balance the right side
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                  onPressed: onBackPressed ?? () => Navigator.maybePop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(), // Removes default wide tap margins
                  alignment: Alignment.centerLeft,
                ),
              ),

              const Spacer(),

              // 2. CENTER: Step Indicator
              Text(
                'Step $step of $totalSteps',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.inkFaint,
                ),
              ),

              const Spacer(),

              // 3. RIGHT SIDE: Actions or Empty Space (must balance the left side)
              if (actions != null && actions!.isNotEmpty)
                Row(children: actions!)
              else
                const SizedBox(width: 32), // Exact same width as the back button so text is dead-center
            ],
          ),
        ),
      ),
    );
  }

  @override
  // Standard toolbar height + extra breathing room
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 20);
}

/// Progress bar with active/inactive dots.
class WizardProgressBar extends StatelessWidget {
  final int activeSteps;
  final int totalSteps;

  const WizardProgressBar({
    super.key,
    required this.activeSteps,
    this.totalSteps = 5,
  });

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
            color: AppColors.moduleBorder.withOpacity(0.6),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            // Automatically generates the exact number of dots you need
            children: List.generate(totalSteps, (i) {
              final active = i < activeSteps;
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.primary : AppColors.bg,
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