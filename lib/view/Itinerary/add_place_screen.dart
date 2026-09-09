import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../viewmodel/Itinerary/add_place_vm.dart';

class AddPlaceScreen extends StatefulWidget {
  final String itineraryId;
  final int dayIndex; // 0-based
  final String explorationTime;

  // ─── Preview working state (optional) ───────────────────────
  // When [workingDay] is supplied the screen runs the in-memory AI
  // insertion + validation flow and returns the updated day WITHOUT
  // touching the database. When omitted, the legacy saved-itinerary
  // behaviour is preserved.
  final ScheduledDay? workingDay;
  final Set<String> itineraryUsedPlaceIds;
  final DateTime? dayDate;
  final String transportMode;
  final String travelPace;
  final List<String> interests;
  final List<String> mustVisitPlaceIds;
  final Coordinates? destinationCenter;

  const AddPlaceScreen({
    Key? key,
    required this.itineraryId,
    required this.dayIndex,
    this.explorationTime = 'Standard',
    this.workingDay,
    this.itineraryUsedPlaceIds = const {},
    this.dayDate,
    this.transportMode = 'walking',
    this.travelPace = 'Standard',
    this.interests = const [],
    this.mustVisitPlaceIds = const [],
    this.destinationCenter,
  }) : super(key: key);

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddPlaceVM>(
      create: (_) => AddPlaceVM(
        itineraryId: widget.itineraryId,
        dayIndex: widget.dayIndex,
        explorationTime: widget.explorationTime,
        workingDay: widget.workingDay,
        itineraryUsedPlaceIds: widget.itineraryUsedPlaceIds,
        dayDate: widget.dayDate,
        transportMode: widget.transportMode,
        travelPace: widget.travelPace,
        interests: widget.interests,
        mustVisitPlaceIds: widget.mustVisitPlaceIds,
        destinationCenter: widget.destinationCenter,
      )..load(),
      child: const _AddPlaceBody(),
    );
  }
}

class _AddPlaceBody extends StatefulWidget {
  const _AddPlaceBody();

  @override
  State<_AddPlaceBody> createState() => _AddPlaceBodyState();
}

class _AddPlaceBodyState extends State<_AddPlaceBody> {
  late final TextEditingController _searchController;

  // Brand Colors
  static const _bg = AppColors.creamBg;
  static const _charcoal = AppColors.charcoal;
  static const _mutedText = AppColors.mutedText;
  static const _pineGreen = AppColors.pineGreen;
  static const _terracotta = AppColors.terracotta;
  static const _surfaceCard = AppColors.white;
  static const _surfaceInactive = AppColors.surfaceInactive;

