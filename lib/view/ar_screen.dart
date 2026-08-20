import 'package:flutter/material.dart';
import 'ar/ar_exploration/ar_exploration_view.dart';

/// Entry point wired into the bottom nav (see app_routes.dart).
/// Delegates straight to the real UC100 AR Exploration flow.
class ARScreen extends StatelessWidget {
  const ARScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ARExplorationView();
  }
}
