import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_vm.dart';
import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile/messages/profile_messages.dart';
import '../../model/repositories/adapters/profile/profile_adapter.dart';
import '../../viewmodel/profile_viewmodel/profile_vm.dart';
import './bookmarks_screen.dart';
import './guest_profile_screen.dart';
import './guidance_screen.dart';
import './language_screen.dart';
import './personal_info_screen.dart';
import './preferences_screen.dart';

/// The Profile tab's entry point in `AppRoutes`'s `IndexedStack`.
///
/// MERGED 6 Sep at Foo's request from the former `lib/view/profile_screen.dart`
/// (a thin delegator one level up) — that file's whole job was this
/// auth-gating: guests can browse AR/Itinerary/Nearby freely, but the
/// Profile tab shows [GuestProfileScreen] when logged out and the real
/// UC402 flow (below) when logged in. Keeping that logic here, next to the
/// screen it gates, means one less file and one less indirection; see
/// `lib/view/profile_screen.dart` for the now-retired stub.
class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  final _profileRepository = SupabaseProfileRepositoryAdapter();
  StreamSubscription<bool>? _subscription;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = _profileRepository.isLoggedIn;
    _subscription = _profileRepository.authStateChanges.listen((loggedIn) {
      if (mounted) setState(() => _isLoggedIn = loggedIn);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoggedIn ? const _LoggedInProfileHome() : const GuestProfileScreen();
  }
}

/// UC402 Basic Flow step 2–3: the Profile Screen itself — a summary +
/// entry points into the four manageable sections, plus logout. Shown only
/// when [ProfileHomeScreen] above has confirmed the tourist is logged in.
class _LoggedInProfileHome extends StatelessWidget {
  const _LoggedInProfileHome();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileVm(),
      child: const _ProfileHomeView(),
    );
  }
}

class _ProfileHomeView extends StatelessWidget {
  const _ProfileHomeView();

  Future<void> _logout(BuildContext context, ProfileVm vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.t('ui.logout')),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.t('ui.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.t('ui.logout'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await vm.logout();
    // ignore: use_build_context_synchronously
    _afterLogout(context);
  }

  void _afterLogout(BuildContext context) {
    // No explicit navigation needed: `ProfileHomeScreen` (the Profile
    // tab's entry point, above) listens to `authStateChanges` and swaps
    // itself to
    // `GuestProfileScreen` — which already offers Log In / Create Account
    // — the instant the session clears. The bottom nav (and its AR/
    // Itinerary/Nearby tabs) stays exactly where it was, so "skipping"
    // login is just tapping any other tab; nothing forces the tourist
    // through the auth screens.
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("You've been logged out.")));
    }
  }

  // --- Added at Foo's request — NOT in the written spec ---------------------

  Future<void> _pickAvatar(BuildContext context, ProfileVm vm) async {
    final ok = await vm.pickAndUploadAvatar();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile picture updated.')));
    } else if (vm.avatarErrorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(vm.avatarErrorMessage!)));
    }
  }

  // Delete Account moved to the Personal Info screen (6 Sep, Foo's
  // request) — it doesn't belong next to Logout. See
  // `personal_info_screen.dart`'s "Danger Zone" section.

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileVm>();
    context.watch<LocaleVm>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.t('ui.profile'))),
      body: SafeArea(
        child: vm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : vm.errorMessage != null
            ? _ErrorRetry(message: vm.errorMessage!, onRetry: vm.load)
            : RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                ProfileMessages.m1ScreenSubtitle,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _AvatarPicker(vm: vm, onTap: () => _pickAvatar(context, vm)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vm.profile?.fullName?.isNotEmpty == true
                              ? vm.profile!.fullName!
                              : 'Tourist',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        if (vm.profile?.username != null)
                          Text(
                            '@${vm.profile!.username}',
                            style: const TextStyle(color: AppColors.inkFaint, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SectionTile(
                icon: Icons.badge_outlined,
                label: AppLocalizations.t('ui.personalInfo'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                ),
              ),
              _SectionTile(
                icon: Icons.tune,
                label: AppLocalizations.t('ui.preferences'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PreferencesScreen()),
                ),
              ),
              _SectionTile(
                icon: Icons.language,
                label: AppLocalizations.t('ui.language'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LanguageScreen()),
                ),
              ),
              _SectionTile(
                icon: Icons.bookmark_border,
                label: AppLocalizations.t('ui.bookmarks'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookmarksScreen()),
                ),
              ),
              // Added: entry point into the Guidance hub — short,
              // swipeable walkthroughs per module (AR today; more
              // modules can register their own guide later) —
              // see `guidance/guidance_screen.dart`.
              _SectionTile(
                icon: Icons.menu_book_outlined,
                label: AppLocalizations.t('ui.guidance'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GuidanceScreen()),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _SectionTile(
                icon: Icons.logout,
                label: AppLocalizations.t('ui.logout'),
                color: AppColors.error,
                onTap: () => _logout(context, vm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _SectionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.ink;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: tint),
      title: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600)),
      trailing: color == null ? const Icon(Icons.chevron_right, color: AppColors.inkFaint) : null,
      onTap: onTap,
    );
  }
}

/// Added at Foo's request — NOT in the written spec. Tappable avatar with a
/// small edit badge; shows a spinner over itself while an upload is in
/// flight instead of blocking the whole screen (see `ProfileVm.
/// isUploadingAvatar`).
class _AvatarPicker extends StatelessWidget {
  final ProfileVm vm;
  final VoidCallback onTap;

  const _AvatarPicker({required this.vm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: vm.isUploadingAvatar ? null : onTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.accentSoft,
            backgroundImage:
            vm.profile?.avatarUrl != null ? NetworkImage(vm.profile!.avatarUrl!) : null,
            child: vm.profile?.avatarUrl == null
                ? const Icon(Icons.person, size: 32, color: AppColors.accentDark)
                : null,
          ),
          if (vm.isUploadingAvatar)
            const Positioned.fill(
              child: CircleAvatar(
                backgroundColor: Colors.black38,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}