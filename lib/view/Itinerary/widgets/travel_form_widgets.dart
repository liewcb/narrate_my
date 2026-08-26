import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SectionTitle({Key? key, required this.title, this.subtitle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color brandCharcoal = Color(0xFF333333);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: brandCharcoal,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class ItineraryTitleField extends StatelessWidget {
  const ItineraryTitleField({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color brandGreen = Color(0xFF0F3D35);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: brandGreen.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: "e.g., My Kuala Lumpur Getaway",
          hintStyle: TextStyle(color: Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

// ==========================================
// INTERACTIVE DATES SECTION
// ==========================================
class TravelDatesSection extends StatefulWidget {
  const TravelDatesSection({Key? key}) : super(key: key);

  @override
  State<TravelDatesSection> createState() => _TravelDatesSectionState();
}

class _TravelDatesSectionState extends State<TravelDatesSection> {
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F3D35), // header background color
              onPrimary: Colors.white, // header text color
              onSurface: Colors.black, // body text color
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String startText = _startDate != null ? DateFormat('MMM dd, yyyy').format(_startDate!) : "Select Date";
    String endText = _endDate != null ? DateFormat('MMM dd, yyyy').format(_endDate!) : "Select Date";

    return GestureDetector(
      onTap: _pickDateRange, // Open calendar on tap
      child: Row(
        children: [
          Expanded(child: _buildDateCard("START DATE", startText)),
          const SizedBox(width: 16),
          Expanded(child: _buildDateCard("END DATE", endText)),
        ],
      ),
    );
  }

  Widget _buildDateCard(String label, String date) {
    const Color brandGrayLight = Color(0xFFF2F2F2);
    const Color brandGreen = Color(0xFF0F3D35);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brandGrayLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: brandGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// INTERACTIVE EXPLORATION TIME
// ==========================================
class ExplorationTimeSection extends StatefulWidget {
  const ExplorationTimeSection({Key? key}) : super(key: key);

  @override
  State<ExplorationTimeSection> createState() => _ExplorationTimeSectionState();
}

class _ExplorationTimeSectionState extends State<ExplorationTimeSection> {
  String _selectedOption = "Standard (9 AM - 8 PM)";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildOption("Standard (9 AM - 8 PM)"),
        const SizedBox(height: 12),
        _buildOption("Relaxed (10 AM - 6 PM)"),
        const SizedBox(height: 12),
        _buildOption("Intense (8 AM - 10 PM)"),
      ],
    );
  }

  Widget _buildOption(String text) {
    const Color brandGreen = Color(0xFF0F3D35);
    bool isSelected = _selectedOption == text;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedOption = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isSelected ? brandGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isSelected ? brandGreen : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                fontSize: 16,
              ),
            ),
            isSelected
                ? const Icon(Icons.check_circle, color: brandGreen)
                : Container(
              width: 20, height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, width: 2)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// INTERACTIVE TRAVEL PACE
// ==========================================
class TravelPaceSection extends StatefulWidget {
  const TravelPaceSection({Key? key}) : super(key: key);

  @override
  State<TravelPaceSection> createState() => _TravelPaceSectionState();
}

class _TravelPaceSectionState extends State<TravelPaceSection> {
  String _selectedPace = "Standard";

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildPaceCard(Icons.airline_seat_recline_extra, "Slow")),
        const SizedBox(width: 12),
        Expanded(child: _buildPaceCard(Icons.directions_walk, "Standard")),
        const SizedBox(width: 12),
        Expanded(child: _buildPaceCard(Icons.directions_run, "Fast")),
      ],
    );
  }

  Widget _buildPaceCard(IconData icon, String label) {
    const Color brandGreenLight = Color(0xFFEAF0ED);
    const Color brandGreen = Color(0xFF0F3D35);
    bool isSelected = _selectedPace == label;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPace = label;
        });
      },
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? brandGreenLight : Colors.white,
            border: Border.all(color: isSelected ? brandGreen : Colors.grey.shade200, width: isSelected ? 2 : 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? brandGreen : Colors.grey.shade400, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? brandGreen : Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// INTERACTIVE INTERESTS (MULTIPLE SELECTION)
// ==========================================
class InterestsSection extends StatefulWidget {
  const InterestsSection({Key? key}) : super(key: key);

  @override
  State<InterestsSection> createState() => _InterestsSectionState();
}

class _InterestsSectionState extends State<InterestsSection> {
  // Use a Set to allow selecting multiple options
  final Set<String> _selectedInterests = {"Attractions", "Food"};

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildInterestChip("Attractions", Icons.stadium),
        _buildInterestChip("Food", Icons.restaurant),
        _buildInterestChip("Culture", null),
        _buildInterestChip("Shopping", null),
      ],
    );
  }

  Widget _buildInterestChip(String label, IconData? icon) {
    const Color brandGreen = Color(0xFF0F3D35);
    const Color outlineVariant = Color(0xFFBFC9C4);

    bool isSelected = _selectedInterests.contains(label);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedInterests.remove(label);
          } else {
            _selectedInterests.add(label);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? brandGreen : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? Colors.transparent : outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 8)
            ],
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class AdditionalNotesField extends StatelessWidget {
  const AdditionalNotesField({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const TextField(
        maxLines: 4,
        decoration: InputDecoration(
          hintText: "e.g., Any dietary restrictions or specific places you absolutely must visit?",
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(20),
        ),
      ),
    );
  }
}