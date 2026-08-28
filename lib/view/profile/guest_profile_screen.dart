import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'widgets/primary_button.dart';

/// Shown on the Profile tab when no one is logged in. Guests can still
/// freely browse AR/Itinerary/Nearby (this gating only applies to the
/// Profile tab itself — see `lib/view/profile_screen.dart`).
class GuestProfileScreen extends StatelessWidget {
  const GuestProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.profile'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined, size: 88, color: AppColors.inkFaint),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.t('ui.guestBrowsing'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.t('ui.guestSubtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: AppLocalizations.t('ui.login'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: AppLocalizations.t('ui.createAccount'),
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
