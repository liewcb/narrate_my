import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';
import 'package:provider/provider.dart';
import '../../model/business_logic/shared_services/trip_draft_notifier.dart';
import 'itinerary_final_screen.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/itinerary_generation_status.dart';
import '../../viewmodel/Itinerary/itinerary_generation_vm.dart';

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});
  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final List<Offset> planePositions = const [
    Offset(0.08, 0.72),
    Offset(0.45, 0.55),
    Offset(0.65, 0.45),
    Offset(0.75, 0.32),
  ];

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Step5GenerationVM>(
      create: (context) {
        final completedTripDraft = context.read<TripDraftNotifier>().draft;
        return Step5GenerationVM(completedTripDraft)..startGeneration();
      },
      child: _GenerationBody(planePositions: planePositions),
    );
  }
}

class _GenerationBody extends StatelessWidget {
  final List<Offset> planePositions;

  const _GenerationBody({required this.planePositions});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step5GenerationVM>();
    final isLoading = vm.isLoading;
    final currentStep = _stepIndex(vm.progressMessage);
    final planeIndex = currentStep.clamp(0, planePositions.length - 1);
    final result = vm.result;

    // Generation finished with a full success: navigate to the preview
    // screen (unchanged behavior — the success message is shown there).
    if (!isLoading &&
        vm.isReady &&
        result != null &&
        result.success &&
        (result.status == null ||
            result.status == ItineraryGenerationStatus.success)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Success message straight from the pipeline's classification —
        // shown only for a full success, never for partial results.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                result.status?.message ??
                    ItineraryGenerationStatus.success.message,
              ),
              backgroundColor: AppColors.brandGreen,
            ),
          );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => ItineraryFinalScreen(
              result: result,
              title: vm.draft.tripName.isEmpty ? 'My Trip' : vm.draft.tripName,
              itineraryId: vm.savedItineraryId,
              explorationTime: vm.draft.exploration ?? 'Standard',
              mustVisitPlaceIds: List.of(vm.draft.mustVisitPlaceIds),
              tripStartDate: vm.draft.startDate ?? DateTime.now(),
              // ✅ REMOVED the dead-context onRegenerate block here
              userId: vm.userId,
              draft: vm.draft,
            ),
          ),
          (route) => route.isFirst,
        );
      });
      return const SizedBox.shrink();
    }

    // Generation finished with a PARTIAL result (free time added, AI
    // fallback, constraint conflicts): show the pipeline-classified status
    // message before continuing. The reason comes from the pipeline — the
    // UI never guesses it.
    if (!isLoading && vm.isReady && result != null && result.success) {
      return Scaffold(
        backgroundColor: AppColors.creamBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WizardAppBar(step: 5),
                const SizedBox(height: 8),
                const WizardProgressBar(activeSteps: 5),
                const SizedBox(height: 24),
                _StatusNoticeView(
                  status: result.status,
                  onViewItinerary: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItineraryFinalScreen(
                          result: result,
                          title:
                          vm.draft.tripName.isEmpty ? 'My Trip' : vm.draft.tripName,
                          itineraryId: vm.savedItineraryId,
                          explorationTime:
                          vm.draft.exploration ?? 'Standard',
                          mustVisitPlaceIds:
                          List.of(vm.draft.mustVisitPlaceIds),
                          tripStartDate:
                          vm.draft.startDate ?? DateTime.now(),
                          // ✅ REMOVED the dead-context onRegenerate block here
                          userId: vm.userId,
                          draft: vm.draft,
                        ),
                      ),
                      (route) => route.isFirst,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WizardAppBar(step: 5),
              const SizedBox(height: 8),
              const WizardProgressBar(activeSteps: 5),
              const SizedBox(height: 24),
              if (vm.errorMessage != null) ...[
                _ErrorView(message: vm.errorMessage!),
              ] else if (isLoading) ...[
                _MapHero(planeOffset: planePositions[planeIndex]),
                const SizedBox(height: 32),
                _LoadingContent(
                  stage: vm.progressMessage ?? 'Preparing...',
                  currentStep: currentStep,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _stepIndex(String? message) {
    if (message == null) return 0;
    final stages = Step5GenerationVM.progressStages;
    // Find the first stage that the message starts with
    for (int i = 0; i < stages.length; i++) {
      if (message.startsWith(stages[i])) {
        return i;
      }
    }
    // Fallback: if the message contains the stage string (e.g., "Scoring places...")
    for (int i = 0; i < stages.length; i++) {
      if (message.contains(stages[i])) {
        return i;
      }
    }
    return 0;
  }
}

class _MapHero extends StatefulWidget {
  final Offset planeOffset;

  const _MapHero({required this.planeOffset});

  @override
  State<_MapHero> createState() => __MapHeroState();
}

class __MapHeroState extends State<_MapHero>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // High-res modern architectural / travel landscape overview
            Image.network(
              'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800&auto=format&fit=crop&q=80',
              fit: BoxFit.cover,
            ),
            // Elegant gradient overlay with subtle travel tint
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
            ),
            // Smooth curved flight path
            CustomPaint(painter: _RoutePainter()),
            // Starting Pin
            _buildPin(
              left: 0.12,
              bottom: 0.65,
              color: AppColors.brandGreen,
              label: 'Departure',
            ),
            // Destination Pin
            _buildPin(
              left: 0.72,
              bottom: 0.28,
              color: AppColors.brandTerracotta,
              label: 'Adventure',
            ),
            // Plane along path
            AnimatedPositioned(
              left: widget.planeOffset.dx * (MediaQuery.of(context).size.width - 64),
              bottom: widget.planeOffset.dy * 200,
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOutCubic,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.flight_takeoff_rounded,
                  color: AppColors.brandGreen,
                  size: 20,
                ),
              ),
            ),
            // Modern Glassmorphic Status Badge
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4CAF50).withOpacity(0.6),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GENERATING YOUR TRIP',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPin({
    required double left,
    required double bottom,
    required Color color,
    required String label,
  }) {
    return Positioned(
      left: left * (MediaQuery.of(context).size.width - 48),
      bottom: bottom * (MediaQuery.of(context).size.height - 48),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              return Container(
                width: 40 + 20 * _pulse.value,
                height: 40 + 20 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.3 * (1 - _pulse.value)),
                ),
                child: child,
              );
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const Icon(
                Icons.location_on,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF81C784)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.35,
        size.width * 0.72,
        size.height * 0.28,
      );

    const double dashWidth = 8.0;
    const double dashSpace = 8.0;
    double distance = 0.0;

    final dashedPath = Path();

    for (ui.PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        dashedPath.addPath(
          pathMetric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoadingContent extends StatelessWidget {
  final String stage;
  final int currentStep;

  const _LoadingContent({required this.stage, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Column(
      // Alignment: Strict left alignment
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hierarchy: Main Header strictly 24px bold
        Text(
          'Building your itinerary...',
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.2,
            color: AppColors.brandGreen,
          ),
        ),
        const SizedBox(height: 8),
        // Hierarchy: Subtitle text strictly 14px regular muted color
        Text(
          stage,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: 24),
        _StepList(currentStep: currentStep),
        const SizedBox(height: 24),
        const _FunFact(),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  final int currentStep;

  const _StepList({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final stages = Step5GenerationVM.progressStages;
    return Container(
      // Spacing: 24px internal card padding standard
      padding: const EdgeInsets.all(24),
      // Simplification: Clean flat background shade, shadows removed
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: List.generate(stages.length, (index) {
          final isDone = index < currentStep;
          final isActive = index == currentStep;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == stages.length - 1 ? 0 : 16,
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? AppColors.brandGreen
                        : isActive
                        ? AppColors.brandGreenLight
                        : AppColors.white,
                    border: Border.all(
                      color: isDone
                          ? AppColors.brandGreen
                          : isActive
                          ? AppColors.brandGreen
                          : AppColors.outlineLight,
                      width: isDone ? 0 : 2,
                    ),
                  ),
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : isActive
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.brandGreen,
                      ),
                    ),
                  )
                      : const Icon(
                    Icons.radio_button_unchecked,
                    size: 16,
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  // Hierarchy: Step labels set to 14px font size
                  child: Text(
                    stages[index],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isDone || isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isDone || isActive
                          ? AppColors.brandGreen
                          : AppColors.black,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreenLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.hourglass_top,
                      size: 14,
                      color: AppColors.brandGreen,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _FunFact extends StatelessWidget {
  const _FunFact();

  @override
  Widget build(BuildContext context) {
    return Container(
      // Spacing: 16px internal padding
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandGreenLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('💡', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 16),
          // Hierarchy: Paragraph text 14px
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Did you know? ',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brandGreen,
                ),
                children: const [
                  TextSpan(
                    text:
                    "Penang's George Town has over 12,000 heritage buildings - we'll route you through the best street art alleys.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppColors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off, color: AppColors.brandTerracotta, size: 48),
        const SizedBox(height: 16),
        // Hierarchy: 14px message label
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.outline),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.maybePop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}

/// Displays a PARTIAL generation result (itinerary exists, but the pipeline
/// classified it with a caveat: free time added, AI fallback used, or a
/// constraint conflict). Renders the pipeline's traveler-facing message
/// verbatim with a matching status icon — no technical details.
class _StatusNoticeView extends StatelessWidget {
  final ItineraryGenerationStatus? status;
  final VoidCallback onViewItinerary;

  const _StatusNoticeView({
    required this.status,
    required this.onViewItinerary,
  });

  @override
  Widget build(BuildContext context) {
    final message = status?.message ?? 'Your itinerary has been created.';
    final (icon, color) = _visualsFor(status);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(icon, color: color, size: 48),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onViewItinerary,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('View Itinerary'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  (IconData, Color) _visualsFor(ItineraryGenerationStatus? status) {
    switch (status) {
      case ItineraryGenerationStatus.aiUnavailable:
      case ItineraryGenerationStatus.aiResponseInvalid:
        return (Icons.auto_awesome_outlined, AppColors.brandGreen);
      case ItineraryGenerationStatus.fewSuitablePlaces:
        return (Icons.schedule_rounded, AppColors.brandGreen);
      case ItineraryGenerationStatus.scheduleTooFull:
        return (Icons.event_busy_rounded, AppColors.brandTerracotta);
      case ItineraryGenerationStatus.openingHoursConflict:
        return (Icons.access_time_rounded, AppColors.brandTerracotta);
      case ItineraryGenerationStatus.travelDistanceTooLong:
        return (Icons.route_rounded, AppColors.brandTerracotta);
      case ItineraryGenerationStatus.mustVisitUnavailable:
      case ItineraryGenerationStatus.mustVisitOutsideDestination:
      case ItineraryGenerationStatus.noSuitablePlaces:
        return (Icons.place_rounded, AppColors.brandTerracotta);
      default:
        return (Icons.info_outline_rounded, AppColors.brandGreen);
    }
  }
}