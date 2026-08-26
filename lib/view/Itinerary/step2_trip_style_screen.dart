import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/config/interest_mapping.dart';
import '../../core/theme/colors.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/ItineraryModel/step2_trip_style_vm.dart';
import 'step3_add_place_screen.dart';

class Step2TripStyleScreen extends StatefulWidget {
  final TripDraft draft;
  const Step2TripStyleScreen({super.key, required this.draft});

  @override
  State<Step2TripStyleScreen> createState() => _Step2TripStyleScreenState();
}

class _Step2TripStyleScreenState extends State<Step2TripStyleScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Step2TripStyleVM>(
      create: (_) => Step2TripStyleVM(widget.draft),
      child: const _Step2TripStyleBody(),
    );
  }
}

class _Step2TripStyleBody extends StatelessWidget {
  const _Step2TripStyleBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step2TripStyleVM>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const _AppBar(step: 2),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const _ProgressBar(activeSteps: 2),
                  const SizedBox(height: 24),
                  _Header(vm: vm),
                  const SizedBox(height: 24),
                  _TripName(
                    initialValue: vm.tripName,
                    onChanged: vm.setTripName,
                  ),
                  const SizedBox(height: 24),
                  _TravelDates(vm: vm),
                  const SizedBox(height: 24),
                  _ExplorationTime(
                    selected: vm.exploration,
                    onSelected: vm.setExploration,
                  ),
                  const SizedBox(height: 24),
                  _TravelPace(
                    selected: vm.pace,
                    onSelected: vm.setPace,
                  ),
                  const SizedBox(height: 24),
                  _Interests(
                    selected: vm.interests,
                    onToggle: vm.toggleInterest,
                  ),
                  const SizedBox(height: 24),
                  _Notes(
                    initialValue: vm.notes,
                    onChanged: vm.setNotes,
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
            _FooterButton(
              onPressed: () {
                final errors = vm.validate();
                if (errors.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(errors.values.first),
                        backgroundColor: Colors.red,
                      ),
                    );
                  return;
                }

                try {
                  final draft = vm.buildDraft();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Step3AddPlaceScreen(
                        draft: draft,
                      ),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(e.toString().replaceFirst('Bad state: ', '')),
                        backgroundColor: Colors.red,
                      ),
                    );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private sub‑widgets for Step 2 ──────────────────────────

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final int step;
  const _AppBar({required this.step});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.background.withOpacity(0.9),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.brandCharcoal),
              onPressed: () => Navigator.maybePop(context),
              padding: EdgeInsets.zero,
            ),
            const Spacer(),
            Text(
              'STEP $step OF 4',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.outline,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.brandCharcoal),
              onPressed: () {},
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

class _ProgressBar extends StatelessWidget {
  final int activeSteps;
  const _ProgressBar({required this.activeSteps});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2,
            width: double.infinity,
            color: AppColors.outlineLight.withOpacity(0.6),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              final active = i < activeSteps;
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.brandGreen : AppColors.background,
                  border: Border.all(
                    color: active ? AppColors.brandGreen : AppColors.outlineLight,
                    width: 2,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.background, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Step2TripStyleVM vm;
  const _Header({required this.vm});

  @override
  Widget build(BuildContext context) {
    final dests = vm.destinations.isNotEmpty ? vm.destinations.join(' • ') : 'Destination';
    final dateText = vm.startDate != null && vm.endDate != null
        ? '${vm.totalDays} days · ${DateFormat('MMM d').format(vm.startDate!)} – ${DateFormat('MMM d').format(vm.endDate!)}'
        : 'Pick your dates';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, size: 16, color: AppColors.outline),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$dests | $dateText',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.outline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "What's your\ntravel style?",
          style: GoogleFonts.playfairDisplay(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: AppColors.brandCharcoal,
          ),
        ),
      ],
    );
  }
}

