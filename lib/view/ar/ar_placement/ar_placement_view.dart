import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ar_flutter_plugin_plus/ar_flutter_plugin_plus.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';

import '../../../core/widgets/app_bottom_navigation.dart';
import '../../../model/entities/ar_object.dart';
import '../../../viewmodel/ar/ar_placement_viewmodel.dart';
import 'widgets/ar_placement_top_bar.dart';
import 'widgets/ar_scanning_guide.dart';
import 'widgets/ar_storytelling_panel.dart';
import 'widgets/ar_action_menu.dart';


/// Screen corresponding to `AR Placement Screen` in the architecture diagram.
/// Pure View layer with strict MVVM adherence.
class ARPlacementScreen extends StatelessWidget {
  final ARMarker? selectedMarker;

  const ARPlacementScreen({super.key, this.selectedMarker});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ARPlacementViewModel>(
      create: (context) => ARPlacementViewModel()..init(selectedMarker),
      child: const _ARPlacementContent(),
    );
  }
}

class _ARPlacementContent extends StatefulWidget {
  const _ARPlacementContent();

  @override
  State<_ARPlacementContent> createState() => _ARPlacementContentState();
}

class _ARPlacementContentState extends State<_ARPlacementContent> with WidgetsBindingObserver {
  bool _isNativeViewReady = true;

  static const _navItems = [
    BottomNavItem(
      icon: Icons.camera_alt_outlined,
      selectedIcon: Icons.camera_alt,
      label: 'AR',
    ),
    BottomNavItem(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: 'Itinerary',
    ),
    BottomNavItem(
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
      label: 'Nearby',
    ),
    BottomNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _isNativeViewReady = true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setState(() => _isNativeViewReady = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ARPlacementViewModel>();
    const darkBg = Color(0xFF142121);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: darkBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Base Layer: ARCore Native Surface
          if (_isNativeViewReady)
            ARView(
              onARViewCreated: vm.onARViewCreated,
              planeDetectionConfig: PlaneDetectionConfig.horizontal,
            )
          else
            const SizedBox.expand(child: ColoredBox(color: darkBg)),

          // 1.5 AR Performance Shield: When 3D Model is active, occlude background AR surface to save GPU
          Selector<ARPlacementViewModel, bool>(
            selector: (context, model) => model.show3DLandmarkModel,
            builder: (context, show3d, child) {
              return IgnorePointer(
                child: AnimatedOpacity(
                  opacity: show3d ? 0.82 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: const ColoredBox(color: Color(0xFF0D1414)),
                ),
              );
            },
          ),

          // 2. Top Navigation & Status Bar
          const ARPlacementTopBar(),

          // 4. Plane Scanning & Placement Guide Prompt
          const ARScanningGuide(),

          // 5. Lightweight Non-blocking Model Placement Indicator
          Selector<ARPlacementViewModel, bool>(
            selector: (context, model) => model.isModelLoading,
            builder: (context, isLoading, child) {
              if (!isLoading) return const SizedBox.shrink();
              return Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142121).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.amberAccent,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Placing Manja on ground...",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 6. Action Menu (Shown when Avatar placed & before storytelling starts)
          const ARActionMenu(),

          // 7. Storytelling Narration Subtitles & Play Controls
          const ARStorytellingPanel(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        items: _navItems,
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            // Already on AR
          } else {
            Navigator.pop(context);
          }
        },
      ),
    );
  }
}