// lib/view/Itinerary/add_custom_stop_screen.dart
import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../core/theme/app_theme.dart';
import '../../../model/entities/trip_draft.dart';

class AddCustomStopScreen extends StatefulWidget {
  final TripDraft tripDraft;
  const AddCustomStopScreen({Key? key, required this.tripDraft}) : super(key: key);

  @override
  State<AddCustomStopScreen> createState() => _AddCustomStopScreenState();
}

class _AddCustomStopScreenState extends State<AddCustomStopScreen> {
  // Brand Colors
  final Color _bg = AppColors.bg;
  final Color _surfaceCard = AppColors.surface;
  final Color _surfaceInactive = AppColors.surface2;
  final Color _surfaceDim = AppColors.surface2;

  final Color _pineGreen = AppColors.green;
  final Color _onSurface = AppColors.ink;
  final Color _tertiary = AppColors.inkSoft;
  final Color _textMuted = AppColors.inkFaint;

  final Color _dangerBg = AppColors.surface2;
  final Color _dangerText = AppColors.error;

  // State
  int _selectedDayIndex = 1;
  final _startTimeController = TextEditingController(text: '11:00 AM');
  final _durationController = TextEditingController(text: '1 hr 30 mins');
  final _searchController = TextEditingController();

  bool _hasConflict = false;
  bool _isOutOfBounds = false; // 👈 Tracks if search violates destination constraint
  String _searchQuery = '';

  bool get _isFormValid {
    final time = _startTimeController.text.trim();
    final dur = _durationController.text.trim();
    return time.isNotEmpty && dur.isNotEmpty && !_isOutOfBounds;
  }

  @override
  void initState() {
    super.initState();
    _startTimeController.addListener(_onFieldChanged);
    _durationController.addListener(_onFieldChanged);
    _searchController.addListener(_onSearchChanged);
  }

