import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/add_custom_place_vm.dart';

class AddCustomStopScreen extends StatefulWidget {
  final String itineraryId;
  final int dayIndex; // 1-based
  final DateTime dayDate;
  final List<int> availableDayIndices;
  final String explorationTime;
  final String travelPace;
  final String transportMode;
  final List<String> interests;
  final String userId;

  /// Preview mode: when provided, the day context comes from the caller's
  /// TEMPORARY itinerary state (no database read for this day) and the
  /// returned proposed day is applied by the host — never persisted here.
  final List<ExistingStopContext>? dayStops;

  const AddCustomStopScreen({
    Key? key,
    required this.itineraryId,
    required this.dayIndex,
    required this.dayDate,
    this.availableDayIndices = const [],
    this.explorationTime = 'Standard',
    this.travelPace = 'Standard',
    this.transportMode = 'walking',
    this.interests = const [],
    this.userId = '',
    this.dayStops,
  }) : super(key: key);

  @override
  State<AddCustomStopScreen> createState() => _AddCustomStopScreenState();
}

class _AddCustomStopScreenState extends State<AddCustomStopScreen> {
  late AddCustomPlaceVM _viewModel;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint('[ADD_CUSTOM] Screen opened — day ${widget.dayIndex}');
    _viewModel = AddCustomPlaceVM(
      itineraryId: widget.itineraryId,
      dayIndex: widget.dayIndex,
      dayDate: widget.dayDate,
      explorationTime: widget.explorationTime,
      travelPace: widget.travelPace,
      transportMode: widget.transportMode,
      interests: widget.interests,
      userId: widget.userId,
    );
    // Preview mode: seed the temporary day context BEFORE loading so no
    // database query is made for this day.
    if (widget.dayStops != null) {
      _viewModel.seedDayContext(widget.dayIndex, widget.dayStops!);
    }
    _viewModel.load();
    _viewModel.loadBookmarks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final vm = _viewModel;
        if (vm.isLoading) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: _buildAppBar(),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading itinerary...',
                    style: TextStyle(color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: _buildAppBar(),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 24, bottom: 140,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWarningBanner(),
                    if (vm.searchError != null || vm.planError != null || vm.loadError != null)
                      const SizedBox(height: 24),

                    _buildSearchBar(),
                    const SizedBox(height: 24),

                    _buildNearbySuggestions(),
                    if (widget.dayStops != null && widget.dayStops!.isNotEmpty)
                      const SizedBox(height: 24),

                    // Unified List Area: Show Search Results OR Bookmarks
                    if (vm.hasSearched)
                      _buildSearchResults()
                    else
                      _buildRichBookmarksSection(),

                    const SizedBox(height: 24),

                    // Scheduling Details Area
                    if (vm.selectedPlace != null) ...[
                      const Divider(color: AppColors.moduleBorder, height: 32, thickness: 1),
                      _buildPlaceDetails(),
                      const SizedBox(height: 24),
                      if (vm.hasPlan) _buildSchedule(),
                      const SizedBox(height: 24),
                    ]
                  ],
                ),
              ),
              _buildStickyFooter(),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg.withOpacity(0.9),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: IconButton(
          icon: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surface2, shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      title: const Text(
        "Add a Place",
        style: TextStyle(
          fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600,
          color: AppColors.ink, letterSpacing: -0.5,
        ),
      ),
      actions: const [SizedBox(width: 52)],
    );
  }

  Widget _buildWarningBanner() {
    final vm = _viewModel;
    final errors = <String>[];
    if (vm.searchError != null) errors.add(vm.searchError!);
    if (vm.planError != null) errors.add(vm.planError!);
    if (vm.planResult != null && !vm.planResult!.success) {
      errors.add(vm.planResult!.message ??
          "We couldn't plan this place right now. Please try again.");
    }
    if (vm.loadError != null) errors.add(vm.loadError!);
    if (errors.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errors.first,
              style: const TextStyle(
                fontFamily: 'Inter', fontSize: 14,
                color: AppColors.error, height: 1.4,
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          _viewModel.query = value;
          _viewModel.searchPlaces();
        },
        decoration: InputDecoration(
          hintText: "Search for a place...",
          hintStyle: const TextStyle(color: AppColors.inkFaint),
          prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () {
              _searchController.clear();
              _viewModel.query = '';
              setState(() {});
            },
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildNearbySuggestions() {
    // If the day is completely empty, there is no "nearby" context to suggest
    if (widget.dayStops == null || widget.dayStops!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            "SEARCH NEARBY TODAY'S STOPS",
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: AppColors.inkFaint,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: widget.dayStops!.map((stop) {
              final placeName = stop.place.placeName;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.moduleBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  labelStyle: const TextStyle(
                    fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w500,
                  ),
                  avatar: const Icon(Icons.near_me_outlined, size: 14, color: AppColors.green),
                  label: Text('Near $placeName'),
                  onPressed: () {
                    // 1. Update the search UI
                    _searchController.text = 'Near $placeName';
                    // 2. Pass it to the ViewModel
                    _viewModel.query = 'Near $placeName';
                    // 3. Trigger the search immediately
                    _viewModel.searchPlaces();
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final vm = _viewModel;
    if (vm.isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Searching...',
                  style: TextStyle(color: AppColors.inkFaint)),
            ],
          ),
        ),
      );
    }
    if (vm.searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No places found. Try a different search.',
          style: TextStyle(color: AppColors.inkFaint, fontSize: 14),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            "SEARCH RESULTS",
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: AppColors.inkFaint,
            ),
          ),
        ),
        ...vm.searchResults.map((place) => _buildRichPlaceCard(place)),
      ],
    );
  }

  Widget _buildRichBookmarksSection() {
    final vm = _viewModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            "SAVED BOOKMARKS",
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: AppColors.inkFaint,
            ),
          ),
        ),
        if (vm.isLoadingBookmarks)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (vm.bookmarksError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              vm.bookmarksError!,
              style: const TextStyle(
                fontSize: 14, color: AppColors.inkFaint, fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (vm.bookmarks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No bookmarks yet.\nSearch above to find places to visit!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.5),
                ),
              ),
            )
          else
            ...vm.bookmarks.map((place) => _buildRichPlaceCard(place)),
      ],
    );
  }

  // Unified Card Design for both Search Results and Bookmarks
  Widget _buildRichPlaceCard(Place place) {
    final isSelected = _viewModel.selectedPlaceId == place.placeId;
    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=200&photoreference=${place.photoReference}'
        '&key=${ApiKeys.googleMapsApiKey}'
        : null;
    final subtitle = place.placeCategory ?? (place.types.isNotEmpty ? place.types.first : 'Place');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.moduleBorder.withOpacity(0.6),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => _viewModel.selectPlace(place.placeId),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64, height: 64,
                  color: AppColors.moduleBorder,
                  child: photoUrl != null
                      ? Image.network(photoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 24, color: AppColors.inkFaint),
                  )
                      : const Icon(Icons.place, size: 24, color: AppColors.inkFaint),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.placeName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink,
                        )),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.inkFaint)),
                    if (place.rating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(place.rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check_circle, color: AppColors.green, size: 24),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceDetails() {
    final vm = _viewModel;
    final place = vm.selectedPlace;
    if (place == null) return const SizedBox.shrink();

    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=${place.photoReference}'
        '&key=${ApiKeys.googleMapsApiKey}'
        : null;
    final primaryType = place.placeCategory ?? (place.types.isNotEmpty ? place.types.first : 'Attraction');
    final prox = vm.proximity;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 72, height: 72,
                  color: AppColors.surface2,
                  child: photoUrl != null
                      ? Image.network(photoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.place, color: AppColors.inkFaint),
                  )
                      : const Icon(Icons.place, color: AppColors.inkFaint),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        primaryType.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 10,
                          fontWeight: FontWeight.bold, letterSpacing: 1.0,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place.placeName,
                      style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 16,
                        fontWeight: FontWeight.bold, color: AppColors.ink,
                        height: 1.2,
                      ),
                    ),
                    if (place.placeAddress.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: AppColors.inkFaint),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              place.placeAddress,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.inkFaint),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (place.rating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: AppColors.gold),
                          const SizedBox(width: 4),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (prox != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.near_me, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${prox.proximity} '
                        '(${prox.distanceFromItineraryKm.toStringAsFixed(1)} km, '
                        '~${prox.travelMinutes} min)',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
          if (vm.isPlanning) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Checking travel time and schedule...',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSchedule() {
    final plan = _viewModel.planResult;
    if (plan == null || plan.proposedDay == null) return const SizedBox.shrink();

    final stops = plan.proposedDay!.stops;
    if (stops.isEmpty) return const SizedBox.shrink();

    final newPlaceId = _viewModel.selectedPlaceId;
    final timeFormat = DateFormat('HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.success)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.green.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: AppColors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Place can be added to your itinerary.',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "PROPOSED SCHEDULE",
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: AppColors.inkFaint,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04), blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: stops.map((stop) {
              final isNew = stop.attraction.place.placeId == newPlaceId;
              final travel = stop.travelFromPreviousMinutes;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (travel > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, size: 12,
                                color: AppColors.inkFaint),
                            const SizedBox(width: 4),
                            Text(
                              '$travel min travel',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.inkFaint),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isNew ? AppColors.accentSoft : AppColors.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            timeFormat.format(stop.startTime),
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: isNew ? AppColors.accent : AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stop.attraction.place.placeName,
                                style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: isNew ? AppColors.accent : AppColors.ink,
                                ),
                              ),
                              Text(
                                '${timeFormat.format(stop.startTime)} – '
                                    '${timeFormat.format(stop.endTime)} '
                                    '(${stop.durationMinutes} min)',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.inkFaint),
                              ),
                            ],
                          ),
                        ),
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyFooter() {
    final vm = _viewModel;
    final canAdd = vm.hasPlan && vm.planResult!.success && !vm.isPlanning;

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: AppColors.bg.withOpacity(0.8),
              border: Border(
                top: BorderSide(color: AppColors.surface2.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.ink,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: const BorderSide(color: AppColors.moduleBorder),
                      ),
                    ),
                    onPressed: () => Navigator.maybePop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAdd ? AppColors.green : AppColors.surface2,
                      foregroundColor: canAdd ? Colors.white : AppColors.inkFaint,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: canAdd ? () => _onAdd(context) : null,
                    child: Text(
                      vm.isPlanning ? 'Planning...' : 'Add to Itinerary',
                      style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 16,
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

  /// Confirm → return the validated proposed day to the caller. The
  /// temporary itinerary is updated by the HOST (EditItinerary state) —
  /// nothing is persisted here. The final Save process persists later.
  Future<void> _onAdd(BuildContext context) async {
    final vm = _viewModel;
    if (vm.isPlanning) return; // no action while planning runs

    final proposedDay = vm.confirmedProposedDay();
    if (proposedDay == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              vm.planError ??
                  vm.planResult?.message ??
                  "We couldn't plan this place right now. Please try again.",
            ),
          ),
        );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add this place?'),
        content: Text(
          '${vm.selectedPlace?.placeName ?? 'This place'} will be added to '
              'Day ${vm.dayIndex} of your itinerary preview. '
              'Changes become permanent only when you save.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Return the validated proposed day — NO database write here.
    Navigator.pop(context, (dayIndex: vm.dayIndex, day: proposedDay));
  }
}