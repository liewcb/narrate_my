import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/Itinerary/day_allocation_vm.dart';
import 'itinerary_generation_screen.dart';

class AddAllocationScreen extends StatefulWidget {
  final TripDraft draft;
  const AddAllocationScreen({super.key, required this.draft});

  @override
  State<AddAllocationScreen> createState() => _AddAllocationScreenState();
}

class _AddAllocationScreenState extends State<AddAllocationScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddAllocationVM>(
      create: (_) => AddAllocationVM(widget.draft),
      child: const _Step4SplitBody(),
    );
  }
}

class _Step4SplitBody extends StatelessWidget {
  const _Step4SplitBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddAllocationVM>();
    final totalDays = vm.totalDays;
    final destinations = vm.destinations;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WizardAppBar(step: 4),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: WizardProgressBar(activeSteps: 4),
                  ),
                  const SizedBox(height: 24),
                  _Title(totalDays: totalDays, vm: vm),
                  const SizedBox(height: 32),
                  _AllocationBar(
                    split: vm.daySplit,
                    destinations: destinations,
                    totalDays: totalDays,
                  ),
                  const SizedBox(height: 32),
                  _Timeline(
                    allocations: vm.allocations,
                    onChanged: vm.setDayCount,
                    onReorder: vm.reorderDestinations,
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(height: 45),
                ],
              ),
            ),
            _StickyCTA(
              totalDays: totalDays,
              onPressed: () {
                final errors = vm.validationErrors;
                if (errors.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(errors.values.first)));
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GenerationScreen(draft: vm.buildDraft()),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Title ──────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  final int totalDays;
  final AddAllocationVM vm;
  const _Title({required this.totalDays, required this.vm});

  @override
  Widget build(BuildContext context) {
    final sd = vm.startDate;
    final ed = vm.endDate;
    final range = (sd != null && ed != null) ? '${_fmt(sd)}–${_fmt(ed)}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Split your trip',
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: 'You have ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.inkFaint,
              ),
              children: [
                TextSpan(
                  text: '$totalDays days',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                if (range.isNotEmpty)
                  TextSpan(
                    text: ' from $range.',
                    style: const TextStyle(
                      color: AppColors.inkFaint,
                    ),
                  ),
                const TextSpan(
                  text: ' Drag to adjust how long you stay in each place.',
                  style: TextStyle(color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${_month(d.month)} ${d.day}';
  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];
}

// ─── Allocation Bar ────────────────────────────────────────────────

class _AllocationBar extends StatelessWidget {
  final Map<String, int> split;
  final List<String> destinations;
  final int totalDays;
  const _AllocationBar({
    required this.split,
    required this.destinations,
    required this.totalDays,
  });

  @override
  Widget build(BuildContext context) {
    final total = split.values.fold(0, (a, b) => a + b);
    final balanced = total == totalDays && split.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Fixed overflow: use Expanded + Flexible
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Allocation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: balanced ? AppColors.green : AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    balanced ? '✓ $total / $totalDays days' : '$total / $totalDays days',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: balanced ? AppColors.green : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: destinations.map((d) {
                  final days = split[d] ?? 1;
                  return Expanded(
                    flex: days,
                    child: Container(
                      height: 8,
                      color: _segmentColor(d),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: destinations.map((d) {
                final days = split[d] ?? 1;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _segmentColor(d),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$d · ${days}d',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _segmentColor(String destination) {
    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.teal,
      AppColors.gold,
      AppColors.green,
      const Color(0xFF8E44AD),
    ];
    final index = destination.hashCode.abs() % colors.length;
    return colors[index];
  }
}

// ─── Timeline ──────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final List<DestinationAllocation> allocations;
  final void Function(String destination, int days) onChanged;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _Timeline({
    required this.allocations,
    required this.onChanged,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.teal,
      AppColors.gold,
      AppColors.green,
      const Color(0xFF8E44AD),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: allocations.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final alloc = allocations[index];
          return _DestinationCard(
            key: ValueKey(alloc.destination),
            index: index,
            allocation: alloc,
            color: colors[index % colors.length],
            onChanged: (val) => onChanged(alloc.destination, val),
          );
        },
      ),
    );
  }
}

// ─── Destination Card ─────────────────────────────────────────────

class _DestinationCard extends StatelessWidget {
  final int index;
  final DestinationAllocation allocation;
  final Color color;
  final ValueChanged<int> onChanged;

  const _DestinationCard({
    super.key,
    required this.index,
    required this.allocation,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final destination = allocation.destination;
    final days = allocation.days;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.surface,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                allocation.dayLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.location_city, color: color, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              allocation.dateRangeLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(
                          Icons.drag_indicator,
                          color: AppColors.inkFaint,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stepperButton(
                          icon: Icons.remove,
                          onTap: () {
                            if (days > 1) onChanged(days - 1);
                          },
                        ),
                        Text(
                          '$days Days',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        _stepperButton(
                          icon: Icons.add,
                          onTap: () {
                            onChanged(days + 1);
                          },
                        ),
                      ],
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

  Widget _stepperButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: AppColors.ink),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 18,
      ),
    );
  }
}

// ─── Sticky CTA ────────────────────────────────────────────────────

class _StickyCTA extends StatelessWidget {
  final int totalDays;
  final VoidCallback onPressed;
  const _StickyCTA({required this.totalDays, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: AppColors.bg.withOpacity(0.95),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.auto_awesome, color: AppColors.surface),
              label: Text(
                'Generate My $totalDays-Day Itinerary',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surface,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can still edit everything after',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}