import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/config/interest_mapping.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/itinerary_validation_service.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/Itinerary/trip_customization_vm.dart';
import 'must_visit_selection_screen.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';

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
      create: (_) => Step2TripStyleVM(initialDraft: widget.draft),
      child: const _Step2TripStyleBody(),
    );
  }
}

// ─── _Step2TripStyleBody remains unchanged in UI ───────────────
class _Step2TripStyleBody extends StatelessWidget {
  const _Step2TripStyleBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step2TripStyleVM>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const WizardAppBar(step: 2),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const WizardProgressBar(activeSteps: 2),
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
                    maxInterests: vm.maxInterests,
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MustVisitSelectionScreen(
                        draft: vm.buildDraft(),
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

// ─── Private sub‑widgets ──────────────────────────────────────────

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
          "What's your travel style?",
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
            // 1. Boundary limit check
            maxLength: 50,
            // 2. Real-time format constraint
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z0-9\s\-,']")),
            ],
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.brandCharcoal),
            decoration: const InputDecoration(
              hintText: 'e.g., My Kuala Lumpur Getaway',
              hintStyle: TextStyle(color: AppColors.outline),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              // Hides the 0/50 counter for a cleaner UI
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }
}
// ─── Travel Dates – now enforce max 3 days ──────────────────────

class _TravelDates extends StatelessWidget {
  final Step2TripStyleVM vm;
  const _TravelDates({required this.vm});

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final DateTimeRange? picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) => _DateRangePickerDialog(
        firstDate: today,
        lastDate: vm.latestPossibleEndDate(), // now uses vm.maxTripDays = 3
        initialStart: vm.startDate,
        initialEnd: vm.endDate,
        maxEndFor: (start) => vm.latestPossibleEndDate(fromStart: start),
      ),
    );

    if (picked == null || !context.mounted) return;
    vm.setDates(start: picked.start, end: picked.end);
  }

  @override
  Widget build(BuildContext context) {
    String format(DateTime? d) =>
        d == null ? 'Pick date' : DateFormat('MMM d, yyyy').format(d);
    final days = vm.totalDays;

    final coverage = vm.weatherCoverage;
    final warning = vm.weatherWarning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // 👇 Updated to show max 3 days
        Text(
          vm.startDate != null
              ? 'Up to ${vm.maxTripDays} days · tap to change'
              : 'Tap to pick · up to ${vm.maxTripDays} days',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline),
        ),

        if (coverage != WeatherCoverage.unknown) ...[
          const SizedBox(height: 8),
          _WeatherCoverageBadge(coverage: coverage),
        ],

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

// ─── Date picker (unchanged, but uses VM's maxEndFor which is now 3) ──

