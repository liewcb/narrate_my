import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/colors.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/Itinerary/must_visit_selection_vm.dart';
import 'split_days_screen.dart';

class MustVisitSelectionScreen extends StatefulWidget {
  final TripDraft draft;
  const MustVisitSelectionScreen({super.key, required this.draft});

  @override
  State<MustVisitSelectionScreen> createState() => _MustVisitSelectionScreenState();
}

class _MustVisitSelectionScreenState extends State<MustVisitSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    print('CURRENT USER: ${user?.id}');

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('No user logged in'),
        ),
      );
    }

    return ChangeNotifierProvider<Step3AddPlaceVM>(
      create: (_) => Step3AddPlaceVM(
        widget.draft,
        userId: user.id,
      ),
      child: const _Step3AddPlaceBody(),
    );
  }
}

class _Step3AddPlaceBody extends StatelessWidget {
  const _Step3AddPlaceBody();

  List<DestinationWithDays> _buildDestinationsWithDays(TripDraft draft) {
    return draft.destinations.map((dest) {
      final allocatedDays = draft.daySplit[dest.destinationName] ?? 1;
      return DestinationWithDays(
        id: dest.id,
        name: dest.destinationName,
        imageUrl: dest.imageUrl,
        initialDays: allocatedDays,
      );
    }).toList();
  }

