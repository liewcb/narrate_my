// lib/view/Itinerary/manage_itinerary/manage_detail_plan_screen.dart
//
// Detail-plan screen: shares the same MVVM insight (ManageDisplayPlanViewModel,
// temporal status, save/discard flow, edit-stop/edit-day navigation) as
// ManageDisplayPlanScreen, but presents a different UI — a horizontally
// swiped day selector with detailed stop timeline cards.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/entities/itinerary_stop.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import '../../../viewmodel/Itinerary/manage_display_plan_vm.dart';
import 'edit_stop_screen.dart';
import 'add_from_bookmark.dart';

class ManageDetailPlanScreen extends StatefulWidget {
  final String itineraryId;

  const ManageDetailPlanScreen({Key? key, required this.itineraryId})
      : super(key: key);

  @override
  State<ManageDetailPlanScreen> createState() =>
      _ManageDetailPlanScreenState();
}

class _ManageDetailPlanScreenState extends State<ManageDetailPlanScreen> {
  late ManageDisplayPlanViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ManageDisplayPlanViewModel(itineraryId: widget.itineraryId);
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final itinerary = _viewModel.itinerary;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // ── Hero Section ──
                  _buildHero(itinerary),
                  const SizedBox(height: 24),

                  // ── Day Selector ──
                  _buildDaySelector(),
                  const SizedBox(height: 24),

