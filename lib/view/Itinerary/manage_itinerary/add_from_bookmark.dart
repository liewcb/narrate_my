import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../model/entities/bookmark.dart';

List<Bookmark> getTestBookmarks() {
  return [
    Bookmark(
      placeId: 'ChIJM2t3x2y2zDERv9b5-1vJyF0',
      placeName: 'Petronas Twin Towers',
      placeAddress: 'Kuala Lumpur City Centre, 50088 Kuala Lumpur',
      placeRating: 4.7,
      placeTypes: 'tourist_attraction,landmark',
      placePhotoRef: 'AenMKlG5YVjO1W3R4qZvEf8hB9xV2pNlQ6tY',
      placeLatitude: 3.1579,
      placeLongitude: 101.7117, userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJL6aQpJ6-2DERWst5bQ0jGQo',
      placeName: 'Batu Caves',
      placeAddress: 'Gombak, 68100 Batu Caves, Selangor',
      placeRating: 4.5,
      placeTypes: 'tourist_attraction,hindu_temple',
      placePhotoRef: 'Bk8S3mN6tY7uJ5wX2vZ1qA0pL9kHdF',
      placeLatitude: 3.2374,
      placeLongitude: 101.6839,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJNZH2gU2-2DERj1S8tDq7z3E',
      placeName: 'Central Market',
      placeAddress: 'Jalan Hang Kasturi, 50050 Kuala Lumpur',
      placeRating: 4.2,
      placeTypes: 'shopping_mall,market',
      placePhotoRef: 'P3qLmN8oV6wX2yZ1rA0sT9uJ5kHdG',
      placeLatitude: 3.1464,
      placeLongitude: 101.6953,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJL7Lx2Z6-2DERlFwK6T6hDgY',
      placeName: 'Penang Hill',
      placeAddress: 'Bukit Bendera, 11300 Penang',
      placeRating: 4.6,
      placeTypes: 'tourist_attraction,nature_reserve',
      placePhotoRef: 'Q4rNmO9pW7xZ3aA2sB1tU0vJ6lIeH',
      placeLatitude: 5.4200,
      placeLongitude: 100.2780,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJ3UjK8U6-2DERF7pK1mB9NwQ',
      placeName: 'George Town Street Art',
      placeAddress: 'George Town, Penang',
      placeRating: 4.4,
      placeTypes: 'art_gallery,tourist_attraction',
      placePhotoRef: 'R5sOnP0qX8yA4bC3tU2vW7kJmIfG',
      placeLatitude: 5.4141,
      placeLongitude: 100.3288,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJK5vVpU6-2DERDg9sE7rF4zJ',
      placeName: 'Kek Lok Si Temple',
      placeAddress: 'Air Itam, 11500 Penang',
      placeRating: 4.3,
      placeTypes: 'buddhist_temple,tourist_attraction',
      placePhotoRef: 'S6tPp1rY9zB5cD4vU3wX8kLnJgH',
      placeLatitude: 5.4000,
      placeLongitude: 100.2760,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJkZg2mU6-2DER9h1QxT5zOeY',
      placeName: 'Langkawi Cable Car',
      placeAddress: 'Oriental Village, 07000 Langkawi',
      placeRating: 4.6,
      placeTypes: 'tourist_attraction,amusement_ride',
      placePhotoRef: 'T7uQq2sZ0aC6dE5wV4yX9lMoKhI',
      placeLatitude: 6.3500,
      placeLongitude: 99.8000,userId: '1',
    ),
    Bookmark(
      placeId: 'ChIJh3wRjU6-2DER2nL8pWxQvF0',
      placeName: 'Jonker Street Night Market',
      placeAddress: 'Jalan Hang Jebat, 75200 Melaka',
      placeRating: 4.1,
      placeTypes: 'market,night_market',
      placePhotoRef: 'U8wRr3tA0bD7eF6xZ5yA0mNpLiJ',
      placeLatitude: 2.1896,
      placeLongitude: 102.2501,userId: '1',
    ),
  ];
}

class AddFromBookmarksScreen extends StatefulWidget {
  final List<Bookmark>? bookmarks; // Optional: can pass or load from ViewModel

  const AddFromBookmarksScreen({super.key, this.bookmarks});

  @override
  State<AddFromBookmarksScreen> createState() => _AddFromBookmarksScreenState();
}

class _AddFromBookmarksScreenState extends State<AddFromBookmarksScreen> {
  // ─── State ────────────────────────────────────────────────────

  int _selectedDayIndex = 1; // "Day 2" active by default
  final Set<String> _selectedBookmarkIds = {};

  // ─── Bookmarks from widget or empty list ────────────────────

  List<Bookmark> get _bookmarks => widget.bookmarks ?? [];

