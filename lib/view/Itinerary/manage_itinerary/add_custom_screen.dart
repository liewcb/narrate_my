import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../model/entities/bookmark.dart';
import 'package:narrate_my/view/Itinerary/itinerary_theme_tokens.dart';


/// Dummy bookmarks for testing the AddCustomStopScreen.
// final List<Bookmark> testBookmarks = [
//   Bookmark(
//     placeId: 'bm_001',
//     placeName: 'Central Market',
//     placeAddress: 'Jalan Hang Kasturi, 50050 Kuala Lumpur',
//     placeRating: 4.2,
//     placeTypes: 'shopping_mall,market',
//     placePhotoRef: 'AenMKlG5YVjO1W3R4qZvEf8hB9xV2pNlQ6tY',
//     placeLatitude: 3.1464,
//     placeLongitude: 101.6953,userId: '1',
//   ),
//   Bookmark(
//     placeId: 'bm_002',
//     placeName: 'Petronas Twin Towers',
//     placeAddress: 'Kuala Lumpur City Centre, 50088 Kuala Lumpur',
//     placeRating: 4.7,
//     placeTypes: 'tourist_attraction,landmark',
//     placePhotoRef: 'Bk8S3mN6tY7uJ5wX2vZ1qA0pL9kHdF',
//     placeLatitude: 3.1579,
//     placeLongitude: 101.7117,userId: '1',
//   ),
//   Bookmark(
//     placeId: 'bm_003',
//     placeName: 'National Museum',
//     placeAddress: 'Jalan Damansara, 50566 Kuala Lumpur',
//     placeRating: 4.1,
//     placeTypes: 'museum',
//     placePhotoRef: 'P3qLmN8oV6wX2yZ1rA0sT9uJ5kHdG',
//     placeLatitude: 3.1378,
//     placeLongitude: 101.6864,userId: '1',
//   ),
// ];

/// Dummy place details for the selected place.
final Map<String, dynamic> testPlaceDetails = {
  'name': "Uncle Lim's Secret Kopitiam",
  'address': 'Lorong Panggong, City Centre',
  'category': 'RESTAURANT',
  'imageUrl': 'https://lh3.googleusercontent.com/aida-public/AB6AXuD7sMqjJwniDkNSnDFw4lYdbUT4wQev7JionRYJw-N-I31zwLm0rw6wKwL3-8_C5oYZ-7IZBnQZlnk6HgZ4jkbWZi3RXNgxPz0OSBKNhTiZ7nlTkzcSRiUc_xA5kfsVS0yP2j8Nn3tKHNjzpphl4HKmj1H0aHvKL_40ZZrhj2dqyxs2uMzRO6lE_lvswuZ3XyM-VJsYyHp4U7e14Ux9xQV-khzp4FWcn3MP98CMRlubUiAJPaegabHx',
};

class AddCustomStopScreen extends StatefulWidget {
  const AddCustomStopScreen({Key? key}) : super(key: key);

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
  bool _hasConflict = false;

  /// Validates the form: both fields must be non-empty and parseable.
  bool get _isFormValid {
    final time = _startTimeController.text.trim();
    final dur = _durationController.text.trim();
    return time.isNotEmpty && dur.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _startTimeController.addListener(_onFieldChanged);
    _durationController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    // Re-evaluate conflict (simulated: conflict if time contains "11:")
    setState(() {
      _hasConflict = _startTimeController.text.contains('11:');
    });
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // Main Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: 120, // Padding for the sticky footer
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

          // Sticky Footer
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
      actions: const [
        SizedBox(width: 52), // Balances the center title against the leading icon
      ],
    );
  }

  Widget _buildWarningBanner() {
    if (!_hasConflict) return const SizedBox.shrink();
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
              "Schedule conflict. This time overlaps with an existing stop (Central Market: 10:30 AM - 12:00 PM).",
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
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search for a place...",
          hintStyle: TextStyle(color: _tertiary),
          prefixIcon: Icon(Icons.search, color: _tertiary),
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
    // Mapping string icon names to actual Flutter Icons
    IconData icon;
    if (iconName == "storefront") icon = Icons.storefront;
    else if (iconName == "apartment") icon = Icons.apartment;
    else icon = Icons.museum;

    return Container(
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
              // Image Thumbnail
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

              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tag
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

                    // Title
                    Text(
                      "Uncle Lim's Secret Kopitiam",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Location
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "Lorong Panggong, City Centre",
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
    final days = ["Day 1", "Day 2", "Day 3", "Day 4"];

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
            // Start Time Input
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Start Time",
                    style: TextStyle(fontSize: 12, color: _tertiary),
                  ),
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
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: TextFormField(
                      controller: _startTimeController,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.schedule, size: 20),
                        hintText: 'e.g. 11:00 AM',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: _hasConflict ? _dangerText : _onSurface,
                      ),
                    ),
                  ),
                  if (_startTimeController.text.trim().isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Start time is required",
                      style: TextStyle(fontSize: 11, color: _dangerText),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Duration Input
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Estimated Duration",
                    style: TextStyle(fontSize: 12, color: _tertiary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.transparent),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.hourglass_bottom, size: 20),
                        hintText: 'e.g. 1 hr 30 mins',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (_durationController.text.trim().isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Duration is required",
                      style: TextStyle(fontSize: 11, color: _dangerText),
                    ),
                  ],
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
                // Cancel Button
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _surfaceCard,
                      foregroundColor: _onSurface,
                      elevation: 0,
                      shadowColor: Colors.black.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: BorderSide(color: _surfaceDim),
                      ),
                    ),
                    onPressed: () {
                      Navigator.maybePop(context);
                    },
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Add to Itinerary Button (validated)
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isFormValid && !_hasConflict
                          ? _pineGreen
                          : _surfaceInactive,
                      foregroundColor: _isFormValid && !_hasConflict
                          ? Colors.white
                          : _textMuted,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      if (!_isFormValid) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Fill in the start time and duration first.'),
                            ),
                          );
                        return;
                      }
                      if (_hasConflict) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Resolve the schedule conflict before adding.'),
                            ),
                          );
                        return;
                      }
                      Navigator.maybePop(context);
                    },
                    child: const Text(
                      "Add to Itinerary",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
