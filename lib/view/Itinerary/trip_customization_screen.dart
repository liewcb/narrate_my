import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/config/interest_mapping.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/itinerary_validation_service.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/ItineraryModel/trip_customization_vm.dart';
import 'must_visit_selection_screen.dart';

class TripCustomizationScreen extends StatefulWidget {
  final TripDraft draft;
  const TripCustomizationScreen({super.key, required this.draft});

  @override
  State<TripCustomizationScreen> createState() => _TripCustomizationScreenState();
}

class _TripCustomizationScreenState extends State<TripCustomizationScreen> {
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
                  _TravelType(
                    selected: vm.travelType,
                    onSelected: vm.setTravelType,
                  ),
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
                  _Transportation(
                    selected: vm.transportation,
                    onSelected: vm.setTransportation,
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
                      builder: (_) => MustVisitSelectionScreen(
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
            // const Spacer(),
            // IconButton(
            //   icon: const Icon(Icons.more_horiz, color: AppColors.brandCharcoal),
            //   onPressed: () {},
            //   padding: EdgeInsets.zero,
            // ),
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

class _TravelType extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;

  const _TravelType({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const types = [
      {'label': 'Solo', 'icon': Icons.person_rounded},
      {'label': 'Couple', 'icon': Icons.favorite_rounded},
      {'label': 'Family', 'icon': Icons.family_restroom_rounded},
      {'label': 'Friends', 'icon': Icons.groups_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel Type',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: types.asMap().entries.map((entry) {
            final idx = entry.key;
            final t = entry.value;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            final isSelected = selected == label;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: idx < types.length - 1 ? 8.0 : 0.0),
                child: GestureDetector(
                  onTap: () => onSelected(label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandGreenLight : AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.brandGreen : AppColors.outlineLight.withOpacity(0.5),
                        width: isSelected ? 1.5 : 1,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 2), blurRadius: 10)
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: isSelected ? AppColors.brandGreen : AppColors.outline,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? AppColors.brandGreen : AppColors.brandCharcoal,
                          ),
                        ),
                      ],
                    ),
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

    // ✅ FIX: Start date limited so full trip stays in forecast
    final maxStartDate = vm.latestPossibleStartDate;

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      // ✅ lastDate = today + forecast range
      //    setDates() handles clamping to maxTripDays
      lastDate: vm.latestPossibleEndDate(),
      initialDateRange: vm.startDate != null && vm.endDate != null
          ? DateTimeRange(start: vm.startDate!, end: vm.endDate!)
          : null,
      saveText: 'Select',
      helpText: 'Pick travel dates',
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

    if (picked == null || !context.mounted) return;

    final wasClamped = vm.setDates(start: picked.start, end: picked.end);

    if (wasClamped && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Dates adjusted to max ${ItineraryValidationService.maxTripDays} days.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    String format(DateTime? d) =>
        d == null ? 'Pick date' : DateFormat('MMM d, yyyy').format(d);
    final days = vm.totalDays;

    // Weather coverage status
    final coverage = vm.weatherCoverage;
    final warning = vm.weatherWarning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Travel Dates',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.brandCharcoal,
              ),
            ),
            if (vm.startDate != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGreenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$days day${days == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandGreen,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Date Cards ──
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

        // ── Helper Text ──
        Text(
          vm.startDate != null
              ? 'Up to ${ItineraryValidationService.maxTripDays} days · tap to change'
              : 'Tap to pick · up to ${ItineraryValidationService.maxTripDays} days',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
        ),

        // ── Weather Coverage Badge ──
        if (coverage != WeatherCoverage.unknown) ...[
          const SizedBox(height: 8),
          _WeatherCoverageBadge(coverage: coverage),
        ],

        // ── Weather Warning Banner ──
        if (warning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: coverage == WeatherCoverage.outOfRange
                  ? Colors.red.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: coverage == WeatherCoverage.outOfRange
                    ? Colors.red.shade200
                    : Colors.orange.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  coverage == WeatherCoverage.outOfRange
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: coverage == WeatherCoverage.outOfRange
                      ? Colors.red.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: coverage == WeatherCoverage.outOfRange
                          ? Colors.red.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                const Icon(Icons.calendar_today_rounded,
                    size: 14, color: AppColors.brandGreen),
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

/// Small badge showing weather coverage status
class _WeatherCoverageBadge extends StatelessWidget {
  final WeatherCoverage coverage;
  const _WeatherCoverageBadge({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (coverage) {
      WeatherCoverage.full => (
      'Weather data available for all days',
      AppColors.brandGreen,
      Icons.check_circle_rounded,
      ),
      WeatherCoverage.primaryOnly => (
      'Primary forecast only (${ItineraryValidationService.primaryForecastDays}-day)',
      Colors.orange,
      Icons.info_outline_rounded,
      ),
      WeatherCoverage.outOfRange => (
      'Beyond weather forecast range',
      Colors.red,
      Icons.warning_amber_rounded,
      ),
      WeatherCoverage.unknown => (
      '',
      AppColors.outline,
      Icons.help_outline,
      ),
    };

    if (coverage == WeatherCoverage.unknown) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
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
    final max = ItineraryValidationService.maxInterests;
    final remaining = max - selected.length;

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
              '${selected.length}/$max',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: remaining == 0
                    ? AppColors.brandTerracotta
                    : AppColors.brandGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          remaining == 0
              ? 'You\'ve reached the maximum ($max interests)'
              : 'SELECT UP TO $max — $remaining remaining',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: remaining == 0 ? AppColors.brandTerracotta : AppColors.outline,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allKeys.map((label) {
            final isSelected = selected.contains(label);
            final isDisabled = !isSelected && remaining == 0;
            final icon = icons[label] ?? Icons.stars_rounded;
            return GestureDetector(
              onTap: isDisabled ? null : () => onToggle(label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.brandGreen
                      : isDisabled
                          ? AppColors.brandGrayLight
                          : AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.brandGreen
                        : AppColors.outlineLight.withOpacity(0.6),
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
                      color: isSelected
                          ? Colors.white
                          : isDisabled
                              ? AppColors.outline
                              : AppColors.brandCharcoal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isDisabled
                                ? AppColors.outline
                                : AppColors.brandCharcoal,
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

class _Transportation extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _Transportation({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const options = [
      {
        'title': 'Public Transit (LRT/MRT/KTM)',
        'desc': 'Accounts for rail networks and transfers, ideal for downtown city exploration.',
        'icon': Icons.directions_subway_rounded,
      },
      {
        'title': 'Driving / Car',
        'desc': 'Accounts for direct routing, Grab/Taxi pickup wait times, and parking search times.',
        'icon': Icons.directions_car_rounded,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transportation Mode',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.brandCharcoal,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: options.map((opt) {
            final title = opt['title'] as String;
            final desc = opt['desc'] as String;
            final icon = opt['icon'] as IconData;
            final isSelected = selected == title;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => onSelected(title),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandGreenLight : AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.brandGreen : AppColors.outlineLight.withOpacity(0.5),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected ? AppColors.brandGreen.withOpacity(0.08) : const Color(0x0A004D40),
                        offset: const Offset(0, 3),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.brandGreen.withOpacity(0.15) : AppColors.brandGrayLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 22,
                          color: isSelected ? AppColors.brandGreen : AppColors.outline,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? AppColors.brandGreen : AppColors.brandCharcoal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              desc,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                                color: isSelected ? AppColors.brandGreen.withOpacity(0.85) : AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? AppColors.brandGreen : AppColors.outlineLight,
                        size: 22,
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