class _TripName extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  const _TripName({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_TripName> createState() => _TripNameState();
}

class _TripNameState extends State<_TripName> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Name your trip',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineLight.withOpacity(0.5)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 4), blurRadius: 16)
            ],
          ),
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.brandCharcoal),
            decoration: const InputDecoration(
              hintText: 'e.g., My Kuala Lumpur Getaway',
              hintStyle: TextStyle(color: AppColors.outline),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _TravelDates extends StatelessWidget {
  final Step2TripStyleVM vm;
  const _TravelDates({required this.vm});

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: vm.startDate != null && vm.endDate != null
          ? DateTimeRange(start: vm.startDate!, end: vm.endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandGreen,
              onPrimary: Colors.white,
              onSurface: AppColors.brandCharcoal,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      vm.setDates(start: picked.start, end: picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    String format(DateTime? d) =>
        d == null ? 'Pick date' : DateFormat('MMM d, yyyy').format(d);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel Dates',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickRange(context),
          child: Row(
            children: [
              _dateCard('START DATE', format(vm.startDate)),
              const SizedBox(width: 12),
              _dateCard('END DATE', format(vm.endDate)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${vm.totalDays} day(s) · tap to change',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
        ),
      ],
    );
  }

  Widget _dateCard(String label, String date) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brandGrayLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineLight.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.outline,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.brandGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    date,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandCharcoal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorationTime extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _ExplorationTime({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const options = [
      'Standard (9 AM - 8 PM)',
      'Relaxed (10 AM - 6 PM)',
      'Intense (8 AM - 10 PM)',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exploration Time',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: options.map((option) {
            final isSelected = option == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onSelected(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandGreenLight : AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.brandGreen : AppColors.outlineLight.withOpacity(0.5),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 2), blurRadius: 10)
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        option,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppColors.brandGreen : AppColors.brandCharcoal,
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? AppColors.brandGreen : AppColors.outlineLight,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TravelPace extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _TravelPace({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const paces = [
      {
        'icon': Icons.sailing_rounded,
        'label': 'Slow',
        'sub': '~2 spots/day',
      },
      {
        'icon': Icons.directions_walk_rounded,
        'label': 'Standard',
        'sub': '~4 spots/day',
      },
      {
        'icon': Icons.directions_run_rounded,
        'label': 'Fast',
        'sub': '~6 spots/day',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel Pace',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: paces.map((p) {
            final label = p['label'] as String;
            final isSelected = selected == label;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelected(label),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandGreenLight : AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.brandGreen : AppColors.outlineLight.withOpacity(0.5),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 4), blurRadius: 12)
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        p['icon'] as IconData,
                        size: 24,
                        color: isSelected ? AppColors.brandGreen : AppColors.outline,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? AppColors.brandGreen : AppColors.brandCharcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p['sub'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? AppColors.brandGreen.withOpacity(0.8) : AppColors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Interests extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _Interests({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final allKeys = InterestMapping.interestToGoogleTypes.keys.toList();

    const icons = {
      'History & Culture': Icons.museum_rounded,
      'Nature & Outdoors': Icons.park_rounded,
      'Food & Culinary': Icons.restaurant_rounded,
      'Thrills & Entertainment': Icons.attractions_rounded,
      'Shopping & Markets': Icons.shopping_bag_rounded,
      'Nightlife & Social': Icons.nightlife_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'What excites you?',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.brandCharcoal,
              ),
            ),
            Text(
              'SELECT MULTIPLE',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allKeys.map((label) {
            final isSelected = selected.contains(label);
            final icon = icons[label] ?? Icons.stars_rounded;
            return GestureDetector(
              onTap: () => onToggle(label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.brandGreen : AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected ? AppColors.brandGreen : AppColors.outlineLight.withOpacity(0.6),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 2), blurRadius: 10)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected ? Colors.white : AppColors.brandCharcoal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.brandCharcoal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Notes extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  const _Notes({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Additional Notes',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineLight.withOpacity(0.5)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 4), blurRadius: 16)
            ],
          ),
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            maxLines: 3,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.brandCharcoal),
            decoration: const InputDecoration(
              hintText: 'e.g., Dietary restrictions or specific places to visit',
              hintStyle: TextStyle(color: AppColors.outline, fontSize: 13),
              contentPadding: EdgeInsets.all(16),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _FooterButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step2TripStyleVM>();
    final canProceed = vm.canProceed;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withOpacity(0.0),
                AppColors.background,
              ],
              stops: const [0.0, 0.4],
            ),
          ),
          child: ElevatedButton.icon(
            onPressed: canProceed ? onPressed : null,
            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
            label: Text(
              'Craft My Itinerary',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandTerracotta,
              disabledBackgroundColor: AppColors.outlineLight,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              elevation: 4,
              shadowColor: AppColors.brandTerracotta.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }
}