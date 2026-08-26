import 'package:flutter/material.dart';
import 'widgets/screen_header.dart';
import 'widgets/custom_segmented_toggle.dart';
import 'widgets/selected_place_chip.dart';
import 'widgets/place_card.dart';
import 'widgets/sticky_bottom_actions.dart';

class MustVisitPlacesScreen extends StatefulWidget {
  const MustVisitPlacesScreen({Key? key}) : super(key: key);

  @override
  State<MustVisitPlacesScreen> createState() => _MustVisitPlacesScreenState();
}

class _MustVisitPlacesScreenState extends State<MustVisitPlacesScreen> {
  bool _showBookmarks = true;

  // Colors
  final Color _bgColor = const Color(0xFFF6F3EB);
  final Color _primaryColor = const Color(0xFF00342B);
  final Color _mutedText = const Color(0xFF9E9B93);
  final Color _accentColor = const Color(0xFFD48152);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScreenHeader(primaryColor: _primaryColor),
                  const SizedBox(height: 24),

                  CustomSegmentedToggle(
                    showBookmarks: _showBookmarks,
                    primaryColor: _primaryColor,
                    mutedText: _mutedText,
                    onToggle: (isBookmarkTab) {
                      setState(() {
                        _showBookmarks = isBookmarkTab;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSelectedChipsSection(),
                  const SizedBox(height: 24),

                  if (_showBookmarks)
                    _buildBookmarksContent()
                  else
                    _buildSearchContent(),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: StickyBottomActions(
              bgColor: _bgColor,
              accentColor: _accentColor,
              mutedText: _mutedText,
              onContinue: () {
                // Navigate to next screen
              },
              onSkip: () {
                // Handle skip
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedChipsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "SELECTED (2)",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _mutedText, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SelectedPlaceChip(
              icon: Icons.bookmark,
              label: "Batu Caves",
              primaryColor: _primaryColor,
              onRemove: () {},
            ),
            SelectedPlaceChip(
              icon: Icons.location_on,
              label: "Uncle Lim's Cafe",
              primaryColor: _primaryColor,
              onRemove: () {},
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBookmarksContent() {
    return Column(
      children: [
        PlaceCard(
          title: "Batu Caves",
          rating: "4.8",
          imageUrl: "https://images.unsplash.com/photo-1603503250005-cb6d573ebc36?auto=format&fit=crop&w=300&q=80",
          categoryText: "Saved Place · Gombak",
          categoryIcon: Icons.bookmark,
          categoryIconBg: const Color(0xFFEAF0ED),
          categoryIconColor: _primaryColor,
          transitIcon: Icons.directions_car,
          transitTime: "15 min",
          duration: "2 hrs",
          isAdded: true,
          primaryColor: _primaryColor,
          accentColor: _accentColor,
          mutedText: _mutedText,
          onAddToggle: () {},
        ),
        const SizedBox(height: 16),
        PlaceCard(
          title: "Central Market",
          rating: "4.5",
          imageUrl: "https://images.unsplash.com/photo-1596422846543-75c6fc197f07?auto=format&fit=crop&w=300&q=80",
          categoryText: "Saved Place · KL",
          categoryIcon: Icons.bookmark,
          categoryIconBg: const Color(0xFFEAF0ED),
          categoryIconColor: _primaryColor,
          transitIcon: Icons.directions_walk,
          transitTime: "8 min",
          duration: "1.5 hrs",
          isAdded: false,
          primaryColor: _primaryColor,
          accentColor: _accentColor,
          mutedText: _mutedText,
          onAddToggle: () {},
        ),
        const SizedBox(height: 24),
        Center(child: Text("Load more bookmarks...", style: TextStyle(color: _mutedText, fontSize: 14))),
      ],
    );
  }

  Widget _buildSearchContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Search places...",
                    hintStyle: TextStyle(color: _mutedText, fontSize: 14),
                    prefixIcon: Icon(Icons.location_on, color: _mutedText),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.tune, color: _primaryColor),
                  Positioned(
                    top: 10, right: 12,
                    child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                  )
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        PlaceCard(
          title: "Village Park Nasi Lemak",
          rating: "4.8",
          imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDPsvHNtcy51fweRpx7Z38NNF934sNKNH_O_BzdWu0HVZWCkBZt6CBLL76Ybhs22w7l2my1T1qeg5fnkajXAwx0JITkEBN3pW_WPoxAQ0fg_zE4g97eh4udNmDuDwHZ7ElSJiNsWWwh2oPmS7RFqqGvusYCHK94NxGBlVsXj2pAXc2mL-gEfWYsTWihW73CNZVpcI-GyIqNRnZ8N_O0QA3xV4S6E5d9ZCOZLr9762lpiyaX4ncWArlM",
          categoryText: "Local Cuisine · Kuala Lumpur",
          categoryIcon: Icons.restaurant,
          categoryIconBg: const Color(0xFFFFF3E0),
          categoryIconColor: _accentColor,
          transitIcon: Icons.directions_car,
          transitTime: "15 min",
          duration: "1.5 hrs",
          isAdded: false,
          primaryColor: _primaryColor,
          accentColor: _accentColor,
          mutedText: _mutedText,
          onAddToggle: () {},
        ),
        const SizedBox(height: 16),
        PlaceCard(
          title: "Islamic Arts Museum",
          rating: "4.7",
          imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDEV-91Z7Vskxdr4h1xNRg-3OB1u30XOx096HGwTr7H3Ia5KlaMpEAfNTcBTT4-RnfoVQWvohZVVM14_sSJ3f6AHlRwFLmMqsIi7N5Gtohr0VOGJSIMJ3QQshVpQIc4sWH6R1oQ1PGyHX3UODPo2-VoNQWPRIqMCvVUOq4Du8UpE4107lMovJhVPzLKNO3Nb4sW_cX9hS4_wK7Kp_7xi8cVxdivG-d5ZY5DnCLAvROQBAlXW7VRl5pp",
          categoryText: "Art Museum · Kuala Lumpur",
          categoryIcon: Icons.camera_alt,
          categoryIconBg: const Color(0xFFE3F2FD),
          categoryIconColor: Colors.blue.shade800,
          transitIcon: Icons.directions_walk,
          transitTime: "8 min",
          duration: "2 hrs",
          isAdded: true,
          primaryColor: _primaryColor,
          accentColor: _accentColor,
          mutedText: _mutedText,
          onAddToggle: () {},
        ),
      ],
    );
  }
}