import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';
import 'package:provider/provider.dart';
import '../../model/business_logic/shared_services/trip_draft_notifier.dart';
import 'itinerary_final_screen.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/itinerary_generation_status.dart';
import '../../model/entities/trip_draft.dart';
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

    if (!isLoading &&
        vm.isReady &&
        result != null &&
        result.success &&
        (result.status == null ||
            result.status == ItineraryGenerationStatus.success)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ItineraryFinalScreen(
              result: result,
              title: vm.draft.tripName.isEmpty ? 'My Trip' : vm.draft.tripName,
              itineraryId: vm.savedItineraryId,
              explorationTime: vm.draft.exploration ?? 'Standard',
              mustVisitPlaceIds: List.of(vm.draft.mustVisitPlaceIds),
              tripStartDate: vm.draft.startDate ?? DateTime.now(),
              userId: vm.userId,
              draft: vm.draft,
            ),
          ),
        );
      });
      return const SizedBox.shrink();
    }

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
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItineraryFinalScreen(
                          result: result,
                          title: vm.draft.tripName.isEmpty
                              ? 'My Trip'
                              : vm.draft.tripName,
                          itineraryId: vm.savedItineraryId,
                          explorationTime: vm.draft.exploration ?? 'Standard',
                          mustVisitPlaceIds:
                          List.of(vm.draft.mustVisitPlaceIds),
                          tripStartDate: vm.draft.startDate ?? DateTime.now(),
                          userId: vm.userId,
                          draft: vm.draft,
                        ),
                      ),
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
                _MapHero(
                  planeOffset: planePositions[planeIndex],
                  draft: vm.draft,
                ),
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
    for (int i = 0; i < stages.length; i++) {
      if (message.startsWith(stages[i])) {
        return i;
      }
    }
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
  final TripDraft draft;

  const _MapHero({
    required this.planeOffset,
    required this.draft,
  });

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

  (List<String>, String) _getDestinationInfo() {
    List<String> destinations = [];

    try {
      final dynamic rawDestinations = (widget.draft as dynamic).destinations;
      if (rawDestinations is List && rawDestinations.isNotEmpty) {
        destinations = rawDestinations.map((e) {
          // 1. Check if 'e' is a Map with a 'name' key
          if (e is Map && e.containsKey('name')) return e['name'].toString();

          // 2. Check if 'e' is an object with a '.name' or '.title' property
          try {
            final dynamic name = (e as dynamic).name ?? (e as dynamic).title;
            if (name != null && name.toString().isNotEmpty) return name.toString();
          } catch (_) {}

          return e.toString();
        }).toList();
      }
    } catch (_) {}

    // Fallback to tripName if list is still empty
    if (destinations.isEmpty) {
      final title = widget.draft.tripName.trim();
      destinations = [title.isNotEmpty ? title : 'Your Destination'];
    }

    int totalDays = 3;
    try {
      final dynamic rawDays =
          (widget.draft as dynamic).durationDays ?? (widget.draft as dynamic).days;
      if (rawDays is int && rawDays > 0) {
        totalDays = rawDays;
      } else if (widget.draft.startDate != null) {
        try {
          final dynamic endDate = (widget.draft as dynamic).endDate;
          if (endDate is DateTime) {
            totalDays = endDate.difference(widget.draft.startDate!).inDays + 1;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return (destinations, '${totalDays}d');
  }

  @override
  Widget build(BuildContext context) {
    final (destinations, durationStr) = _getDestinationInfo();
    final primaryDestination = destinations.first;
    final secondaryDestination =
    destinations.length > 1 ? destinations[1] : null;

    return Container(
      height: 280,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mapWidth = constraints.maxWidth;
            final mapHeight = constraints.maxHeight;

            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  'https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600&q=80',
                  fit: BoxFit.cover,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.creamBg.withOpacity(0.2),
                        AppColors.white.withOpacity(0.4),
                        AppColors.creamBg.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
                CustomPaint(painter: _RoutePainter()),

                // Centered Primary Destination Marker
                _buildCenteredPin(
                  xRatio: 0.5,
                  yRatio: 0.5,
                  parentWidth: mapWidth,
                  parentHeight: mapHeight,
                  color: AppColors.brandGreen,
                  label: '$primaryDestination · $durationStr',
                ),

                // Secondary Marker
                if (secondaryDestination != null)
                  _buildCenteredPin(
                    xRatio: 0.8,
                    yRatio: 0.3,
                    parentWidth: mapWidth,
                    parentHeight: mapHeight,
                    color: AppColors.brandTerracotta,
                    label: secondaryDestination,
                  )
                else
                  _buildCenteredPin(
                    xRatio: 0.8,
                    yRatio: 0.3,
                    parentWidth: mapWidth,
                    parentHeight: mapHeight,
                    color: AppColors.brandTerracotta,
                    label: 'Exploration',
                  ),

                // Flight Icon Positioned Relative to Map Hero
                AnimatedPositioned(
                  left: widget.planeOffset.dx * mapWidth - 16,
                  top: (1 - widget.planeOffset.dy) * mapHeight - 16,
                  duration: const Duration(milliseconds: 1300),
                  curve: Curves.easeInOut,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.flight,
                      color: AppColors.brandGreen,
                      size: 18,
                    ),
                  ),
                ),

                // Top Header Badge
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'GENERATING TRIP TO ${primaryDestination.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenteredPin({
    required double xRatio,
    required double yRatio,
    required double parentWidth,
    required double parentHeight,
    required Color color,
    required String label,
  }) {
    return Positioned(
      left: xRatio * parentWidth,
      top: yRatio * parentHeight,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  child: Center(child: child),
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
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brandGreen
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.4,
        size.width * 0.75,
        size.height * 0.32,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      padding: const EdgeInsets.all(24),
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