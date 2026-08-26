// lib/view/Itinerary/manage_itinerary/add_custom_place_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/ItineraryModel/add_custom_place_vm.dart';

/// UI for the "Add Location" workflow (Manage Itinerary).
///
/// Flow: search Google Places by text → select a result → view place info,
/// distance (Near/Moderate/Far) and travel time → AI plans + validates →
/// confirmation popup → confirm/cancel.
class AddCustomPlaceScreen extends StatefulWidget {
  final String itineraryId;
  final int dayIndex; // 1-based
  final DateTime dayDate;
  final String explorationTime;
  final String travelPace;
  final String transportMode;
  final List<String> interests;

  const AddCustomPlaceScreen({
    Key? key,
    required this.itineraryId,
    required this.dayIndex,
    required this.dayDate,
    this.explorationTime = 'Standard',
    this.travelPace = 'Standard',
    this.transportMode = 'walking',
    this.interests = const [],
  }) : super(key: key);

  @override
  State<AddCustomPlaceScreen> createState() => _AddCustomPlaceScreenState();
}

class _AddCustomPlaceScreenState extends State<AddCustomPlaceScreen> {
  late AddCustomPlaceVM _vm;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = AddCustomPlaceVM(
      itineraryId: widget.itineraryId,
      dayIndex: widget.dayIndex,
      dayDate: widget.dayDate,
      explorationTime: widget.explorationTime,
      travelPace: widget.travelPace,
      transportMode: widget.transportMode,
      interests: widget.interests,
    )..load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _vm.saved),
        ),
        title: Text(
          'Add Location • Day ${widget.dayIndex}',
          style: AppTextStyles.pageTitle,
        ),
      ),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          if (_vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDayStopsSection(),
                const SizedBox(height: 24),
                _buildSearchSection(),
                if (_vm.hasSearched) ...[
                  const SizedBox(height: 24),
                  _buildResultsSection(),
                ],
                if (_vm.selectedPlace != null) ...[
                  const SizedBox(height: 24),
                  _buildSelectedPlaceSection(),
                ],
                if (_vm.hasPlan) ...[
                  const SizedBox(height: 24),
                  _buildPlanPreviewSection(),
                ],
                if (_vm.planResult != null && !_vm.planResult!.success) ...[
                  const SizedBox(height: 24),
                  _buildPlanErrorBanner(),
                ],
                if (_vm.saveError != null) ...[
                  const SizedBox(height: 24),
                  _buildSaveErrorBanner(),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _vm.hasPlan && _vm.planResult?.success == true
          ? _buildConfirmBar()
          : null,
    );
  }

  // ─── Day stops ──────────────────────────────────────────────

  Widget _buildDayStopsSection() {
    final stops = _vm.dayStops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CURRENT DAY STOPS', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (stops.isEmpty)
          Text('This day has no stops yet.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted))
        else
          ...stops.map((stop) => _buildDayStopRow(stop)),
      ],
    );
  }

  Widget _buildDayStopRow(ItineraryStop stop) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            '${DateFormat('HH:mm').format(stop.startTime)} – '
            '${DateFormat('HH:mm').format(stop.endTime)}',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              stop.place?.name ?? stop.placeId,
              style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Search ─────────────────────────────────────────────────

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SEARCH GOOGLE PLACES', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _vm.searchPlaces(),
                onChanged: (v) => _vm.query = v,
                decoration: InputDecoration(
                  hintText: 'e.g. Petaling Street, National Mosque…',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: AppColors.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _vm.isSearching ? null : _vm.searchPlaces,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryTerracotta,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              child: Text(_vm.isSearching ? '…' : 'Search'),
            ),
          ],
        ),
        if (_vm.searchError != null) ...[
          const SizedBox(height: 12),
          Text(
            'Search failed: ${_vm.searchError}',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  // ─── Results ────────────────────────────────────────────────

  Widget _buildResultsSection() {
    final results = _vm.searchResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SEARCH RESULTS', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (results.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              'No places found for that query.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
            ),
          )
        else
          ...results.map((place) {
            final selected = _vm.selectedPlaceId == place.placeId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildResultTile(place, selected),
            );
          }),
      ],
    );
  }

  Widget _buildResultTile(Place place, bool selected) {
    return GestureDetector(
      onTap: () => _vm.selectPlace(place.placeId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTerracotta.withOpacity(0.08) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primaryTerracotta : AppColors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (place.address.isNotEmpty)
                    Text(
                      place.address,
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (place.rating > 0) ...[
                        const Icon(Icons.star, size: 14, color: AppColors.primaryContainer),
                        const SizedBox(width: 4),
                        Text('${place.rating.toStringAsFixed(1)}',
                            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.primaryTerracotta),
          ],
        ),
      ),
    );
  }

  // ─── Selected place info + distance + travel ────────────────

  Widget _buildSelectedPlaceSection() {
    final place = _vm.selectedPlace!;
    final proximity = _vm.proximity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELECTED LOCATION', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(place.name,
                  style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600)),
              if (place.address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place.address,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              if (proximity != null) ...[
                Row(
                  children: [
                    Icon(_proximityIcon(proximity.proximity),
                        size: 16, color: _proximityColor(proximity.proximity)),
                    const SizedBox(width: 6),
                    Text(
                      '${proximity.distanceFromItineraryKm.toStringAsFixed(1)} km away',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _proximityColor(proximity.proximity).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        _proximityIcon(proximity.proximity) == Icons.circle
                            ? '🟢 ${proximity.proximity}'
                            : proximity.proximity,
                        style: AppTextStyles.labelSm.copyWith(
                          color: _proximityColor(proximity.proximity),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.directions, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Estimated travel: ${proximity.travelText}',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ] else if (_vm.isPlanning)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Checking distance & schedule…'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _proximityIcon(String proximity) => switch (proximity) {
        'Near' => Icons.circle,
        'Moderate' => Icons.radio_button_checked,
        _ => Icons.error,
      };

  Color _proximityColor(String proximity) => switch (proximity) {
        'Near' => AppColors.secondaryPine,
        'Moderate' => AppColors.primaryTerracotta,
        _ => AppColors.error,
      };

  // ─── Plan preview ───────────────────────────────────────────

  Widget _buildPlanPreviewSection() {
    final plan = _vm.planResult!;
    final day = plan.proposedDay;
    if (day == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('PREVIEW', style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.bold,
            )),
            const Spacer(),
            Icon(
              plan.success ? Icons.check_circle : Icons.error,
              color: plan.success ? AppColors.secondaryPine : AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              plan.success ? 'Valid' : 'Invalid',
              style: AppTextStyles.labelSm.copyWith(
                color: plan.success ? AppColors.secondaryPine : AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: day.stops.map((s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      s.attraction.place.placeId == _vm.selectedPlaceId
                          ? Icons.add_circle
                          : Icons.circle,
                      size: 14,
                      color: s.attraction.place.placeId == _vm.selectedPlaceId
                          ? AppColors.primaryTerracotta
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${DateFormat('HH:mm').format(s.startTime)} – '
                      '${DateFormat('HH:mm').format(s.endTime)}',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.attraction.place.name,
                        style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        if (plan.message != null) ...[
          const SizedBox(height: 12),
          Text(
            plan.message!,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Widget _buildPlanErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        'This location cannot be added because it does not fit the schedule '
        '(exploration time, travel time, or opening hours).',
        style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
      ),
    );
  }

  Widget _buildSaveErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        'Failed to save: ${_vm.saveError}',
        style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
      ),
    );
  }

  // ─── Confirm bar → confirmation popup ───────────────────────

  Widget _buildConfirmBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryTerracotta,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          onPressed: _vm.isSaving ? null : _showConfirmation,
          child: Text(
            _vm.isSaving ? 'Saving…' : 'Add Location',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Future<void> _showConfirmation() async {
    final place = _vm.selectedPlace;
    final proximity = _vm.proximity;
    if (place == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Location?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name,
                style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600)),
            if (proximity != null) ...[
              const SizedBox(height: 8),
              Text(
                '${proximity.distanceFromItineraryKm.toStringAsFixed(1)} km from '
                'current itinerary',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Estimated travel: ${proximity.travelText}',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'The itinerary will be updated to accommodate this location.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add Location'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok = await _vm.confirmAndSave();
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location added successfully.')),
        );
        Navigator.pop(context, true);
      }
    }
  }
}
