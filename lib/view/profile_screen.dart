import 'dart:async';

import 'package:flutter/material.dart';

import '../model/repositories/adapters/profile_adapter.dart';
import 'profile/guest_profile_screen.dart';
import 'profile/profile_home_screen.dart';

/// The Profile tab's entry point in `AppRoutes`'s `IndexedStack`. Kept as a
/// thin delegator (matching how `ar_screen.dart` delegates to
/// `ar_exploration_view.dart`) — the actual gating logic ("guests can
/// browse AR/Itinerary/Nearby; the Profile tab shows GuestProfileScreen
/// when logged out, the real profile flow when logged in") lives entirely
/// here, so `AppRoutes` itself needed no changes.
///
/// RETIRED: this file previously held the whole generic placeholder
/// profile form (name/age/religion/ethnicity/gender) plus a real bug —
/// `import '../ViewModel/Profile_VM.dart'` / `'../Model/...'` against the
/// repo's actual lowercase `viewmodel/`/`model/` folders. Both are gone;
/// the replacement lives under `lib/view/profile/` and `lib/viewmodel/profile/`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    return _isLoggedIn ? const ProfileHomeScreen() : const GuestProfileScreen();
  }
}
