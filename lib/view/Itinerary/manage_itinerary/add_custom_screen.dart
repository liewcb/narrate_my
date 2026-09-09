import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_vm.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../model/business_logic/itinerary_service/custom_place_service.dart';
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
    // Itinerary module previously never watched LocaleVm — see
    // itinerary-localization-audit.md. This makes the screen respond to a
    // language change instead of staying stuck in English.
    context.watch<LocaleVm>();
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final vm = _viewModel;
        if (vm.isLoading) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: _buildAppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.t('itinerary.addCustom.loading'),
                    style: const TextStyle(color: AppColors.inkFaint),
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
                    else ...[
                      _buildRecommendationsSection(),
                      _buildRichBookmarksSection(),
                    ],

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
      title: Text(
        AppLocalizations.t('itinerary.addCustom.title'),
        style: const TextStyle(
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
    if (vm.searchError != null && vm.searchError!.trim().isNotEmpty) errors.add(vm.searchError!.trim());
    if (vm.planError != null && vm.planError!.trim().isNotEmpty) errors.add(vm.planError!.trim());
    if (vm.planResult != null && !vm.planResult!.success && (vm.planResult!.message?.trim().isNotEmpty ?? false)) {
      errors.add(vm.planResult!.message!.trim());
    }
    if (vm.loadError != null && vm.loadError!.trim().isNotEmpty) errors.add(vm.loadError!.trim());
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
          hintText: AppLocalizations.t('itinerary.addCustom.searchHint'),
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
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            AppLocalizations.t('itinerary.addCustom.searchNearby'),
            style: const TextStyle(
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
                  label: Text(AppLocalizations.t('itinerary.addCustom.nearPlace').replaceAll('{place}', placeName)),
                  onPressed: () {
                    final nearQuery =
                        AppLocalizations.t('itinerary.addCustom.nearPlace').replaceAll('{place}', placeName);
                    // 1. Update the search UI
                    _searchController.text = nearQuery;
                    // 2. Pass it to the ViewModel
                    _viewModel.query = nearQuery;
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(AppLocalizations.t('itinerary.manageEdit.searching'),
                  style: const TextStyle(color: AppColors.inkFaint)),
            ],
          ),
        ),
      );
    }
    if (vm.searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          AppLocalizations.t('itinerary.addCustom.noPlacesFound'),
          style: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            AppLocalizations.t('itinerary.addCustom.searchResults'),
            style: const TextStyle(
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
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            AppLocalizations.t('itinerary.addCustom.savedBookmarks'),
            style: const TextStyle(
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  AppLocalizations.t('itinerary.addCustom.noBookmarksYet'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.5),
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
    final photoUrl = (place.imageUrl != null && place.imageUrl!.trim().isNotEmpty)
        ? place.imageUrl!.trim()
        : (place.photoReference != null && place.photoReference!.trim().isNotEmpty
            ? 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=200&photoreference=${place.photoReference!.trim()}'
                '&key=${ApiKeys.googleMapsApiKey}'
            : null);
    final subtitle = place.placeCategory ??
        (place.types.isNotEmpty ? place.types.first : AppLocalizations.t('itinerary.common.place'));

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

    final photoUrl = (place.imageUrl != null && place.imageUrl!.trim().isNotEmpty)
        ? place.imageUrl!.trim()
        : (place.photoReference != null && place.photoReference!.trim().isNotEmpty
            ? 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=400&photoreference=${place.photoReference!.trim()}'
                '&key=${ApiKeys.googleMapsApiKey}'
            : null);
    final primaryType = place.placeCategory ??
        (place.types.isNotEmpty ? place.types.first : AppLocalizations.t('itinerary.manageEdit.attractionFallback'));
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
            Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.t('itinerary.addCustom.checkingTravelTime'),
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
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

    final hasUnscheduled = plan.proposedDay?.reason.contains('unscheduled') == true ||
        stops.any((s) => s.startTime.hour == 0 && s.startTime.minute == 0 && s.endTime.hour == 0 && s.endTime.minute == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.success) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: hasUnscheduled
                  ? const Color(0xFFFFF3E0)
                  : AppColors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasUnscheduled
                    ? const Color(0xFFFFB74D)
                    : AppColors.green.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasUnscheduled ? Icons.info_outline_rounded : Icons.check_circle,
                  size: 18,
                  color: hasUnscheduled ? const Color(0xFFE65100) : AppColors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasUnscheduled
                        ? AppLocalizations.t('itinerary.addCustom.placeAddedUnscheduled')
                        : AppLocalizations.t('itinerary.addCustom.placeCanBeAdded'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasUnscheduled ? const Color(0xFFD84315) : AppColors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            AppLocalizations.t('itinerary.addCustom.proposedSchedule'),
            style: const TextStyle(
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
              final isUnscheduled = stop.startTime.hour == 0 &&
                  stop.startTime.minute == 0 &&
                  stop.endTime.hour == 0 &&
                  stop.endTime.minute == 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (travel > 0 && !isUnscheduled)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, size: 12,
                                color: AppColors.inkFaint),
                            const SizedBox(width: 4),
                            Text(
                              AppLocalizations.t('itinerary.addCustom.minTravel').replaceAll('{n}', '$travel'),
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
                            isUnscheduled ? '--:--' : timeFormat.format(stop.startTime),
                            textAlign: TextAlign.center,
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
                            child: Text(
                              AppLocalizations.t('itinerary.addCustom.newBadge'),
                              style: const TextStyle(
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
    final canAdd = vm.selectedPlace != null && !vm.isPlanning;

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
                    child: Text(
                      AppLocalizations.t('ui.cancel'),
                      style: const TextStyle(
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
                      backgroundColor: canAdd && !vm.isSaving ? AppColors.green : AppColors.surface2,
                      foregroundColor: canAdd && !vm.isSaving ? Colors.white : AppColors.inkFaint,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: canAdd && !vm.isSaving ? () => _onAdd() : null,
                    child: Text(
                      vm.isSaving
                          ? AppLocalizations.t('itinerary.addCustom.saving')
                          : (vm.isPlanning
                              ? AppLocalizations.t('itinerary.addCustom.planning')
                              : AppLocalizations.t('itinerary.addCustom.addToItinerary')),
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

  /// Confirm → if preview mode, returns proposed day to host;
  /// if saved itinerary mode, persists to database and returns true.
  Future<void> _onAdd() async {
    final vm = _viewModel;
    if (vm.isPlanning || vm.isSaving) return;

    final proposedDay = vm.confirmedProposedDay();
    if (proposedDay == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              vm.planError ??
                  vm.planResult?.message ??
                  AppLocalizations.t('itinerary.addCustom.planFailed'),
            ),
          ),
        );
      return;
    }

    final isPreview = widget.dayStops != null;
    final placeName = vm.selectedPlace?.placeName ?? AppLocalizations.t('itinerary.addCustom.thisPlaceFallback');

    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.t('itinerary.addCustom.addPlaceTitle'),
      message: isPreview
          ? AppLocalizations.t('itinerary.addCustom.addPlacePreviewMessage')
              .replaceAll('{place}', placeName)
              .replaceAll('{n}', '${vm.dayIndex}')
          : AppLocalizations.t('itinerary.addCustom.addPlaceMessage')
              .replaceAll('{place}', placeName)
              .replaceAll('{n}', '${vm.dayIndex}'),
      confirmLabel: AppLocalizations.t('itinerary.addCustom.confirm'),
      cancelLabel: AppLocalizations.t('ui.cancel'),
      confirmColor: AppColors.primary,
      icon: Icons.add_location_alt_outlined,
      iconBgColor: AppColors.primary.withOpacity(0.12),
      iconColor: AppColors.primary,
    );
    if (confirmed != true || !mounted) return;

    if (isPreview) {
      Navigator.pop(context, (dayIndex: vm.dayIndex, day: proposedDay));
    } else {
      final success = await vm.confirmAndSave();
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.t('itinerary.addCustom.addedToDay')
                    .replaceAll('{place}', placeName)
                    .replaceAll('{n}', '${vm.dayIndex}'),
              ),
              backgroundColor: AppColors.primary,
            ),
          );
        Navigator.pop(context, true);
      } else {
        await showConfirmationDialog(
          context: context,
          title: AppLocalizations.t('itinerary.addCustom.cannotAddPlaceTitle'),
          message: vm.planError ?? AppLocalizations.t('itinerary.addCustom.failedToAddPlace'),
          confirmLabel: AppLocalizations.t('itinerary.addCustom.ok'),
          cancelLabel: '',
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.error,
          iconBgColor: AppColors.error.withOpacity(0.12),
        );
      }
    }
  }

  Widget _buildRecommendationsSection() {
    final vm = _viewModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            AppLocalizations.t('itinerary.addCustom.recommendedForDay'),
            style: const TextStyle(
              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: AppColors.inkFaint,
            ),
          ),
        ),
        if (vm.isLoadingRecommendations) // Assuming you add this to VM
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.t('itinerary.addCustom.analyzingSchedule'),
                      style: const TextStyle(color: AppColors.inkFaint)),
                ],
              ),
            ),
          )
        else if (vm.recommendationsError != null) // Assuming you add this to VM
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              vm.recommendationsError!,
              style: const TextStyle(
                fontSize: 14, color: AppColors.inkFaint, fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (vm.recommendations.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                AppLocalizations.t('itinerary.addCustom.noRecommendations'),
                style: const TextStyle(fontSize: 14, color: AppColors.inkFaint),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: vm.recommendations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final place = vm.recommendations[index]; // Extract Place from recommendation
                  // ✅ Reuse your beautiful rich card design!
                  return _buildRichPlaceCard(place);
                },
              ),
            ),
      ],
    );
  }
}