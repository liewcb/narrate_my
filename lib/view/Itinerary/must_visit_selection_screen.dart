// lib/view/Itinerary/must_visit_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/Itinerary/must_visit_selection_vm.dart';
import 'day_allocation_screen.dart';

class MustVisitSelectionScreen extends StatefulWidget {
  final TripDraft draft;
  const MustVisitSelectionScreen({super.key, required this.draft});

  @override
  State<MustVisitSelectionScreen> createState() => _MustVisitSelectionScreenState();
}

class _MustVisitSelectionScreenState extends State<MustVisitSelectionScreen> {
  static const String _userId = '252f0924-192c-42fe-8643-881da7bbf285';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Step3AddPlaceVM>(
      create: (_) => Step3AddPlaceVM(widget.draft, userId: _userId),
      child: const _Step3AddPlaceBody(),
    );
  }
}

class _Step3AddPlaceBody extends StatelessWidget {
  const _Step3AddPlaceBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step3AddPlaceVM>();

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
                  const SizedBox(height: 10),
                  _SelectedChips(
                    selectedNames: vm.mustVisitPlaces,
                    onRemove: vm.togglePlace,
                  ),
                  const SizedBox(height: 14),
                  _SearchBar(onChanged: vm.searchPlaces),
                  const SizedBox(height: 22),
                  // ... rest of the content unchanged ...
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
                    else if (vm.selectedTab == 1 && vm.availablePlaces.isEmpty && vm.searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.map_outlined, size: 48, color: AppColors.outline),
                                const SizedBox(height: 12),
                                const Text(
                                  'Explore top attractions and restaurants nearby',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.outline, fontSize: 14),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: vm.loadDefaultPlaces,
                                  icon: const Icon(Icons.explore_outlined, color: Colors.white),
                                  label: const Text('Load Recommended Places'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
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
                        else if (vm.availablePlaces.isEmpty)
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
                          else
                            _PlaceList(
                              places: vm.selectedTab == 1
                                  ? vm.pagedDefaultPlaces
                                  : vm.availablePlaces,
                              isAdded: vm.isPlaceAdded,
                              onToggle: vm.togglePlace,
                              showLoadMore: vm.selectedTab == 1 &&
                                  vm.searchQuery.isEmpty &&
                                  vm.hasMoreDefaultPlaces,
                              onLoadMore: vm.loadMorePlaces,
                              isLoadingMore: vm.isLoadingMore,
                            ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            _StickyFooter(
              selectedCount: vm.mustVisitPlaces.length,
              onContinue: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddAllocationScreen(draft: vm.buildDraft()),
                  ),
                );
              },
              onSkip: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddAllocationScreen(draft: vm.buildDraft()),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private Sub‑Widgets (unchanged, except _AppBar removed) ─────

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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.outline,
            ),
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
      // Alignment: Shares identical 24px horizontal grid line
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 48,
        // Simplification: Subtle background container instead of heavy shadows/borders
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
  final List<String> selectedNames;
  final ValueChanged<String> onRemove;

  const _SelectedChips({required this.selectedNames, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (selectedNames.isEmpty) return const SizedBox.shrink();
    return Padding(
      // Alignment: 24px horizontal grid line
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hierarchy: 14px regular muted label text
          Text(
            "Selected (${selectedNames.length})",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedNames.map((name) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => onRemove(name),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
      // Alignment: 24px horizontal grid margin
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 56,
        // Simplification: Soft white container with no elevation or borders
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
                  // Hierarchy: 14px regular secondary text for hint
                  hintStyle: TextStyle(
                    color: AppColors.outline,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
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

class _PlaceList extends StatelessWidget {
  final List<WizardPlace> places;
  final bool Function(String) isAdded;
  final ValueChanged<String> onToggle;
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Alignment: Shared 24px vertical grid line
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          ...places.map((place) {
            final added = isAdded(place.name);
            return Padding(
              // Spacing: 16px grid margin between cards
              padding: const EdgeInsets.only(bottom: 16),
              child: _PlaceCard(
                place: place,
                isAdded: added,
                onToggle: () => onToggle(place.name),
              ),
            );
          }).toList(),
          if (showLoadMore)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: OutlinedButton.icon(
                onPressed: isLoadingMore ? null : onLoadMore,
                icon: isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(isLoadingMore ? 'Loading...' : 'Load more places'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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

  const _PlaceCard({
    required this.place,
    required this.isAdded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: image + name + type (unchanged)
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
                    child: const Icon(Icons.image_not_supported,
                        color: AppColors.outline),
                  ),
                )
                    : Container(
                  width: 72,
                  height: 72,
                  color: AppColors.outlineLight,
                  child: const Icon(Icons.landscape,
                      color: AppColors.outline),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandGreen,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.location.isNotEmpty
                          ? '${place.type} · ${place.location}'
                          : place.type,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: AppColors.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Bottom row: rating + flexible chips + add button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Rating chip – fixed width
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGreenLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star,
                      size: 14,
                      color: AppColors.brandTerracotta,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      place.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandCharcoal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Middle section: travel + duration chips that wrap
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.start,
                  children: [
                    _infoChip(place.travelIcon, place.travelTime),
                    if (place.duration != null)
                      _infoChip(Icons.hourglass_bottom, place.duration!),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Add button – fixed size
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAdded ? AppColors.brandGreen : AppColors.outlineLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAdded ? "Added ✓" : "+ Add",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isAdded ? Colors.white : AppColors.brandCharcoal,
                    ),
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
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}

class _StickyFooter extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _StickyFooter({
    required this.selectedCount,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        // Alignment & Spacing: Strict 24px side padding grid line, 32px top margin padding
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: AppColors.creamBg.withOpacity(0.95),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandTerracotta,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0, // Simplification: Flat button aesthetic
              ),
              onPressed: onContinue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Continue with $selectedCount Places",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onSkip,
              child: const Text(
                "Skip for now",
                // Hierarchy: 14px regular secondary text
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}