class _DateRangePickerDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime Function(DateTime start) maxEndFor;

  const _DateRangePickerDialog({
    required this.firstDate,
    required this.lastDate,
    required this.maxEndFor,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<_DateRangePickerDialog> createState() =>
      _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  static const List<String> _weekdayLabels = [
    'S',
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
  ];

  DateTime? _start;
  DateTime? _end;
  late DateTime _displayedMonth;
  late final DateTime _today;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final anchor = _start ?? _today;
    _displayedMonth = DateTime(anchor.year, anchor.month);
  }

  bool get _hasCompleteRange => _start != null && _end != null;

  bool _isDisabled(DateTime day) {
    // ONLY disable dates that are strictly outside the global allowed bounds
    return day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);
  }

  void _onDayTapped(DateTime day) {
    if (_isDisabled(day)) return;

    setState(() {
      // 1. If nothing is selected, or both are already selected, start a fresh range
      if (_start == null || _hasCompleteRange) {
        _start = day;
        _end = null;
      }
      // 2. If they pick a date BEFORE the start date, shift the start date backward
      else if (day.isBefore(_start!)) {
        _start = day;
      }
      // 3. If they pick a date BEYOND the max limit, assume they are starting over
      else if (day.isAfter(widget.maxEndFor(_start!))) {
        _start = day;
        _end = null;
      }
      // 4. Valid end date (includes tapping the exact same day for a 1-day trip!)
      else {
        _end = day;
      }
    });
  }

  void _shiftMonth(int months) {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + months);
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstOfShown = _displayedMonth;
    final firstOfFirst =
    DateTime(widget.firstDate.year, widget.firstDate.month);
    final firstOfLast = DateTime(widget.lastDate.year, widget.lastDate.month);
    final canGoPrev = firstOfShown.isAfter(firstOfFirst);
    final canGoNext = firstOfShown.isBefore(firstOfLast);

    final gridStart =
    firstOfShown.subtract(Duration(days: firstOfShown.weekday % 7));

    String hint;
    if (_start == null) {
      hint = 'Select a start date';
    } else if (_end == null) {
      final maxEnd = widget.maxEndFor(_start!);
      final minEnd =
      _start!.isBefore(widget.firstDate) ? widget.firstDate : _start!;
      hint = 'End date must be between '
          '${DateFormat('MMM d').format(minEnd)} and '
          '${DateFormat('MMM d').format(maxEnd)}';
    } else {
      final days = _end!.difference(_start!).inDays + 1;
      hint = '$days day${days == 1 ? '' : 's'} selected';
    }

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick travel dates',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandCharcoal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandGreen,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: canGoPrev ? () => _shiftMonth(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: AppColors.brandGreen,
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(firstOfShown),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandCharcoal,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: canGoNext ? () => _shiftMonth(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: AppColors.brandGreen,
                  ),
                ],
              ),
              Row(
                children: _weekdayLabels
                    .map(
                      (label) => Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6 * 44,
                child: Column(
                  children: List.generate(6, (week) {
                    return Expanded(
                      child: Row(
                        children: List.generate(7, (weekday) {
                          final day = gridStart
                              .add(Duration(days: week * 7 + weekday));
                          return Expanded(
                            child: _buildDayCell(day),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.outline,
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _hasCompleteRange
                          ? () => Navigator.of(context).pop(
                        DateTimeRange(start: _start!, end: _end!),
                      )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandGreen,
                        disabledBackgroundColor:
                        AppColors.outlineLight.withOpacity(0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        'Select',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime day) {
    final inMonth =
        day.month == _displayedMonth.month && day.year == _displayedMonth.year;
    if (!inMonth) return const SizedBox.shrink();

    final disabled = _isDisabled(day);
    final isStart = _start != null && _isSameDay(day, _start!);
    final isEnd = _end != null && _isSameDay(day, _end!);
    final isSelected = isStart || isEnd;
    final inRange =
        _hasCompleteRange && day.isAfter(_start!) && day.isBefore(_end!);
    final inValidWindow = _start != null &&
        _end == null &&
        !day.isBefore(_start!) &&
        !day.isAfter(widget.maxEndFor(_start!));

    // NEW: Check if this specific day is beyond the current 3-day limit
    final isBeyondMax = _start != null && _end == null && day.isAfter(widget.maxEndFor(_start!));
    final isToday = _isSameDay(day, _today);

    Color? bg;
    if (isSelected) {
      bg = AppColors.brandGreen;
    } else if (inRange) {
      bg = AppColors.brandGreenLight;
    } else if (inValidWindow && !disabled) {
      bg = AppColors.brandGreenLight.withOpacity(0.45);
    }

    // UPDATE: If it's beyond max, make it look slightly faded, but NOT fully disabled
    final fg = isSelected
        ? Colors.white
        : disabled
        ? AppColors.outlineLight
        : isBeyondMax
        ? AppColors.brandCharcoal.withOpacity(0.4) // Soft hint that it's outside the range
        : AppColors.brandCharcoal;

    return GestureDetector(
      onTap: disabled ? null : () => _onDayTapped(day),
      child: Container(
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: bg,
          shape: CircleBorder(
            side: isToday && !isSelected
                ? BorderSide(color: AppColors.brandGreen.withOpacity(0.6))
                : BorderSide.none,
          ),
        ),
        child: Text(
          '${day.day}',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

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
      {'icon': Icons.sailing_rounded, 'label': 'Slow'},
      {'icon': Icons.directions_walk_rounded, 'label': 'Standard'},
      {'icon': Icons.directions_run_rounded, 'label': 'Fast'},
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

// ─── Interests – now enforce max 2 ─────────────────────────────

class _Interests extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final int maxInterests; // 👈 new parameter

  const _Interests({
    required this.selected,
    required this.onToggle,
    required this.maxInterests,
  });

  @override
  Widget build(BuildContext context) {
    final allKeys = InterestMapping.interestToGoogleTypes.keys.toList();
    final max = maxInterests; // 👈 use VM's value
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