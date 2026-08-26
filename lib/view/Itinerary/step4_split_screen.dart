// lib/screens/step4_split_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/ItineraryModel/step4_split_vm.dart';
import 'step5_generation_screen.dart';

class Step4SplitScreen extends StatefulWidget {
  final TripDraft draft;
  const Step4SplitScreen({super.key, required this.draft});

  @override
  State<Step4SplitScreen> createState() => _Step4SplitScreenState();
}

class _Step4SplitScreenState extends State<Step4SplitScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Step4SplitVM>(
      create: (_) => Step4SplitVM(widget.draft),
      child: const _Step4SplitBody(),
    );
  }
}

class _Step4SplitBody extends StatelessWidget {
  const _Step4SplitBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step4SplitVM>();
    final totalDays = vm.totalDays;
    final destinations = vm.destinations;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              // Spacing: Bottom padding ensures content clears the fixed bottom CTA
              padding: const EdgeInsets.only(bottom: 160),
              child: Column(
                // Alignment: Strict left alignment across all section blocks
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const _AppBar(),
                  // Spacing: 32px strict margin between major sections (8px grid)
                  const SizedBox(height: 32),
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
                  const SizedBox(height: 24),
                  _AutoBalanceButton(onPressed: vm.autoBalanceDays),
                  const SizedBox(height: 32),
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
                    builder: (_) => Step5GenerationScreen(draft: vm.buildDraft()),
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

// ─── Private Sub‑Widgets ──────────────────────────────────────

class _AppBar extends StatelessWidget {
  const _AppBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Alignment: 24px horizontal grid margin
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Simplification: Flat button container, no elevation or heavy drop shadows
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.brandGreen),
                  onPressed: () => Navigator.maybePop(context),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(4, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 24,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < 4 ? AppColors.brandGreen : AppColors.outlineLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Hierarchy: 14px regular muted text for step indicator
          const Text(
            'Step 4 of 4 · Plan Your Days',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final int totalDays;
  final Step4SplitVM vm;
  const _Title({required this.totalDays, required this.vm});

  @override
  Widget build(BuildContext context) {
    final sd = vm.startDate;
    final ed = vm.endDate;
    final range = (sd != null && ed != null) ? '${_fmt(sd)}–${_fmt(ed)}' : '';

    return Padding(
      // Alignment: Shares identical 24px horizontal grid line
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        // Alignment: Left aligned text
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hierarchy: Main header strictly 24px bold
          Text(
            'Split your trip',
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
              color: AppColors.brandGreen,
            ),
          ),
          const SizedBox(height: 8),
          // Hierarchy: Secondary text strictly 14px regular muted color
          RichText(
            text: TextSpan(
              text: 'You have ',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.outline,
              ),
              children: [
                TextSpan(
                  text: '$totalDays days',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.brandGreen,
                  ),
                ),
                if (range.isNotEmpty)
                  TextSpan(
                    text: ' from $range.',
                    style: const TextStyle(
                      color: AppColors.outline,
                    ),
                  ),
                const TextSpan(
                  text: ' Drag to adjust how long you stay in each place.',
                  style: TextStyle(color: AppColors.outline),
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
      // Alignment: Shares 24px horizontal grid margin
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        // Spacing: Increased internal padding to strict 24px grid standard
        padding: const EdgeInsets.all(24),
        // Simplification: Clean flat background shade with no elevation or shadows
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Hierarchy: Section Header bold
                const Text(
                  'Your Allocation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.black,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: balanced ? AppColors.brandGreenLight : AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  // Hierarchy: Status text 14px font size
                  child: Text(
                    balanced ? '✓ $total / $totalDays days balanced' : '$total / $totalDays days',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: balanced ? AppColors.brandGreen : AppColors.dangerText,
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
                    // Hierarchy: Secondary text 14px regular muted color
                    Text(
                      '$d · ${days}d',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: AppColors.outline,
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
      AppColors.brandGreen,
      AppColors.brandTerracotta,
      AppColors.indigo,
      AppColors.brown,
      AppColors.teal,
      AppColors.purple,
    ];
    final index = destination.hashCode.abs() % colors.length;
    return colors[index];
  }
}

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
      AppColors.brandGreen,
      AppColors.brandTerracotta,
      AppColors.indigo,
      AppColors.brown,
      AppColors.teal,
      AppColors.purple,
    ];

    return Padding(
      // Alignment: Shared 24px vertical grid line
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
      // Spacing: 16px bottom margin between cards (8px grid)
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator icon
          Column(
            children: [
              // Simplification: Soft flat container, shadow removed
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              // Hierarchy: Secondary label 14px regular
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
          // Grouped Card Component
          Expanded(
            child: Container(
              // Spacing: Internal 24px padding rule
              padding: const EdgeInsets.all(24),
              // Simplification: Soft background card, removed shadows
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                // Alignment: Text left aligned
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
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Hierarchy: Secondary text 14px regular muted color
                            Text(
                              allocation.dateRangeLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(
                          Icons.drag_indicator,
                          color: AppColors.outline,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Stepper Control
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.creamBg,
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
                        // Hierarchy: Value text 14px bold
                        Text(
                          '$days Days',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: AppColors.black),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 18,
      ),
    );
  }
}

class _AutoBalanceButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AutoBalanceButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Alignment: 24px horizontal grid margin
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.auto_awesome, size: 16, color: AppColors.outline),
          label: const Text(
            'Auto-balance for me',
            // Hierarchy: 14px regular secondary text
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.outline,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.outlineLight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}

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
        // Alignment & Spacing: 24px horizontal grid padding, 32px top margin padding
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: AppColors.creamBg.withOpacity(0.95),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(
                'Generate My $totalDays-Day Itinerary',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0, // Simplification: Flat button aesthetic, shadows removed
              ),
            ),
            const SizedBox(height: 16),
            // Hierarchy: 14px regular muted secondary text
            const Text(
              'You can still edit everything after',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}