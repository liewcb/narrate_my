import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_vm.dart';
import '../../../../viewmodel/ar/ar_placement_vm.dart';

/// Scanning prompt guiding the user to move the device and tap on detected planes
class ARScanningGuide extends StatefulWidget {
  const ARScanningGuide({super.key});

  @override
  State<ARScanningGuide> createState() => _ARScanningGuideState();
}

class _ARScanningGuideState extends State<ARScanningGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swayController;
  late final Animation<double> _swayOffset;

  @override
  void initState() {
    super.initState();
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _swayOffset = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _swayController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _swayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleVm>();
    final topPadding = MediaQuery.of(context).padding.top + 90;

    return Selector<
      ARPlacementViewModel,
      ({bool isPlaced, bool hasStartedStorytelling, bool isPlaneDetected})
    >(
      selector:
          (context, vm) => (
            isPlaced: vm.isAvatarPlaced,
            hasStartedStorytelling: vm.hasStartedStorytelling,
            isPlaneDetected: vm.isPlaneDetected,
          ),
      builder: (context, data, child) {
        if (data.isPlaced || data.hasStartedStorytelling) {
          return const SizedBox.shrink();
        }

        final hasPlane = data.isPlaneDetected;
        final iconColor =
            hasPlane ? const Color(0xFF00E5FF) : Colors.amberAccent;
        final borderColor =
            hasPlane
                ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2);

        return Positioned(
          top: topPadding,
          left: 24,
          right: 24,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: hasPlane ? 1.5 : 1.0,
                ),
                boxShadow: [
                  if (hasPlane)
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _swayOffset,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(hasPlane ? 0 : _swayOffset.value, 0),
                        child: Icon(
                          hasPlane
                              ? Icons.touch_app_rounded
                              : Icons.smartphone_rounded,
                          color: iconColor,
                          size: 24,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      hasPlane
                          ? AppLocalizations.t('ar.tapBlueSurfaceToPlace')
                          : AppLocalizations.t('ar.noPlacementSurface'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
