import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../model/business_logic/profile_business_logic/messages/profile_messages.dart';
import '../../viewmodel/profile_viewmodel/profile_vm.dart';
import 'bookmarks_screen.dart';
import 'language_screen.dart';
import 'personal_info_screen.dart';
import 'preferences_screen.dart';

/// UC402 Basic Flow step 2–3: the Profile Screen itself — a summary +
/// entry points into the four manageable sections, plus logout. Shown only
/// when logged in; `lib/view/profile_screen.dart` is what decides that.
class ProfileHomeScreen extends StatelessWidget {
  const ProfileHomeScreen({super.key});

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
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log Out', style: TextStyle(color: AppColors.error)),
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
    // No explicit navigation needed: `ProfileScreen` (the Profile tab's
    // entry point) listens to `authStateChanges` and swaps itself to
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

  Future<void> _deleteAccount(BuildContext context, ProfileVm vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(ProfileMessages.m22ConfirmDeleteAccount),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteAccount();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ProfileMessages.m23AccountDeleted)));
      // Same auth-gate mechanism as logout: `ProfileScreen` listens for the
      // (now-invalidated) session to clear and swaps itself to
      // `GuestProfileScreen` on its own.
    } else if (vm.deleteAccountErrorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(vm.deleteAccountErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileVm>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
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
                          label: 'Personal Info',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                          ),
                        ),
                        _SectionTile(
                          icon: Icons.tune,
                          label: 'Preferences',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PreferencesScreen()),
                          ),
                        ),
                        _SectionTile(
                          icon: Icons.language,
                          label: 'Language',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LanguageScreen()),
                          ),
                        ),
                        _SectionTile(
                          icon: Icons.bookmark_border,
                          label: 'Bookmarks',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const BookmarksScreen()),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        _SectionTile(
                          icon: Icons.logout,
                          label: 'Log Out',
                          color: AppColors.error,
                          onTap: () => _logout(context, vm),
                        ),
                        _SectionTile(
                          icon: Icons.delete_outline,
                          label: 'Delete Account',
                          color: AppColors.error,
                          onTap: () => _deleteAccount(context, vm),
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
