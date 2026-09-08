import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/colors.dart';
import '../../../model/business_logic/shared_services/trip_draft_notifier.dart';
import '../../Itinerary/my_itineraries_screen.dart';

class WizardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int step;
  final int totalSteps;
  final bool showHomeButton;

  const WizardAppBar({
    super.key,
    required this.step,
    this.totalSteps = 5,
    this.showHomeButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: Row(
        children: [
          if (step > 1)
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.brandCharcoal),
              onPressed: () => Navigator.pop(context),
            ),
          if (step == 1)
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.brandCharcoal),
              onPressed: () => _showExitConfirmation(context),
            ),
        ],
      ),
      title: Text(
        'Step $step of $totalSteps',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.outline,
          letterSpacing: 1.2,
        ),
      ),
      centerTitle: true,
      actions: [
        if (showHomeButton)
          IconButton(
            icon: const Icon(Icons.home_outlined, color: AppColors.brandCharcoal),
            onPressed: () => _navigateToHome(context),
            tooltip: 'My Itineraries',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit trip builder?'),
        content: const Text(
          'Your trip progress will be lost if you leave now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Planning'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyItinerariesScreen(),
                ),
              );
            },
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _navigateToHome(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Go to My Itineraries?'),
        content: const Text(
          'Your current trip progress will be saved if you have reached Step 2 or later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay Here'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Save current draft before navigating
              final draft = context.read<TripDraftNotifier>().draft;
              context.read<TripDraftNotifier>().updateDraft(draft);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyItinerariesScreen(),
                ),
              );
            },
            child: const Text('Go Home'),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

// ─── WizardProgressBar ──────────────────────────────────────────

/// A progress indicator showing which step of the wizard the user is on.
class WizardProgressBar extends StatelessWidget {
  final int activeSteps; // Number of completed steps (1-5)

  const WizardProgressBar({
    super.key,
    required this.activeSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final isActive = index < activeSteps;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: isActive ? AppColors.brandGreen : AppColors.outlineLight,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}