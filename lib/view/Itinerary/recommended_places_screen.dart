// lib/view/Itinerary/recommended_places_screen.dart
//
// "Recommended Places" — a day-scoped add-place flow.
//
// Shows deterministic Attractions / Restaurants recommendations for the
// currently selected day. The traveler picks ONE place; a single compact
// DeepSeek request (3s hard timeout, deterministic fallback) decides the best
// insertion position + visit duration, Dart builds the exact schedule and
// hard-validates it. On success the validated proposed day is returned to the
// host editor's working state — nothing is persisted here and no other day is
// touched.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config/api_keys.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/place.dart';
import '../../viewmodel/Itinerary/recommended_places_vm.dart';

/// Result returned to the editor when a place is successfully planned.
typedef RecommendedPlaceResult = ({ScheduledDay day, String addedPlaceName});

class RecommendedPlacesScreen extends StatefulWidget {
  final int dayNumber; // 1-based
  final DateTime dayDate;
  final List<ExistingStopContext> existingStops;
  final Set<String> usedPlaceIds;
  final List<String> interests;
  final String transportMode;
  final String explorationTime;
  final String travelPace;
  final Coordinates? destinationCenter;

  const RecommendedPlacesScreen({
    super.key,
    required this.dayNumber,
    required this.dayDate,
    required this.existingStops,
    required this.usedPlaceIds,
    required this.interests,
    required this.transportMode,
    required this.explorationTime,
    required this.travelPace,
    this.destinationCenter,
  });

  @override
  State<RecommendedPlacesScreen> createState() => _RecommendedPlacesScreenState();
}

class _RecommendedPlacesScreenState extends State<RecommendedPlacesScreen>
    with SingleTickerProviderStateMixin {
  late final RecommendedPlacesVM _vm;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _vm = RecommendedPlacesVM(
      dayNumber: widget.dayNumber,
      dayDate: widget.dayDate,
      existingStops: widget.existingStops,
      usedPlaceIds: widget.usedPlaceIds,
      interests: widget.interests,
      transportMode: widget.transportMode,
      explorationTime: widget.explorationTime,
      travelPace: widget.travelPace,
      destinationCenter: widget.destinationCenter,
    );
    _vm.loadRecommendations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _onSelect(Place place) async {
    await _vm.selectAndPlan(place);
    if (!mounted) return;

    final day = _vm.confirmedProposedDay();
    if (day != null) {
      Navigator.pop(context, (day: day, addedPlaceName: place.placeName));
      return;
    }
    // Could not fit — keep the previous day state, let the user try another.
    _vm.clearSelection();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _vm.planError ?? 'This place cannot fit into Day ${widget.dayNumber}.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.warmBg,
          appBar: AppBar(
            backgroundColor: AppColors.warmBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Places',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
                Text(
                  'Recommended for Day ${widget.dayNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedText,
                  ),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.terracottaDark,
              unselectedLabelColor: AppColors.mutedText,
              indicatorColor: AppColors.terracottaDark,
              dividerColor: AppColors.outlineLight,
              tabs: const [
                Tab(text: 'Attractions'),
                Tab(text: 'Restaurants'),
              ],
            ),
          ),
          body: Stack(
            children: [
              TabBarView(
                controller: _tabController,
                children: [
                  _buildCategoryList(RecommendationCategory.attractions),
                  _buildCategoryList(RecommendationCategory.restaurants),
                ],
              ),
              if (_vm.isPlanning) _buildPlanningOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryList(RecommendationCategory category) {
    if (_vm.isLoadingRecommendations) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.terracottaDark),
            SizedBox(height: 16),
            Text(
              'Finding recommendations for your day...',
              style: TextStyle(color: AppColors.mutedText, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_vm.recommendationsError != null &&
        _vm.forCategory(category).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _vm.recommendationsError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedText, fontSize: 14),
          ),
        ),
      );
    }

    final items = _vm.forCategory(category);
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No recommendations available for this day.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mutedText, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildPlaceCard(items[index]),
    );
  }

  Widget _buildPlaceCard(NearbyPlaceResult candidate) {
    final place = candidate.place;
    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
            '?maxwidth=400&photoreference=${place.photoReference}'
            '&key=${ApiKeys.googleMapsApiKey}'
        : null;
    final categoryLabel = place.placeCategory ??
        (place.types.isNotEmpty ? place.types.first : 'Attraction');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              color: AppColors.surfaceInactive,
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.place,
                        color: AppColors.mutedText,
                      ),
                    )
                  : const Icon(Icons.place, color: AppColors.mutedText),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _capitalize(categoryLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _reasonFor(candidate),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.warmBrown,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _vm.isPlanning ? null : () => _onSelect(place),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.terracottaDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Select',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanningOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.warmBg.withOpacity(0.85),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.terracottaDark),
              SizedBox(height: 16),
              Text(
                'Finding the best time for your day...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Short, human "why recommended" line built from ranking metadata only.
  String _reasonFor(NearbyPlaceResult r) {
    final parts = <String>[];
    final place = r.place;
    if (place.rating > 0) {
      parts.add('Rated ${place.rating.toStringAsFixed(1)}');
    }
    final km = r.distanceFromPreviousKm;
    if (km != null) {
      parts.add('${km.toStringAsFixed(1)} km from your route');
    } else if (r.estimatedAdditionalTravelMinutes > 0) {
      parts.add('~${r.estimatedAdditionalTravelMinutes.round()} min detour');
    }
    if (parts.isEmpty) parts.add('Recommended for your day');
    return parts.join(' · ');
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
  }
}
