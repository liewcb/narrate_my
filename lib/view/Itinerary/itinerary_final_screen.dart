import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/trip_draft.dart';
import '../../viewmodel/Itinerary/itinerary_final_vm.dart';
import 'add_place_screen.dart';
import 'edit_itinerary_screen.dart';
import 'my_itineraries_screen.dart';
import 'widgets/view_place_detail_screen.dart';

class ItineraryFinalScreen extends StatefulWidget {
  final ItineraryResult result;
  final String title;
  final String? itineraryId;
  final String explorationTime;
  final List<String> mustVisitPlaceIds;
  final DateTime tripStartDate;
  final Future<void> Function()? onRegenerate;
  final Future<ItineraryResult> Function()? onRegenerateAlternatives;
  final String userId;
  final TripDraft? draft;

  const ItineraryFinalScreen({
    super.key,
    required this.result,
    required this.title,
    this.itineraryId,
    this.explorationTime = 'Standard',
    this.mustVisitPlaceIds = const [],
    required this.tripStartDate,
    this.onRegenerate,
    this.onRegenerateAlternatives,
    this.userId = '252f0924-192c-42fe-8643-881da7bbf285',
    this.draft,
  });

  @override
  State<ItineraryFinalScreen> createState() => _ItineraryFinalScreenState();
}

class _ItineraryFinalScreenState extends State<ItineraryFinalScreen> {
  late ItineraryFinalViewModel _vm;
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _dayKeys;

  @override
  void initState() {
    super.initState();
    _vm = ItineraryFinalViewModel(
      result: widget.result,
      title: widget.title,
      itineraryId: widget.itineraryId,
      explorationTime: widget.explorationTime,
      mustVisitPlaceIds: widget.mustVisitPlaceIds,
      tripStartDate: widget.tripStartDate,
      regenerateRequest: widget.onRegenerate,
      regenerateAlternatives: widget.onRegenerateAlternatives,
      userId: widget.userId,
      draft: widget.draft,
    );
    final days = _vm.days;
    _dayKeys = List.generate(days.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _vm.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Prompts user with a confirmation dialog before discarding
  Future<void> _handleDiscard() async {
    final shouldDiscard = await showConfirmationDialog(
      context: context,
      title: 'Discard Itinerary?',
      message: 'Are you sure you want to discard this generated plan? Any unsaved progress will be lost.',
      confirmLabel: 'Discard',
      cancelLabel: 'Cancel',
      confirmColor: AppColors.error,
      icon: Icons.warning_amber_rounded,
      iconBgColor: AppColors.error,
      iconColor: AppColors.error,
    );

    if (shouldDiscard == true && mounted) {
      await _vm.clearDraft();
      // Pop the screen
      Navigator.pop(context);
    }
  }

  /// Persist the itinerary via the ViewModel, then navigate to the saved
  /// itinerary list on success.
  Future<void> _handleSave() async {
    debugPrint('[FINAL SAVE] Button pressed');
    debugPrint('[FINAL SAVE] canSave=${_vm.canSave}, '
        'isSaving=${_vm.isSaving}, itineraryId=${_vm.itineraryId}');

    if (!_vm.canSave) {
      debugPrint('[FINAL SAVE] Cannot save: itinerary is not valid or empty.');
      return;
    }

    debugPrint('[FINAL SAVE] Calling ViewModel.save()');
    final saved = await _vm.save();
    debugPrint('[FINAL SAVE] ViewModel.save() completed. saved=$saved, '
        'isSaved=${_vm.isSaved}');

    if (!mounted) return;

    if (saved) {
      debugPrint('[FINAL SAVE] Save succeeded. Clearing draft and navigating.');
      await _vm.clearDraft();

      debugPrint('[FINAL SAVE] Navigation started');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MyItinerariesScreen(),
        ),
      );
      debugPrint('[FINAL SAVE] Navigation completed');
    } else {
      // Show the saveMessage to the user if available
      final msg = _vm.saveMessage ?? 'Failed to save itinerary. Please try again.';
      debugPrint('[FINAL SAVE] Save did not succeed; staying on final screen. '
          'saveMessage=$msg');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            final days = _vm.days;
            if (_dayKeys.length != days.length) {
              _dayKeys.length = days.length;
            }

            // ── Empty / error state ──────────────────────────────
            if (days.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, size: 64, color: AppColors.inkFaint),
                    const SizedBox(height: 16),
                    const Text(
                      'Something went wrong',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Unable to display the generated itinerary.',
                      style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                    ),
                    if (_vm.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _vm.errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppColors.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.surface,
                      ),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              );
            }