  void _navigateToSplitDays(BuildContext context, TripDraft draft) {
    final destinationsWithDays = _buildDestinationsWithDays(draft);
    int totalDays = draft.totalDays;

    if (draft.daySplit.isEmpty && destinationsWithDays.isNotEmpty) {
      final count = destinationsWithDays.length;
      final base = totalDays ~/ count;
      final extra = totalDays % count;
      for (int i = 0; i < count; i++) {
        destinationsWithDays[i].days = base + (i < extra ? 1 : 0);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SplitDaysScreen(
          draft: draft,
          destinations: destinationsWithDays,
          totalPlannedDays: totalDays,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step3AddPlaceVM>();

    final query = vm.searchQuery.trim().toLowerCase();
    List<WizardPlace> displayPlaces;

    if (vm.selectedTab == 1) {
      displayPlaces = query.isEmpty
          ? vm.pagedDefaultPlaces
          : vm.pagedDefaultPlaces.where((p) =>
      p.name.toLowerCase().contains(query) ||
          p.type.toLowerCase().contains(query) ||
          p.location.toLowerCase().contains(query)
      ).toList();
    } else {
      displayPlaces = query.isEmpty
          ? vm.availablePlaces
          : vm.availablePlaces.where((p) =>
      p.name.toLowerCase().contains(query) ||
          p.type.toLowerCase().contains(query) ||
          p.location.toLowerCase().contains(query)
      ).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WizardAppBar(step: 3),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: WizardProgressBar(activeSteps: 3),
                  ),
                  const SizedBox(height: 8),
                  const _Title(),
                  const SizedBox(height: 24),
                  _TabToggle(
                    selectedIndex: vm.selectedTab,
                    onChanged: vm.setTab,
                  ),
                  const SizedBox(height: 14),
                  _SelectedChips(
                    selectedEntries: vm.mustVisitEntries,
                    onRemove: vm.removeMustVisit,
                  ),
                  const SizedBox(height: 14),
                  _SearchBar(onChanged: vm.searchPlaces),
                  if (vm.selectedTab == 1 && vm.selectedHotspot != null) ...[
                    const SizedBox(height: 12),
                    _HotspotBanner(
                      hotspotName: vm.selectedHotspot!.hotspotName,
                      radiusKm: vm.selectedHotspot!.suggestedRadiusKm,
                    ),
                  ],
                  const SizedBox(height: 22),

                  if (vm.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (vm.selectedTab == 0 && vm.isLoadingBookmarks)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (vm.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.cloud_off, color: AppColors.outline, size: 40),
                              const SizedBox(height: 8),
                              Text(
                                vm.errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.outline, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (vm.selectedTab == 0 && vm.bookmarksError != null && vm.availablePlaces.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.bookmark_border, color: AppColors.outline, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  vm.bookmarksError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppColors.outline, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (displayPlaces.isEmpty && query.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                            child: Center(
                              child: Text(
                                vm.selectedTab == 1
                                    ? 'No places found in the selected destination.'
                                    : 'No bookmarks yet.\nSave places you want to visit!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.outline, fontSize: 14, height: 1.4),
                              ),
                            ),
                          )
                        else if (displayPlaces.isEmpty && query.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.search_off, color: AppColors.outline, size: 40),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No places match your search.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.outline, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            _PlaceList(
                              places: displayPlaces,
                              isAdded: vm.isPlaceAdded,
                              onToggle: (placeId, {confirmOutsideHotspot = false}) =>
                                  vm.togglePlace(
                                    placeId,
                                    // REQ_MV_08 §8 — preserve the selection
                                    // source through to generation.
                                    source: vm.selectedTab == 0
                                        ? 'BOOKMARK'
                                        : 'GOOGLE_SEARCH',
                                    confirmOutsideHotspot: confirmOutsideHotspot,
                                  ),
                              showLoadMore: vm.selectedTab == 1 &&
                                  query.isEmpty &&
                                  vm.hasMoreDefaultPlaces,
                              onLoadMore: vm.loadMorePlaces,
                              isLoadingMore: vm.isLoadingMore,
                            ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            _StickyFooter(
              selectedCount: vm.mustVisitPlaceIds.length,
              onContinue: () {
                final draft = vm.buildDraft();
                _navigateToSplitDays(context, draft);
              },
              onSkip: () {
                final draft = vm.buildDraft();
                _navigateToSplitDays(context, draft);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub‑widgets ──────────────────────────────────────────────────

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Must-visit attractions",
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.brandGreen,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Select places you want to visit during your trip.",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.outline),
          ),
        ],
      ),
    );
  }
}

class _TabToggle extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _TabToggle({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.outlineLight.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _tabButton(0, "Bookmarks"),
            _tabButton(1, "Search Maps"),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final isSelected = selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.brandGreen : AppColors.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedChips extends StatelessWidget {
  final List<(String, String)> selectedEntries; // (placeId, displayName)
  final ValueChanged<String> onRemove;
  const _SelectedChips({
    required this.selectedEntries,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedEntries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("MUST-VISIT PLACES SELECTED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: AppColors.outline)),
                Text("${selectedEntries.length}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.brandGreen)),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: selectedEntries.map((entry) {
                final (placeId, name) = entry;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreenLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 18, color: AppColors.brandGreen),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.brandCharcoal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onRemove(placeId),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(2.0),
                          child: Icon(Icons.close, size: 18, color: AppColors.outline),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search, color: AppColors.outline),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: "Search restaurants or attractions...",
                  hintStyle: TextStyle(color: AppColors.outline, fontSize: 14, fontWeight: FontWeight.normal),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(fontSize: 14, color: AppColors.brandCharcoal),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _HotspotBanner extends StatelessWidget {
  final String hotspotName;
  final double radiusKm;
  const _HotspotBanner({required this.hotspotName, required this.radiusKm});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brandGreenLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brandGreen),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: AppColors.brandGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Searching around $hotspotName', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.brandGreen)),
                  Text('Recommended radius: ${radiusKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12, color: AppColors.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceList extends StatelessWidget {
  final List<WizardPlace> places;
  final bool Function(String) isAdded;
  final Future<MustVisitSelectionResult> Function(String placeId,
      {bool confirmOutsideHotspot}) onToggle;
  final bool showLoadMore;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  const _PlaceList({
    required this.places,
    required this.isAdded,
    required this.onToggle,
    this.showLoadMore = false,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  Future<void> _handleToggle(
      BuildContext context, WizardPlace place) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await onToggle(
      place.placeId,
      confirmOutsideHotspot: false,
    );

    switch (result.status) {
      case MustVisitSelectionStatus.added:
        break;
      case MustVisitSelectionStatus.warning:
        // OUTSIDE_HOTSPOT — traveler may confirm (§19). "Add Anyway" only
        // means "outside the recommended hotspot"; it never bypasses the
        // other validation rules.
        if (!context.mounted) break;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Outside recommended hotspot'),
            content: Text(result.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add Anyway')),
            ],
          ),
        );
        if (confirmed == true) {
          await onToggle(place.placeId, confirmOutsideHotspot: true);
        }
        break;
      case MustVisitSelectionStatus.rejected:
        // Validation failure — clear message, never a raw exception.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          ...places.map((place) {
            final added = isAdded(place.placeId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PlaceCard(
                place: place,
                isAdded: added,
                onToggle: () => _handleToggle(context, place),
              ),
            );
          }).toList(),
          if (showLoadMore)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: OutlinedButton.icon(
                onPressed: isLoadingMore ? null : onLoadMore,
                icon: isLoadingMore
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: Text(isLoadingMore ? 'Loading...' : 'Load more places'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final WizardPlace place;
  final bool isAdded;
  final VoidCallback onToggle;
  const _PlaceCard({required this.place, required this.isAdded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: place.imageUrl != null
                    ? Image.network(
                  place.imageUrl!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    color: AppColors.outlineLight,
                    child: const Icon(Icons.image_not_supported, color: AppColors.outline),
                  ),
                )
                    : Container(
                  width: 72,
                  height: 72,
                  color: AppColors.outlineLight,
                  child: const Icon(Icons.landscape, color: AppColors.outline),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.brandGreen, height: 1.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.location.isNotEmpty ? '${place.type} · ${place.location}' : place.type,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.brandGreenLight, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: AppColors.brandTerracotta),
                    const SizedBox(width: 4),
                    Text(place.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.brandCharcoal)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.start,
                  children: [
                    _infoChip(place.travelIcon, place.travelTime),
                    if (place.duration != null) _infoChip(Icons.hourglass_bottom, place.duration!),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                // Selection decisions live in the ViewModel; the card only
                // triggers the toggle and displays the resulting feedback.
                onTap: onToggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAdded ? AppColors.brandGreen : AppColors.outlineLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAdded ? "Added ✓" : "+ Add",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isAdded ? Colors.white : AppColors.brandCharcoal),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.outline),
        const SizedBox(width: 4),
        Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: AppColors.outline)),
      ],
    );
  }
}

class _StickyFooter extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  const _StickyFooter({required this.selectedCount, required this.onContinue, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final bool hasSelection = selectedCount > 0;
    final String placeLabel = selectedCount == 1 ? 'Place' : 'Places';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(color: AppColors.creamBg.withOpacity(0.95)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasSelection) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandTerracotta,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: onContinue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Continue with $selectedCount $placeLabel', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            GestureDetector(
              onTap: onSkip,
              child: const Text('Skip for now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.outline)),
            ),
          ],
        ),
      ),
    );
  }
}