  // ─── Lifecycle ───────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Pre-select the first bookmark if any exist
    if (_bookmarks.isNotEmpty) {
      _selectedBookmarkIds.add(_bookmarks.first.placeId);
    }
  }

  // ─── Actions ─────────────────────────────────────────────────

  void _toggleBookmark(String placeId) {
    setState(() {
      if (_selectedBookmarkIds.contains(placeId)) {
        _selectedBookmarkIds.remove(placeId);
      } else {
        _selectedBookmarkIds.add(placeId);
      }
    });
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Main Scrollable List
          ListView(
            padding: const EdgeInsets.only(
              top: 100,
              left: 20,
              right: 20,
              bottom: 140,
            ),
            children: [
              _buildSearchBar(),
              const SizedBox(height: 20),
              _buildDaySelector(),
              const SizedBox(height: 24),
              if (_bookmarks.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'No bookmarks yet.\nSave places you want to visit!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.outline,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                ..._bookmarks.map((bookmark) => _buildBookmarkCard(bookmark)).toList(),
            ],
          ),

          // Floating Chat Button
          Positioned(
            bottom: 110,
            right: 24,
            child: FloatingActionButton(
              onPressed: () {},
              backgroundColor: AppColors.brandGreen,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.chat_bubble, color: Colors.white),
            ),
          ),

          // Sticky Bottom Actions
          _buildStickyFooter(),
        ],
      ),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            backgroundColor: AppColors.creamBg.withOpacity(0.9),
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.brandCharcoal),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Text(
              "Add from bookmarks",
              style: TextStyle(
                fontFamily: 'Playfair Display',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.brandCharcoal,
                letterSpacing: -0.5,
              ),
            ),
            centerTitle: false,
          ),
        ),
      ),
    );
  }

  // ─── Search Bar ──────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search bookmarks...",
          hintStyle: TextStyle(color: AppColors.outline, fontSize: 14, fontFamily: 'Inter'),
          prefixIcon: Icon(Icons.search, color: AppColors.outline),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ─── Day Selector ────────────────────────────────────────────

  Widget _buildDaySelector() {
    final days = ["Day 1", "Day 2", "Day 3"];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "ADDING TO",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.outline,
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
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDayIndex = index;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandGreen : AppColors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: isSelected ? AppColors.brandGreen : AppColors.outlineLight,
                      ),
                    ),
                    child: Text(
                      days[index],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.brandCharcoal,
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

  // ─── Bookmark Card ───────────────────────────────────────────

  Widget _buildBookmarkCard(Bookmark bookmark) {
    final bool isChecked = _selectedBookmarkIds.contains(bookmark.placeId);

    // Build the photo URL from the reference
    final photoUrl = bookmark.placePhotoRef != null
        ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=200&photoreference=${bookmark.placePhotoRef}'
        : null;

    // Get the first type as subtitle
    final subtitle = bookmark.placeTypes?.split(',').first ?? 'Place';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main clickable card area
          InkWell(
            onTap: () => _toggleBookmark(bookmark.placeId),
            borderRadius: isChecked
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 64,
                      height: 64,
                      color: AppColors.outlineLight,
                      child: photoUrl != null
                          ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.outlineLight,
                          child: const Icon(Icons.image_not_supported, size: 24),
                        ),
                      )
                          : const Icon(Icons.place, size: 24, color: AppColors.outline),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Text Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookmark.placeName,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandCharcoal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: AppColors.outline,
                          ),
                        ),
                        // Show rating if available
                        if (bookmark.placeRating != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                bookmark.placeRating!.toStringAsFixed(1),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppColors.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Custom Circular Checkbox
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isChecked ? AppColors.brandGreen : Colors.transparent,
                      border: Border.all(
                        color: isChecked ? AppColors.brandGreen : AppColors.outlineLight,
                        width: 2,
                      ),
                    ),
                    child: isChecked
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content (Shown only when checked)
          if (isChecked) ...[
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.outlineLight.withOpacity(0.3))),
              ),
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 12),
              child: Row(
                children: [
                  // Start Time Block
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.creamBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: AppColors.brandTerracotta, size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "START TIME",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.outline,
                                ),
                              ),
                              Text(
                                "10:00 AM", // Default time - should come from selection
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandCharcoal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Duration Block
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.creamBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_empty, color: AppColors.brandTerracotta, size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "DURATION",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.outline,
                                ),
                              ),
                              Text(
                                "1 hr", // Default duration
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandCharcoal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Sticky Footer ───────────────────────────────────────────

  Widget _buildStickyFooter() {
    final selectedCount = _selectedBookmarkIds.length;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: AppColors.creamBg.withOpacity(0.9),
              border: Border(top: BorderSide(color: AppColors.outlineLight)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.brandCharcoal,
                      side: BorderSide(color: AppColors.outlineLight),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
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
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: selectedCount > 0
                        ? () {
                      // Get selected bookmark IDs
                      final selectedIds = _selectedBookmarkIds.toList();
                      // Return selected IDs to previous screen
                      Navigator.pop(context, selectedIds);
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandTerracotta,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      "Add $selectedCount Places",
                      style: const TextStyle(
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