                  // ── Stop Timeline ──
                  Expanded(
                    child: _viewModel.currentDayDisplayStops.isEmpty
                        ? _buildEmptyDay()
                        : ListView.builder(
                            padding: const EdgeInsets.only(
                              left: 24,
                              right: 24,
                              bottom: 160,
                            ),
                            itemCount:
                                _viewModel.currentDayDisplayStops.length,
                            itemBuilder: (context, index) {
                              return _buildStopCard(index);
                            },
                          ),
                  ),
                ],
              ),
              _buildStickyBottomBar(context),
            ],
          ),
        );
      },
    );
  }

  // ─── Hero ──────────────────────────────────────────────────

  Widget _buildHero(dynamic itinerary) {
    final status = _viewModel.temporalStatus;
    final (Color bg, Color fg, String label, IconData icon) = switch (status) {
      ItineraryTemporalStatus.past => (
        AppColors.surface2,
        AppColors.inkFaint,
        'Past',
        Icons.history,
      ),
      ItineraryTemporalStatus.ongoing => (
        AppColors.green,
        AppColors.surface,
        'Ongoing',
        Icons.play_circle_outline,
      ),
      ItineraryTemporalStatus.upcoming => (
        AppColors.accentSoft,
        AppColors.bg,
        'Upcoming',
        Icons.event_available,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              height: 160,
              width: double.infinity,
              color: AppColors.accent.withOpacity(0.15),
              child: itinerary?.coverImageUrl != null
                  ? Image.network(itinerary!.coverImageUrl!, fit: BoxFit.cover)
                  : const Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 48,
                        color: AppColors.inkFaint,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  itinerary?.title ?? 'My Trip',
                  style: AppTextStyles.pageTitle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: AppTextStyles.labelSm.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (itinerary != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${itinerary.totalDays} Days • '
                '${DateFormat('d MMM').format(itinerary.startDate)} – '
                '${DateFormat('d MMM').format(itinerary.endDate)}',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Day Selector (horizontal chip scroll) ────────────────

  Widget _buildDaySelector() {
    final totalDays = _viewModel.itinerary?.totalDays ?? 1;
    final selected = _viewModel.selectedDayIndex;

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: totalDays,
        itemBuilder: (context, index) {
          final dayIndex = index + 1;
          final isActive = selected == dayIndex;
          final date = _viewModel.itinerary?.startDate
              .add(Duration(days: index));

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _viewModel.selectDay(dayIndex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isActive
                        ? AppColors.accent
                        : AppColors.moduleBorder,
                  ),
                ),
                child: Text(
                  date != null
                      ? 'Day $dayIndex • ${DateFormat('d MMM').format(date)}'
                      : 'Day $dayIndex',
                  style: AppTextStyles.labelSm.copyWith(
                    color: isActive ? AppColors.surface : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Empty Day ────────────────────────────────────────────

  Widget _buildEmptyDay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tour_outlined, size: 64, color: AppColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              'No places on this day yet.',
              style: AppTextStyles.bodyLg.copyWith(color: AppColors.inkFaint),
            ),
            const SizedBox(height: 8),
            Text(
              'Add bookmarks or a custom place to get started.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
              textAlign: TextAlign.center,
            ),
            if (_viewModel.canCustomize) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _openAddBookmarks(_viewModel.selectedDayIndex),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Add from bookmarks'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Stop Card ────────────────────────────────────────────

  Widget _buildStopCard(int index) {
    final display = _viewModel.currentDayDisplayStops[index];
    final stop = display.stop;
    final place = display.place;
    final isExpanded = _viewModel.expandedStopId == stop.stopId.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _viewModel.toggleStopExpansion(stop.stopId.toString()),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: isExpanded
                  ? Border.all(color: AppColors.accent.withOpacity(0.3))
                  : null,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ──
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isExpanded
                            ? AppColors.accent
                            : AppColors.surface2,
                        border: isExpanded
                            ? null
                            : Border.all(color: AppColors.moduleBorder),
                      ),
                      child: Center(
                        child: Text(
                          '${stop.stopOrder + 1}',
                          style: AppTextStyles.labelSm.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isExpanded
                                ? Colors.white
                                : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: AppTextStyles.bodyLg.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            display.formattedTime,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppColors.inkFaint,
                    ),
                  ],
                ),

                // ── Expanded details ──
                if (isExpanded) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.moduleBorder),
                  const SizedBox(height: 16),

                  // Address
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          place.address,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Duration
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        '${stop.durationMinutes} min visit',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),

                  // Travel info
                  if (display.travelFromPrevText != null ||
                      display.travelToNextText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.directions_car_rounded,
                              size: 16, color: AppColors.inkSoft),
                          const SizedBox(width: 6),
                          Text(
                            display.travelFromPrevText != null
                                ? 'From prev: ${display.travelFromPrevText}'
                                : 'Starting point',
                            style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.inkSoft,
                            ),
                          ),
                          if (display.travelToNextText != null) ...[
                            const Spacer(),
                            Icon(Icons.arrow_downward_rounded,
                                size: 16, color: AppColors.inkSoft),
                            const SizedBox(width: 6),
                            Text(
                              'To next: ${display.travelToNextText}',
                              style: AppTextStyles.labelSm.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Actions
                  if (_viewModel.canCustomize) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openStop(stop),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _deleteStop(stop),
                          icon: const Icon(Icons.delete_rounded, size: 18),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Bar ───────────────────────────────────────────

  Widget _buildStickyBottomBar(BuildContext context) {
    if (!_viewModel.canCustomize) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: AppColors.bg.withOpacity(0.95),
          ),
          child: Text(
            _viewModel.isReadOnly
                ? 'This itinerary is in the past and is read-only.'
                : 'This itinerary is upcoming — you can view it but '
                    'progress cannot be recorded yet.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.bg.withOpacity(0.95),
          border: Border(
            top: BorderSide(color: AppColors.moduleBorder),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _viewModel.isSaving ? null : () => _discardChanges(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: BorderSide(color: AppColors.moduleBorder),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _viewModel.isSaving
                    ? null
                    : () => _saveChanges(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: Text(_viewModel.isSaving ? 'Saving…' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Handlers ─────────────────────────────────────────────

  Future<void> _openStop(ItineraryStop stop) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStopScreen(
          stop: stop,
          itineraryStartDate:
              _viewModel.itinerary?.startDate ?? DateTime.now(),
          isReadOnly: _viewModel.isReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _viewModel.load();
    }
  }

  Future<void> _deleteStop(ItineraryStop stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove place?'),
        content: const Text(
          'This place will be removed. The schedule and route '
          'will not be recalculated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _viewModel.deleteStop(stop.stopId.toString());
    }
  }

  Future<void> _openAddBookmarks(int dayIndex) async {
    final selectedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddFromBookmarksScreen(
          userId: _viewModel.itinerary?.userId ?? '',
        ),
      ),
    );
    if (selectedIds != null && selectedIds.isNotEmpty && mounted) {
      final added = await _viewModel.addBookmarkedPlaces(
        dayIndex: dayIndex,
        placeIds: selectedIds,
      );
      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added bookmark(s).')),
        );
        await _viewModel.load();
      }
    }
  }

  Future<void> _saveChanges(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _viewModel.saveChanges();
      messenger.showSnackBar(
        const SnackBar(content: Text('Itinerary saved.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Future<void> _discardChanges(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Unsaved customization changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _viewModel.load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes discarded.')),
      );
    }
  }
}