            // ── Loading state ──────────────────────────────────────
            if (_vm.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            // ── Main content ────────────────────────────────────────
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: _HeroSection(
                    title: _vm.title,
                    dateRange: _vm.dateRange,
                    places: '${_vm.totalStops}',
                    days: '${days.length}',
                    imageUrl: _vm.heroImageUrl,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _StatsBar(
                    places: _vm.totalStops,
                    transit: '${_vm.totalTravelTime.inHours}h',
                    cities: _vm.cityCount,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DayPillsDelegate(
                    days: days,
                    selectedIndex: _vm.selectedDayIndex,
                    onDaySelected: (index) {
                      _vm.selectDay(index);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final key = _dayKeys[index];
                        if (key.currentContext != null) {
                          Scrollable.ensureVisible(
                            key.currentContext!,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                      });
                    },
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final day = days[index];
                      return Container(
                        key: _dayKeys[index],
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: _DayCard(
                          day: day,
                          isSelected: index == _vm.selectedDayIndex,
                        onAddPlace: () async {
                          final days = _vm.result.scheduledDays;
                          if (days == null || index >= days.length) return;
                          final updated =
                              await Navigator.push<ScheduledDay>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddPlaceScreen(
                                itineraryId: _vm.itineraryId ?? '',
                                dayIndex: index,
                                explorationTime: _vm.explorationTime,
                                workingDay: days[index],
                                itineraryUsedPlaceIds: _vm.allPlaceIds,
                                dayDate: days[index].date,
                                transportMode:
                                    _vm.draft?.transportation ?? 'walking',
                                travelPace: _vm.draft?.pace ?? 'Standard',
                                interests:
                                    _vm.draft?.interests.toList() ?? const [],
                                mustVisitPlaceIds: _vm.mustVisitPlaceIds,
                                destinationCenter:
                                    _vm.destinationCenterForDay(index),
                              ),
                            ),
                          );
                          if (updated != null && mounted) {
                            // Replace ONLY the selected day in the working
                            // preview; every other day is preserved.
                            _vm.applyDayUpdate(index, updated);
                          }
                        },
                          onEditDay: () {
                            Navigator.push<ItineraryResult>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditItineraryScreen(
                                  result: _vm.result,
                                  title: _vm.title,
                                  dayNumber: day.dayNumber,
                                  tripStartDate: _vm.tripStartDate,
                                  explorationTime: _vm.explorationTime,
                                  mustVisitPlaceIds: _vm.mustVisitPlaceIds,
                                  transportMode: _vm.draft?.transportation ??
                                      'walking',
                                  interests:
                                      _vm.draft?.interests.toList() ??
                                          const [],
                                ),
                              ),
                            ).then((updated) {
                              if (updated != null && mounted) {
                                _vm.updateResult(updated);
                              }
                            });
                          },
                        ),
                      );
                    },
                    childCount: days.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            );
          },
        ),
        bottomNavigationBar: _BottomActions(
          onDiscard: _handleDiscard,
          onRegenerate: _vm.canRegenerate ? () => _vm.regenerate() : null,
          isRegenerating: _vm.isRegenerating,
          onSave: _vm.canSave ? () => _handleSave() : null,
          isSaving: _vm.isSaveInProgress,
          saveMessage: _vm.saveMessage,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _HeroSection extends StatefulWidget {
  final String title;
  final String dateRange;
  final String places;
  final String days;
  final String? imageUrl;

  const _HeroSection({
    required this.title,
    required this.dateRange,
    required this.places,
    required this.days,
    this.imageUrl,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  bool _isLoading = true;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // If imageUrl is null or empty, show placeholder immediately
          if (widget.imageUrl == null || widget.imageUrl!.isEmpty)
            _placeholder()
          else
            _buildImageWithLoading(),
          // Gradient overlay (unchanged)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),
          // Title and badges (unchanged)
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge('Editable', Colors.white.withOpacity(0.2), Colors.white),
                    const SizedBox(width: 8),
                    _badge('${widget.days} Days', AppColors.accent, Colors.white),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
                if (widget.dateRange.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.dateRange} • ${widget.places} places',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWithLoading() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Image
        Image.network(
          widget.imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              // Image loaded
              _isLoading = false;
              return child;
            }
            // Still loading
            return _loadingPlaceholder();
          },
          errorBuilder: (context, error, stackTrace) {
            _hasError = true;
            _isLoading = false;
            return _placeholder();
          },
        ),
        // Show loading spinner if still loading
        if (_isLoading)
          Center(
            child: CircularProgressIndicator(
              color: Colors.white.withOpacity(0.8),
              strokeWidth: 2,
            ),
          ),
      ],
    );
  }

  Widget _loadingPlaceholder() {
    return Container(
      color: AppColors.surface2,
      child: const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surface2,
      child: const Center(
        child: Icon(Icons.map_outlined, size: 80, color: AppColors.inkFaint),
      ),
    );
  }

  Widget _badge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: textColor,
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int places;
  final String transit;
  final int cities;

  const _StatsBar({required this.places, required this.transit, required this.cities});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(color: AppShadows.card, offset: Offset(0, 8), blurRadius: 24),
        ],
      ),
      child: Row(
        children: [
          _statItem('$places', 'Places'),
          Container(width: 1, height: 32, color: AppColors.moduleBorder),
          _statItem(transit, 'Transit'),
          Container(width: 1, height: 32, color: AppColors.moduleBorder),
          _statItem('$cities', 'Cities'),
        ],
      ),
    );
  }

  Widget _statItem(String number, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            number,
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayPillsDelegate extends SliverPersistentHeaderDelegate {
  final List<DayData> days;
  final int selectedIndex;
  final ValueChanged<int> onDaySelected;

  _DayPillsDelegate({
    required this.days,
    required this.selectedIndex,
    required this.onDaySelected,
  });

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: minExtent,
      child: Container(
        color: AppColors.bg.withOpacity(0.9),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(days.length, (index) {
              final day = days[index];
              final isSelected = index == selectedIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onDaySelected(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.moduleBorder,
                      ),
                    ),
                    child: Text(
                      'Day ${day.dayNumber}${index == 0 ? ' • ${day.date}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? AppColors.surface : AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

class _DayCard extends StatelessWidget {
  final DayData day;
  final bool isSelected;
  final VoidCallback onAddPlace;
  final VoidCallback onEditDay;

  const _DayCard({
    required this.day,
    required this.isSelected,
    required this.onAddPlace,
    required this.onEditDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.moduleBorder.withOpacity(0.6),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: AppShadows.card, offset: const Offset(0, 4), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Day ${day.dayNumber}',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Selected',
                              style: TextStyle(fontSize: 10, color: AppColors.surface, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      day.date,
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                    if (day.timeRange != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${day.totalStops} stops • ${day.timeRange}',
                        style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                GestureDetector(
                  onTap: onEditDay,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.edit, color: AppColors.ink, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Stops
          ..._buildStops(),

          // Add button
          if (isSelected) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAddPlace,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.moduleBorder, width: 1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 16, color: AppColors.inkFaint),
                    const SizedBox(width: 6),
                    Text(
                      'Add a place to Day ${day.dayNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildStops() {
    final List<Widget> widgets = [];
    for (int i = 0; i < day.stops.length; i++) {
      final stop = day.stops[i];
      widgets.add(
        _StopItem(
          stop: stop,
          isFirst: i == 0,
          isLast: i == day.stops.length - 1,
          isActive: day.isSelected,
        ),
      );
      if (i < day.stops.length - 1) {
        final transitText = stop.transitTime ?? '';
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.directions_car, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Text(
                  transitText.isNotEmpty ? transitText : 'travel',
                  style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _StopItem extends StatelessWidget {
  final StopData stop;
  final bool isFirst;
  final bool isLast;
  final bool isActive;

  const _StopItem({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFirst ? AppColors.primary : AppColors.moduleBorder,
                border: Border.all(color: isFirst ? Colors.transparent : AppColors.surface, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: AppColors.moduleBorder,
              ),
          ],
        ),
        const SizedBox(width: 12),

        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${stop.time} • ${stop.duration}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isFirst ? AppColors.primary : AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),

              // Card
              InkWell(
                onTap: () => _openPlaceDetail(context),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isFirst ? AppColors.surface2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: isFirst ? null : Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
                  ),
                  child: Row(
                    children: [
                      if (stop.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            stop.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackImage(),
                          ),
                        )
                      else
                        _fallbackImage(),
                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stop.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              stop.type,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isActive)
                        Icon(Icons.drag_indicator, color: AppColors.inkFaint, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the existing ViewPlaceDetailScreen for this stop's place.
  ///
  /// Uses the current stop's actual Google place ID and the already-joined
  /// [Place] (no new Google Places search, no direct Supabase access).
  void _openPlaceDetail(BuildContext context) {
    if (stop.placeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Place details are unavailable.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: stop.placeId,
          initialPlace: stop.place,
          showStatusToggle: false,
        ),
      ),
    );
  }

  Widget _fallbackImage() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Text('📍', style: TextStyle(fontSize: 24))),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final VoidCallback onDiscard;
  final VoidCallback? onRegenerate;
  final VoidCallback? onSave;
  final bool isRegenerating;
  final bool isSaving;
  final String? saveMessage;

  const _BottomActions({
    required this.onDiscard,
    this.onRegenerate,
    this.onSave,
    this.isRegenerating = false,
    this.isSaving = false,
    this.saveMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.moduleBorder.withOpacity(0.6))),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            offset: Offset(0, -4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDiscard,
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                  label: const Text(
                    'Discard',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: (onRegenerate == null || isRegenerating) ? null : onRegenerate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: BorderSide(color: AppColors.moduleBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isRegenerating) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ] else ...[
                        const Icon(Icons.refresh, size: 16, color: AppColors.ink),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        isRegenerating ? 'Generating...' : 'Regenerate',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (saveMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                saveMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: isSaving ? AppColors.inkFaint : AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (onSave == null || isSaving) ? null : onSave,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0x80FFFFFF),
                      ),
                    )
                  : const Icon(Icons.check_circle, size: 18, color: AppColors.surface),
              label: Text(
                isSaving ? 'Saving...' : 'Save Itinerary',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 4,
                shadowColor: AppColors.primary.withOpacity(0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}