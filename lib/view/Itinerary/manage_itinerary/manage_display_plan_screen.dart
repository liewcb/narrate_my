// lib/view/Itinerary/manage_itinerary/manage_display_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:narrate_my/view/Itinerary/itinerary_theme_tokens.dart';
import '../../../model/entities/bookmark.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../viewmodel/ItineraryModel/manage_display_plan_vm.dart';
import 'add_custom_place_screen.dart';
import 'package:narrate_my/view/Itinerary/manage_itinerary/itinerary_status_resolver.dart';
import 'add_from_bookmark.dart';
import 'edit_stop_screen.dart';

class ManageDisplayPlanScreen extends StatefulWidget {
  final String itineraryId;

  const ManageDisplayPlanScreen({Key? key, required this.itineraryId})
      : super(key: key);

  @override
  State<ManageDisplayPlanScreen> createState() => _ManageDisplayPlanScreenState();
}

class _ManageDisplayPlanScreenState extends State<ManageDisplayPlanScreen> {
  late ManageDisplayPlanViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ManageDisplayPlanViewModel(itineraryId: widget.itineraryId);
    _viewModel.load();
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
            elevation: 0, // Simplification: No app bar shadow
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
              // Main Scrollable Canvas
              ListView(
                // Spacing: Enforcing 24px margins on the scrollable area (8px grid)
                padding: const EdgeInsets.only(
                  left: 24.0,
                  right: 24.0,
                  top: 8.0,
                  bottom: 160.0,
                ),
                children: [
                  _buildHeroSection(itinerary),
                  const SizedBox(height: 24.0),
                  _buildStopFilterChips(),
                  // Spacing: 32px strict margin between major sections
                  const SizedBox(height: 32.0),
                  ..._buildDayCards(),
                  const SizedBox(height: 32.0),
                ],
              ),
              _buildStickyBottomBar(context),
            ],
          ),
        );
      },
    );
  }

  // ─── Hero Section ───────────────────────────────────────────

  Widget _buildHeroSection(dynamic itinerary) {
    return Column(
      // Alignment: Align all text left strictly
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            height: 200,
            width: double.infinity,
            color: AppColors.accent.withOpacity(0.15),
            child: itinerary?.coverImageUrl != null
                ? Image.network(
              itinerary!.coverImageUrl!,
              fit: BoxFit.cover,
            )
                : const Center(
              child: Icon(
                Icons.map_outlined,
                size: 56,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24.0), // Spacing: 8px grid
        // Hierarchy: Main header strictly 24px bold
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                itinerary?.title ?? 'My Trip',
                style: AppTextStyles.pageTitle,
              ),
            ),
            const SizedBox(width: 8.0),
            _buildStatusBadge(),
          ],
        ),
        const SizedBox(height: 8.0), // Spacing: 8px grid
        // Hierarchy: Secondary text strictly 14px regular muted color
        Text(
          itinerary != null
              ? '${itinerary.totalDays} Days • ${DateFormat('d MMM').format(itinerary.startDate)}-${DateFormat('d MMM').format(itinerary.endDate)}'
              : '',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    );
  }

  // ─── Stop Status Filter Chips ────────────────────────────────

  Widget _buildStopFilterChips() {
    final options = <(String?, String)>[
      (null, 'All'),
      ('PLANNED', 'Planned'),
      ('COMPLETED', 'Completed'),
      ('SKIPPED', 'Skipped'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: options.map((opt) {
          final (value, label) = opt;
          final isActive = _viewModel.stopStatusFilter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () => _viewModel.setStopStatusFilter(value),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.green
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: isActive
                        ? AppColors.green
                        : AppColors.moduleBorder,
                  ),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.labelSm.copyWith(
                    color: isActive
                        ? AppColors.surface
                        : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Day Cards ────────────────────────────────────────────────

  List<Widget> _buildDayCards() {
    final grouped = <int, List<ItineraryStop>>{};
    for (final stop in _viewModel.stops) {
      grouped.putIfAbsent(stop.dayIndex, () => []).add(stop);
    }

    if (grouped.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              'No stops yet for this itinerary.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
            ),
          ),
        ),
      ];
    }

    final days = grouped.keys.toList()..sort();
    final itinerary = _viewModel.itinerary;
    final cards = <Widget>[];

    for (final dayIndex in days) {
      final stops = grouped[dayIndex]!..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      final date = itinerary?.startDate.add(Duration(days: dayIndex - 1));
      final dayTitle = 'Day $dayIndex';
      final dayMeta = date != null
          ? '${DateFormat('d MMM').format(date)} • ${stops.length} stops'
          : '${stops.length} stops';

      cards.add(
        _buildDayCard(
          dayTitle: dayTitle,
          dayMeta: dayMeta,
          stops: stops,
          dayIndex: dayIndex,
          dayDate: date ?? DateTime.now(),
        ),
      );
      // Spacing: 32px between grouped section cards
      cards.add(const SizedBox(height: 32.0));
    }

    return cards;
  }

  Widget _buildDayCard({
    required String dayTitle,
    required String dayMeta,
    required List<ItineraryStop> stops,
    required int dayIndex,
    required DateTime dayDate,
  }) {
    // Simplification: Replaced Material Card with a flat Container.
    // Removed unnecessary borders/shadows and used subtle background shades.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      // Spacing: Strict 24px padding inside the container
      padding: const EdgeInsets.all(24.0),
      child: Column(
        // Alignment: Align all text left
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hierarchy: Main header 24px bold
          Text(dayTitle, style: AppTextStyles.pageTitle),
          const SizedBox(height: 8.0),
          // Hierarchy: Secondary text 14px regular muted color
          Text(
            dayMeta,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
          ),
          const SizedBox(height: 24.0),
          ...stops.map((stop) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0), // Spacing: 8px grid
            child: _buildStopRow(stop),
          )),
          const SizedBox(height: 8.0),
          // Add custom place button (Ongoing only)
          if (_viewModel.canCustomize) ...[
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _openAddPlace(dayIndex, dayDate),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(
                  'Add custom place to ${dayTitle.toLowerCase()}',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.accent,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _openAddBookmarks(dayIndex),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(
                  'Add from bookmarks to ${dayTitle.toLowerCase()}',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.green,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStopRow(ItineraryStop stop) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openStop(stop),
        borderRadius: BorderRadius.circular(AppRadius.iconSm),
        // Spacing: Internal padding for clickable area aligned to 8px grid
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  // Alignment: Text left
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.place?.name ?? stop.placeId,
                      style: AppTextStyles.bodyLg.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8.0), // Spacing: 8px grid
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: AppColors.inkFaint,
                        ),
                        const SizedBox(width: 8.0),
                        // Hierarchy: Secondary text 14px regular muted
                        Text(
                          '${DateFormat('HH:mm').format(stop.startTime)} – '
                              '${DateFormat('HH:mm').format(stop.endTime)}',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0), // Spacing: 8px grid
                    Row(
                      children: [
                        Icon(
                          _statusIcon(stop.stopStatus),
                          size: 16,
                          color: _statusColor(stop.stopStatus),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          _statusLabel(stop.stopStatus),
                          style: AppTextStyles.bodySm.copyWith(
                            color: _statusColor(stop.stopStatus),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (stop.place?.photoReference != null) ...[
                const SizedBox(width: 16.0),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: AppColors.accent.withOpacity(0.12),
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 16.0), // Spacing: 8px grid
              const Align(
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStop(ItineraryStop stop) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStopScreen(
          stop: stop,
          itineraryStartDate: _viewModel.itinerary?.startDate ??
              DateTime.now(),
          isReadOnly: _viewModel.isReadOnly,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _viewModel.load();
    }
  }

  Future<void> _openAddPlace(int dayIndex, DateTime dayDate) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCustomPlaceScreen(
          itineraryId: widget.itineraryId,
          dayIndex: dayIndex,
          dayDate: dayDate,
          explorationTime: _viewModel.itinerary?.explorationTime ?? 'Standard',
          travelPace: _viewModel.itinerary?.travelPace ?? 'Standard',
          interests: _viewModel.itinerary?.interests ?? const [],
        ),
      ),
    );

    if (changed == true && mounted) {
      await _viewModel.load();
    }
  }

  Future<void> _openAddBookmarks(int dayIndex) async {
    final selectedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddFromBookmarksScreen(),
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty && mounted) {
      // Bookmarks are loaded from a repository in a future step; for now
      // the screen returns an empty selection, so nothing is added.
      final selected = <Bookmark>[];
      final ok = await _viewModel.addBookmarkedPlaces(
        dayIndex: dayIndex,
        bookmarks: selected,
      );
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${selected.length} bookmark(s).'),
          ),
        );
        await _viewModel.load();
      }
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle;
      case 'SKIPPED':
        return Icons.block;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppColors.accent;
      case 'SKIPPED':
        return AppColors.inkFaint;
      default:
        return AppColors.inkSoft;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'COMPLETED':
        return 'Completed';
      case 'SKIPPED':
        return 'Skipped';
      default:
        return 'Planned';
    }
  }

  // ─── Sticky Bottom Bar ──────────────────────────────────────

  Widget _buildStickyBottomBar(BuildContext context) {
    // Past itineraries are read-only — no save/discard actions.
    if (!_viewModel.canCustomize) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 24.0,
            bottom: MediaQuery.of(context).padding.bottom + 24.0,
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
          left: 24.0,
          right: 24.0,
          top: 16.0,
          bottom: MediaQuery.of(context).padding.bottom + 16.0,
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
                onPressed: _viewModel.isSaving
                    ? null
                    : () => _discardChanges(context),
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
            const SizedBox(width: 12.0),
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
      // Reload from the repository to restore the persisted state.
      await _viewModel.load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes discarded.')),
      );
    }
  }
}