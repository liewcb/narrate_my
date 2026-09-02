import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/model/entities/place.dart'; // ✅ import your existing Place model

class AddPlaceScreen extends StatefulWidget {
  final List<Place> candidates;
  final String? title;
  final String? subtitle;

  const AddPlaceScreen({
    super.key,
    required this.candidates,
    this.title,
    this.subtitle,
  });

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  // Theme colors (keep these matching your app)
  static const Color brandBg = Color(0xFFF6F3EB);
  static const Color surfaceCard = Colors.white;
  static const Color surfaceInactive = Color(0xFFE6E2D6);
  static const Color brandActivePill = Color(0xFF194D44);
  static const Color primaryContainer = Color(0xFFD48152);
  static const Color textMuted = Color(0xFF9E9B93);
  static const Color onSurface = Color(0xFF1B1B1B);
  static const Color tertiary = Color(0xFF5F5E58);

  String _searchQuery = '';
  String _selectedCategory = 'All';

  List<String> get _categories {
    final cats = widget.candidates.map((p) => p.category ?? 'Uncategorized').toList();
    return ['All', ...cats.toSet()];
  }

  List<Place> get _filteredPlaces {
    return widget.candidates.where((place) {
      final matchesCategory = _selectedCategory == 'All' ||
          (place.category ?? 'Uncategorized') == _selectedCategory;
      final matchesSearch = place.placeName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase()) ||
          (place.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: brandBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: Text(
          widget.title ?? 'Add a Place',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (widget.subtitle != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              alignment: Alignment.centerLeft,
              child: Text(
                widget.subtitle!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: textMuted,
                ),
              ),
            ),
          // Category pills
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? brandActivePill : surfaceInactive,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      category,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : tertiary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: surfaceCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: GoogleFonts.inter(fontSize: 16, color: onSurface),
                decoration: InputDecoration(
                  icon: const Icon(Icons.search, color: textMuted),
                  hintText: 'Search places',
                  hintStyle: GoogleFonts.inter(fontSize: 16, color: textMuted),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filteredPlaces.isEmpty
                ? Center(
              child: Text(
                'No places found.',
                style: GoogleFonts.inter(fontSize: 14, color: textMuted),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _filteredPlaces.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final place = _filteredPlaces[index];
                return _buildPlaceCard(place);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(Place place) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: surfaceInactive,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.place, color: tertiary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.placeName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (place.category != null)
                  Text(
                    place.category!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textMuted,
                    ),
                  ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, place),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryContainer,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}