// lib/view/Itinerary/widgets/change_location_picker_sheet.dart
//
// Change Location recommendation sheet used by the preview editor
// (EditItineraryScreen).
//
// Workflow:
//   editability check → nearby candidates → Dart hard-filter → AI ranking
//   (10s hard budget, ~6-7s AI window) → "Recommended for you" cards
//   + the existing manual search. Tapping ANY place (AI or manual) opens
//   the EXISTING ViewPlaceDetailScreen in replacement mode; the stop is
//   replaced only after the traveler taps "Use This Place" and the final
//   deterministic validation succeeds. No database writes — the caller's
//   onUsePlace callback owns the replacement.

import 'package:flutter/material.dart';

import '../../../core/config/api_keys.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/business_logic/itinerary_service/change_location_service.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/change_location_vm.dart';
import 'view_place_detail_screen.dart';

class ChangeLocationPickerSheet extends StatefulWidget {
  /// The stop currently being replaced (provides itineraryId + stopId).
  final ItineraryStop stop;

  /// In-memory place IDs already scheduled on the temporary itinerary —
  /// duplicates are hard-filtered BEFORE the AI sees any candidate.
  final Set<String> scheduledPlaceIds;

  /// Trip date of the stop's day (opening-hours/date filtering).
  final DateTime tripDate;

  final List<String> interests;
  final String explorationTime;

  /// Final deterministic validation + replacement. Return a traveler-facing
  /// Problem message on failure, or null on success.
  final Future<String?> Function(Place selected) onUsePlace;

  const ChangeLocationPickerSheet({
    super.key,
    required this.stop,
    required this.scheduledPlaceIds,
    required this.tripDate,
    required this.interests,
    required this.explorationTime,
    required this.onUsePlace,
  });

  @override
  State<ChangeLocationPickerSheet> createState() =>
      _ChangeLocationPickerSheetState();
}

class _ChangeLocationPickerSheetState extends State<ChangeLocationPickerSheet> {
  late final ChangeLocationViewModel _vm;
  final GoogleMapsService _mapsService = GoogleMapsService();
  final TextEditingController _queryController = TextEditingController();

  List<Place> _results = [];
  bool _isSearching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _vm = ChangeLocationViewModel(stop: widget.stop);
    _vm.loadPreviewRecommendations(
      scheduledPlaceIds: widget.scheduledPlaceIds,
      tripDate: widget.tripDate,
      visitDurationMinutes: widget.stop.durationMinutes,
      interests: widget.interests,
      explorationTime: widget.explorationTime,
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    _queryController.dispose();
    super.dispose();
  }

  /// Opens the EXISTING ViewPlaceDetailScreen in replacement mode for the
  /// tapped place (AI recommendation or manual search result). Both paths
  /// share the same final validation via [widget.onUsePlace].
  Future<void> _openPlaceDetail(Place place) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: place.placeId,
          initialPlace: place,
          isReplacement: true,
          replacingStopId: widget.stop.stopId.toString(),
          onUsePlace: (selected) => widget.onUsePlace(selected),
        ),
      ),
    );
    if (changed == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _mapsService.searchTextPlaces(query: trimmed);
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _searchError = 'No places found. Try a different search.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searchError = 'Could not search places. Check your connection.';
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.moduleBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Change Location',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),

            // ── AI recommendations / problem state ──
            ListenableBuilder(
              listenable: _vm,
              builder: (context, _) {
                if (_vm.isLoadingRecommendations) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Finding recommended places...',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  );
                }

                if (_vm.problemMessage != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 20, color: AppColors.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _vm.problemMessage!,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (_vm.recommendations.isEmpty) {
                  return const SizedBox.shrink();
                }

                return _buildRecommendations();
              },
            ),

            // ── Manual search (existing behavior) ──
            const Text(
              'SEARCH MANUALLY',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search restaurants or attractions...',
                hintStyle: const TextStyle(color: AppColors.inkFaint),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.inkFaint),
                suffixIcon: _queryController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _queryController.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.moduleBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.moduleBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_searchError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _searchError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkFaint,
                  ),
                ),
              )
            else if (_results.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Or pick one of the recommendations above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final place = _results[index];
                    return _ManualResultTile(
                      place: place,
                      onTap: () => _openPlaceDetail(place),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    final recommendations = _vm.recommendations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'RECOMMENDED FOR YOU${_vm.usedFallback ? ' (NEARBY)' : ''}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.38,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: recommendations.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rec = recommendations[index];
              return _RecommendationCard(
                recommendation: rec,
                onTap: () => _openPlaceDetail(rec.place),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// AI recommendation card: name, rating, category, short reason, distance.
class _RecommendationCard extends StatelessWidget {
  final ChangeLocationRecommendation recommendation;
  final VoidCallback onTap;

  const _RecommendationCard({required this.recommendation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final place = recommendation.place;
    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
            '?maxwidth=200&photoreference=${place.photoReference}'
            '&key=${ApiKeys.googleMapsApiKey}'
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.moduleBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 52,
                height: 52,
                color: AppColors.surface2,
                child: photoUrl != null
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.place,
                          color: AppColors.inkFaint,
                        ),
                      )
                    : const Icon(Icons.place, color: AppColors.inkFaint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (place.placeRating > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 14, color: AppColors.gold),
                        const SizedBox(width: 2),
                        Text(
                          place.placeRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if ((place.placeCategory ?? '').isNotEmpty) ...[
                        Text(
                          place.placeCategory!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.inkFaint),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        recommendation.distanceText,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.inkFaint),
                      ),
                    ],
                  ),
                  if (recommendation.reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      recommendation.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Manual search result tile — routes through the same ViewPlaceDetailScreen
/// replacement flow as AI recommendations.
class _ManualResultTile extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;

  const _ManualResultTile({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photoUrl = place.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
            '?maxwidth=200&photoreference=${place.photoReference}'
            '&key=${ApiKeys.googleMapsApiKey}'
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.moduleBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 52,
                height: 52,
                color: AppColors.surface2,
                child: photoUrl != null
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.place,
                          color: AppColors.inkFaint,
                        ),
                      )
                    : const Icon(Icons.place, color: AppColors.inkFaint),
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
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (place.placeAddress.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      place.placeAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
