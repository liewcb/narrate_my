import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../widgets/primary_button.dart';

/// Shown on the Profile tab when no one is logged in. Guests can still
/// freely browse AR/Itinerary/Nearby (this gating only applies to the
/// Profile tab itself — see `lib/view/profile_screen.dart`).
class GuestProfileScreen extends StatelessWidget {
  const GuestProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined, size: 88, color: AppColors.inkFaint),
              const SizedBox(height: 20),
              const Text(
                "You're browsing as a guest",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Log in or create an account to save your preferences, bookmarks, '
                'and preferred language.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Log In',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Create Account',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