  void _onFieldChanged() {
    setState(() {
      _hasConflict = _startTimeController.text.contains('11:');
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _searchQuery = query;

      // Constraint Check based on Step 1 Destination Choice
      // e.g., if trip destinations include "Kuala Lumpur" or "Puchong", block conflicting queries
      final primaryDestination = widget.tripDraft.destinations.isNotEmpty
          ? widget.tripDraft.destinations.first.toLowerCase()
          : 'kuala lumpur';

      // Example simulation: if user searches for something containing a mismatched major city
      if (query.isNotEmpty) {
        if (primaryDestination.contains('kuala lumpur') &&
            (query.contains('penang') || query.contains('johor') || query.contains('langkawi'))) {
          _isOutOfBounds = true;
        } else {
          _isOutOfBounds = false;
        }
      } else {
        _isOutOfBounds = false;
      }
    });
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _durationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: 120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDestinationConstraintBanner(),
                const SizedBox(height: 16),
                _buildWarningBanner(),
                const SizedBox(height: 24),
                _buildSearchBar(),
                const SizedBox(height: 24),
                _buildBookmarksSection(),
                const SizedBox(height: 24),
                _buildPlaceDetails(),
                const SizedBox(height: 24),
                _buildAddToDay(),
                const SizedBox(height: 24),
                _buildSchedule(),
              ],
            ),
          ),
          _buildStickyFooter(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _bg.withOpacity(0.9),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surfaceInactive,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back, color: _onSurface),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      title: Text(
        "Add custom stop",
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _onSurface,
          letterSpacing: -0.5,
        ),
      ),
      actions: const [SizedBox(width: 52)],
    );
  }

  Widget _buildDestinationConstraintBanner() {
    final destination = widget.tripDraft.destinations.isNotEmpty
        ? widget.tripDraft.destinations.first
        : 'Selected Region';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: _pineGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Restricted to your chosen destination: $destination",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: _onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    if (!_hasConflict && !_isOutOfBounds) return const SizedBox.shrink();

    String message = "";
    if (_isOutOfBounds) {
      message = "Location constraint violation. Selected place is outside your trip's destination zone.";
    } else if (_hasConflict) {
      message = "Schedule conflict. This time overlaps with an existing stop (Central Market: 10:30 AM - 12:00 PM).";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dangerText.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: _dangerText, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: _dangerText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isOutOfBounds ? _dangerText : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: "Search location within destination...",
          hintStyle: TextStyle(color: _tertiary),
          prefixIcon: Icon(Icons.search, color: _tertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () => _searchController.clear(),
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildBookmarksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                "FROM YOUR BOOKMARKS",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _tertiary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                "View all",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _pineGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _buildBookmarkChip("storefront", "Central Market"),
              const SizedBox(width: 12),
              _buildBookmarkChip("apartment", "Petronas Towers"),
              const SizedBox(width: 12),
              _buildBookmarkChip("museum", "National Museum"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookmarkChip(String iconName, String label) {
    IconData icon = iconName == "storefront" ? Icons.storefront : (iconName == "apartment" ? Icons.apartment : Icons.museum);

    return GestureDetector(
      onTap: () {
        _searchController.text = label; // Auto fill search on click
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _surfaceDim.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _pineGreen),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            "PLACE DETAILS",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _tertiary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  "https://lh3.googleusercontent.com/aida-public/AB6AXuD7sMqjJwniDkNSnDFw4lYdbUT4wQev7JionRYJw-N-I31zwLm0rw6wKwL3-8_C5oYZ-7IZBnQZlnk6HgZ4jkbWZi3RXNgxPz0OSBKNhTiZ7nlTkzcSRiUc_xA5kfsVS0yP2j8Nn3tKHNjzpphl4HKmj1H0aHvKL_40ZZrhj2dqyxs2uMzRO6lE_lvswuZ3XyM-VJsYyHp4U7e14Ux9xQV-khzp4FWcn3MP98CMRlubUiAJPaegabHx",
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "RESTAURANT",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: _pineGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _searchQuery.isEmpty ? "Uncle Lim's Secret Kopitiam" : "Selected: ${_searchController.text}",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.tripDraft.destinations.isNotEmpty
                                ? "Mapped to ${widget.tripDraft.destinations.first}"
                                : "Lorong Panggong, City Centre",
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddToDay() {
    final days = List.generate(widget.tripDraft.endDate != null && widget.tripDraft.startDate != null
        ? widget.tripDraft.endDate!.difference(widget.tripDraft.startDate!).inDays + 1
        : 4, (index) => "Day ${index + 1}");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            "ADD TO DAY",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _tertiary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: List.generate(days.length, (index) {
              final isSelected = _selectedDayIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDayIndex = index;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _pineGreen : _surfaceInactive,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      days[index],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : _tertiary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            "SCHEDULE",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _tertiary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Start Time", style: TextStyle(fontSize: 12, color: _tertiary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hasConflict ? _dangerText : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: TextFormField(
                      controller: _startTimeController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.schedule, size: 20),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Estimated Duration", style: TextStyle(fontSize: 12, color: _tertiary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.hourglass_bottom, size: 20),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStickyFooter() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: _bg.withOpacity(0.8),
              border: Border(
                top: BorderSide(color: _surfaceDim.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _surfaceCard,
                      foregroundColor: _onSurface,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: BorderSide(color: _surfaceDim),
                      ),
                    ),
                    onPressed: () => Navigator.maybePop(context),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFormValid && !_hasConflict && !_isOutOfBounds
                          ? _pineGreen
                          : _surfaceInactive,
                      foregroundColor: _isFormValid && !_hasConflict && !_isOutOfBounds
                          ? Colors.white
                          : _textMuted,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      if (_isOutOfBounds) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot add place outside your selected destination zone.')),
                        );
                        return;
                      }
                      if (!_isFormValid) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fill in valid start time and duration.')),
                        );
                        return;
                      }
                      if (_hasConflict) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Resolve schedule conflict before adding.')),
                        );
                        return;
                      }
                      Navigator.maybePop(context);
                    },
                    child: const Text("Add to Itinerary"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}