  static const List<String> _categories = [
    'All',
    'Landmarks',
    'Culture',
    'Food & Nightlife',
    'Shopping',
    'Nature',
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: vm.isLoadingStops || (vm.isLoadingCandidates && vm.candidates.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContextCards(vm),
                  const SizedBox(height: 20),
                  _buildSearchBar(vm),
                  const SizedBox(height: 16),
                  _buildCategoryChips(vm),
                  const SizedBox(height: 24),
                  _buildRecommendedList(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _bg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: _buildAddButton(context),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _bg.withOpacity(0.95),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: _charcoal),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Column(
        children: [
          const Text(
            "Add a Place",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _charcoal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Day ${context.read<AddPlaceVM>().dayIndex + 1}",
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _mutedText,
            ),
          ),
        ],
      ),
      actions: const [SizedBox(width: 48)],
    );
  }

  Widget _buildContextCards(AddPlaceVM vm) {
    final freeMinutes = vm.availableMinutes;
    final hours = freeMinutes ~/ 60;
    final mins = freeMinutes % 60;
    final freeText = hours > 0
        ? '$hours hr${mins > 0 ? ' $mins min' : ''}'
        : '$mins min';

    return Container(
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _pineGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.schedule_rounded, color: _pineGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TIME AVAILABLE",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _mutedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$freeText free',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: freeMinutes > 0 ? _charcoal : _terracotta,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${vm.existingStops.length} stop(s) scheduled on Day ${vm.dayIndex + 1}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: _mutedText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AddPlaceVM vm) {
    return Container(
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
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {});
          vm.search(val);
        },
        decoration: InputDecoration(
          hintText: "Search places, landmarks, food...",
          hintStyle: const TextStyle(color: _mutedText, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: _mutedText, size: 22),
          suffixIcon: vm.isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _pineGreen),
                  ),
                )
              : _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: _mutedText, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        vm.search('');
                      },
                    )
                  : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(AddPlaceVM vm) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _categories.map((category) {
          final isSelected = vm.selectedCategoryFilter == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                category,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : _charcoal,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => vm.setCategoryFilter(category),
              backgroundColor: _surfaceCard,
              selectedColor: _pineGreen,
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? _pineGreen : Colors.grey.withOpacity(0.2),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecommendedList(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();
    final isSearching = vm.searchQuery.trim().isNotEmpty;
    final title = isSearching
        ? "SEARCH RESULTS (${vm.candidates.length})"
        : "RECOMMENDED PLACES (${vm.candidates.length})";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: _mutedText,
              ),
            ),
            if (isSearching)
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                  vm.search('');
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _terracotta,
                ),
                child: const Text('Clear search', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (vm.candidates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: _surfaceCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  isSearching ? Icons.search_off_rounded : Icons.place_outlined,
                  size: 44,
                  color: _mutedText.withOpacity(0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  isSearching
                      ? 'No places found matching "${vm.searchQuery}"'
                      : (vm.candidatesError ?? 'No places available for this filter.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _charcoal,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Try searching for another attraction or switch category.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _mutedText),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: vm.candidates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final option = vm.candidates[index];
              return _buildPlaceCard(context, option);
            },
          ),
      ],
    );
  }

  Widget _buildPlaceCard(BuildContext context, AddPlaceOption option) {
    final vm = context.watch<AddPlaceVM>();
    final isSelected = vm.isSelected(option.placeId);
    final hours = option.durationMinutes ~/ 60;
    final mins = option.durationMinutes % 60;
    final durText = hours > 0
        ? '$hours hr${mins > 0 ? ' $mins min' : ''}'
        : '$mins min';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _pineGreen : Colors.transparent,
          width: 1.5,
        ),
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
          // Photo Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 90,
              height: 90,
              child: option.imageUrl != null && option.imageUrl!.isNotEmpty
                  ? Image.network(
                      option.imageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: _surfaceInactive,
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: _surfaceInactive,
                        child: const Icon(Icons.photo_outlined, color: _mutedText),
                      ),
                    )
                  : Container(
                      color: _surfaceInactive,
                      child: const Icon(Icons.place, color: _mutedText),
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  option.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _charcoal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Rating & Category row
                Row(
                  children: [
                    if (option.rating > 0) ...[
                      const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text(
                        option.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _charcoal,
                        ),
                      ),
                      if (option.userRatingsTotal != null && option.userRatingsTotal! > 0) ...[
                        const SizedBox(width: 2),
                        Text(
                          ' (${_formatReviews(option.userRatingsTotal)})',
                          style: const TextStyle(fontSize: 11, color: _mutedText),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: _mutedText,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        option.category,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _pineGreen,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                if (option.address != null && option.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 13, color: _mutedText),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          option.address!,
                          style: const TextStyle(fontSize: 11, color: _mutedText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),

                // Bottom Row (Duration + Add Button)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hourglass_empty_rounded, size: 14, color: _terracotta),
                        const SizedBox(width: 4),
                        Text(
                          durText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _terracotta,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? _pineGreen : _terracotta,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () => vm.toggleSelection(option.placeId),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isSelected ? "Selected" : "Add",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatReviews(int? count) {
    if (count == null || count == 0) return '';
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  Future<void> _confirmAndAddPlace(BuildContext context, AddPlaceVM vm) async {
    AddPlaceOption? selectedOption;
    for (final c in vm.candidates) {
      if (vm.selectedPlaceIds.contains(c.placeId)) {
        selectedOption = c;
        break;
      }
    }
    if (selectedOption == null) return;

    final existingStops = vm.workingDay?.stops ?? [];
    String? prevStopName;
    double? distanceKm;
    int? travelMinutes;

    if (existingStops.isNotEmpty) {
      final prev = existingStops.last;
      prevStopName = prev.attraction.place.placeName;
      final prevCoords = prev.attraction.place.coordinates;
      final targetCoords = selectedOption.place.coordinates;
      if (prevCoords.latitude != 0 && targetCoords.latitude != 0) {
        distanceKm = prevCoords.distanceTo(targetCoords);
        travelMinutes = ((distanceKm / 35.0) * 60).round().clamp(5, 120);
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _pineGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_location_alt_rounded, color: _pineGreen, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Confirm Adding Place',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: _charcoal,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedOption!.name,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _charcoal,
              ),
            ),
            if (selectedOption.address != null && selectedOption.address!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                selectedOption.address!,
                style: const TextStyle(fontSize: 12, color: _mutedText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  if (distanceKm != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.straighten_rounded, size: 16, color: _pineGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Distance: ~${distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _charcoal),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.directions_car_rounded, size: 16, color: _terracotta),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Est. Travel Time: ~${travelMinutes} mins drive',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _charcoal),
                          ),
                        ),
                      ],
                    ),
                    if (prevStopName != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24.0),
                        child: Text(
                          'from previous stop "$prevStopName"',
                          style: const TextStyle(fontSize: 11, color: _mutedText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: _pineGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Visit Duration: ~${selectedOption.durationMinutes} mins',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _charcoal),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You have full control to reorder, reschedule, or adjust times in the itinerary editor.',
              style: TextStyle(fontSize: 12, color: _mutedText, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: _mutedText, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _pineGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirm & Add', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await vm.addPlaces();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Place added to Day ${vm.dayIndex + 1}.'
                : (result.message ?? 'Could not add place.'),
          ),
        ),
      );
    if (result.success) {
      Navigator.pop(context, result.proposedDay);
    }
  }

  Widget _buildAddButton(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();
    final canAdd = vm.selectedPlaceIds.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canAdd && !vm.isSaving
            ? () => _confirmAndAddPlace(context, vm)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canAdd ? _pineGreen : _surfaceInactive,
          foregroundColor: canAdd ? Colors.white : _mutedText,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        icon: vm.isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_rounded, size: 20),
        label: Text(
          vm.isSaving
              ? (vm.isPreviewMode
                  ? 'Fitting into your day...'
                  : 'Adding...')
              : vm.isPreviewMode
                  ? 'Add place to Day ${vm.dayIndex + 1}'
                  : 'Add ${vm.selectedPlaceIds.length} place(s) to Itinerary',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
