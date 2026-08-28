// lib/view/Itinerary/manage_itinerary/manage_edit_itinerary_screen.dart
//
// Day-editor screen: reached after tapping a specific plan day in
// ManageDisplayPlanScreen. Lets the traveler reorder, edit or add places
// to that day (only for ongoing itineraries; past ones are read-only).

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../viewmodel/ItineraryModel/manage_edit_itinerary_vm.dart';
import 'add_from_bookmark.dart';
import 'edit_stop_screen.dart';

class ManageEditItineraryScreen extends StatefulWidget {
  final String itineraryId;
  final int dayNumber;

  const ManageEditItineraryScreen({
    super.key,
    required this.itineraryId,
    required this.dayNumber,
  });

  @override
  State<ManageEditItineraryScreen> createState() =>
      _ManageEditItineraryScreenState();
}

class _ManageEditItineraryScreenState extends State<ManageEditItineraryScreen> {
  late ManageEditItineraryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ManageEditItineraryViewModel(
      itineraryId: widget.itineraryId,
      dayIndex: widget.dayNumber,
    );
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

        return Scaffold(
          backgroundColor: AppColors.bg,
          // ── Header ──
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              onPressed: () => _onBackPressed(context),
              padding: EdgeInsets.zero,
            ),
            title: Text(
              'Serene Traveler',
              style: AppTextStyles.pageTitle.copyWith(fontSize: 20),
            ),
            centerTitle: false,
            actions: [
              TextButton(
                onPressed: _viewModel.isSaving
                    ? null
                    : () => _onDonePressed(context),
                child: Text(
                  _viewModel.isSaving ? 'Saving…' : 'Done',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // ── Body ──
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // ── Day Header ──
                    _DayHeader(viewModel: _viewModel),
                    const SizedBox(height: 24),

                    // ── Map Preview ──
                    _MapPreview(dayNumber: widget.dayNumber),
                    const SizedBox(height: 24),

                    // ── Stops Section ──
                    _StopsSection(
                      items: _viewModel.displayStops,
                      expandedIndex: _viewModel.expandedIndex,
                      isReadOnly: _viewModel.isReadOnly,
                      onToggleExpand: (index) => _viewModel.toggleExpand(index),
                      onEditPlace: (index) => _onEditPlace(index),
                      onDeletePlace: (index) => _onDeletePlace(context, index),
                      onMorePlace: (index) => _onMoreOptions(index),
                      onAddPlace: _viewModel.canCustomize
                          ? () => _onAddPlace(context)
                          : null,
                    ),

                    const SizedBox(height: 120),
                  ],
                ),
              ),

              // ── FAB ──
              if (_viewModel.canCustomize)
                Positioned(
                  bottom: 100,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: () => _onAddPlace(context),
                    backgroundColor: AppColors.accent,
                    elevation: 4,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),

              // ── Bottom Bar ──
              _BottomBar(
                isReadOnly: _viewModel.isReadOnly,
                onPressed: () => _onReviewChanges(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Handlers ──────────────────────────────────────────────────────

  Future<void> _onBackPressed(BuildContext context) async {
    if (!_viewModel.hasChanges) {
      Navigator.maybePop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Unsaved changes to this day will be lost.',
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
    if (discard == true && mounted) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _onDonePressed(BuildContext context) async {
    final saved = await _viewModel.saveChanges();
    if (!mounted) return;
    if (saved) {
      Navigator.maybePop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_viewModel.error ?? 'Failed to save changes.')),
      );
    }
  }

  Future<void> _onEditPlace(int index) async {
    final item = _viewModel.displayStops[index];
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStopScreen(
          stop: item.stop,
          itineraryStartDate:
              _viewModel.itinerary?.startDate ?? DateTime.now(),
          isReadOnly: _viewModel.isReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _viewModel.refresh();
    }
  }

  Future<void> _onDeletePlace(BuildContext context, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove place?'),
        content: const Text(
          'This place will be removed from the day. The schedule and '
          'route will not be recalculated.',
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
      await _viewModel.deleteStop(index);
    }
  }

  void _onMoreOptions(int index) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _PlaceOptionsSheet(
        placeName: _viewModel.displayStops[index].place.name,
        isReadOnly: _viewModel.isReadOnly,
        onEdit: () {
          Navigator.pop(context);
          _onEditPlace(index);
        },
        onDelete: () {
          Navigator.pop(context);
          _onDeletePlace(context, index);
        },
      ),
    );
  }

  Future<void> _onAddPlace(BuildContext context) async {
    final selectedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddFromBookmarksScreen(
          userId: _viewModel.itinerary?.userId ?? '',
        ),
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty && mounted) {
      final added = await _viewModel.addBookmarkedPlaces(selectedIds);
      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added place(s).')),
        );
      }
    }
  }

  Future<void> _onReviewChanges(BuildContext context) async {
    final saved = await _viewModel.saveChanges();
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day changes saved.')),
      );
      Navigator.maybePop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_viewModel.error ?? 'Failed to save changes.')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DAY HEADER
// ═══════════════════════════════════════════════════════════════════════

class _DayHeader extends StatelessWidget {
  final ManageEditItineraryViewModel viewModel;

  const _DayHeader({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          viewModel.formattedDayHeader,
          style: AppTextStyles.pageTitle.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'Reorder, edit or add places to your day.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  MAP PREVIEW
// ═══════════════════════════════════════════════════════════════════════

class _MapPreview extends StatelessWidget {
  final int dayNumber;

  const _MapPreview({required this.dayNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Map Background (placeholder) ──
            Container(
              color: AppColors.surface2,
              child: CustomPaint(
                painter: _RoutePainter(),
              ),
            ),

            // ── Gradient overlay ──
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x33000000)],
                ),
              ),
            ),

            // ── Route label badge ──
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Day $dayNumber route',
                  style: AppTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder painter for route visualization.
/// Replace with actual Google Map widget.
class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final dotBorder = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Route line
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.4)
      ..lineTo(size.width * 0.45, size.height * 0.6)
      ..lineTo(size.width * 0.55, size.height * 0.3)
      ..lineTo(size.width * 0.85, size.height * 0.7);

    canvas.drawPath(path, paint);

    // Markers
    final markers = [
      Offset(size.width * 0.15, size.height * 0.4),
      Offset(size.width * 0.55, size.height * 0.3),
      Offset(size.width * 0.85, size.height * 0.7),
    ];

    for (final center in markers) {
      canvas.drawCircle(center, 8, dotBorder);
      canvas.drawCircle(center, 6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════
//  STOPS SECTION
// ═══════════════════════════════════════════════════════════════════════

class _StopsSection extends StatelessWidget {
  final List<DayStopItem> items;
  final int? expandedIndex;
  final bool isReadOnly;
  final ValueChanged<int> onToggleExpand;
  final ValueChanged<int> onEditPlace;
  final ValueChanged<int> onDeletePlace;
  final ValueChanged<int> onMorePlace;
  final VoidCallback? onAddPlace;

  const _StopsSection({
    required this.items,
    required this.expandedIndex,
    required this.isReadOnly,
    required this.onToggleExpand,
    required this.onEditPlace,
    required this.onDeletePlace,
    required this.onMorePlace,
    this.onAddPlace,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Label ──
        Text(
          'STOPS',
          style: AppTextStyles.sectionLabel,
        ),
        const SizedBox(height: 20),

        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No places on this day yet.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.inkFaint,
                ),
              ),
            ),
          ),

        // ── Timeline + Stop Cards ──
        Stack(
          children: [
            // ── Dashed vertical line ──
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 2,
                child: CustomPaint(
                  painter: _DashedLinePainter(
                    color: AppColors.moduleBorder,
                  ),
                ),
              ),
            ),

            // ── Stop items ──
            Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _StopItem(
                    index: i,
                    item: items[i],
                    isExpanded: expandedIndex == i,
                    onTap: () => onToggleExpand(i),
                    onEdit: () => onEditPlace(i),
                    onDelete: () => onDeletePlace(i),
                    onMore: () => onMorePlace(i),
                  ),
                  if (i < items.length - 1) const SizedBox(height: 16),
                ],

                // ── Add Place Button ──
                if (onAddPlace != null) ...[
                  const SizedBox(height: 24),
                  _AddPlaceButton(onTap: onAddPlace!),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SINGLE STOP ITEM
// ═══════════════════════════════════════════════════════════════════════

class _StopItem extends StatelessWidget {
  final int index;
  final DayStopItem item;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  const _StopItem({
    required this.index,
    required this.item,
    required this.isExpanded,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final number = index + 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Number Circle ──
        _StopCircle(number: number, isExpanded: isExpanded),

        const SizedBox(width: 16),

        // ── Content Card ──
        Expanded(
          child: GestureDetector(
            onTap: isExpanded ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: isExpanded
                  ? _ExpandedCard(
                item: item,
                onEdit: onEdit,
                onDelete: onDelete,
              )
                  : _CollapsedCard(
                item: item,
                onMore: onMore,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Timeline Circle ─────────────────────────────────────────────────

class _StopCircle extends StatelessWidget {
  final int number;
  final bool isExpanded;

  const _StopCircle({required this.number, required this.isExpanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isExpanded ? AppColors.accent : AppColors.surface2,
        border: isExpanded
            ? null
            : Border.all(color: AppColors.moduleBorder),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppColors.accent.withOpacity(0.2)
                : Colors.transparent,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: AppTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.w700,
            color: isExpanded ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

// ── Expanded Card ───────────────────────────────────────────────────

class _ExpandedCard extends StatelessWidget {
  final DayStopItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExpandedCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title + Action Buttons ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.place.name,
                      style: AppTextStyles.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.formattedTime,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  // Edit button
                  _ActionButton(
                    icon: Icons.edit_rounded,
                    backgroundColor: AppColors.surface2,
                    iconColor: AppColors.inkSoft,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 8),
                  // Delete button
                  _ActionButton(
                    icon: Icons.delete_rounded,
                    backgroundColor: AppColors.accentSoft,
                    iconColor: AppColors.accent,
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Address ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.place.address,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.inkSoft,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Visit Duration ──
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Text(
                'Suggested visit: ${item.visitDurationText}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),

          // ── Travel Info Bar ──
          if (item.travelFromPrevText != null ||
              item.travelToNextText != null) ...[
            const SizedBox(height: 20),
            _TravelInfoBar(item: item),
          ],
        ],
      ),
    );
  }
}

// ── Collapsed Card ──────────────────────────────────────────────────

class _CollapsedCard extends StatelessWidget {
  final DayStopItem item;
  final VoidCallback onMore;
  final VoidCallback onTap;

  const _CollapsedCard({
    required this.item,
    required this.onMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.place.name,
                    style: AppTextStyles.bodyLg.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.formattedTime,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onMore,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Button (Edit/Delete) ────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

// ── Travel Info Bar ────────────────────────────────────────────────

class _TravelInfoBar extends StatelessWidget {
  final DayStopItem item;
  const _TravelInfoBar({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // From previous
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_car_rounded,
                  size: 16,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.travelFromPrevText != null
                        ? 'From prev: ${item.travelFromPrevText}'
                        : 'Starting point',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.inkSoft,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // To next
          if (item.travelToNextText != null)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'To next: ${item.travelToNextText}',
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.inkSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ADD PLACE BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _AddPlaceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPlaceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          // Dashed circle with +
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.add,
              size: 20,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Add another place',
            style: AppTextStyles.button.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DASHED LINE PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 6.0;
    const gapHeight = 4.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + gapHeight;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════
//  BOTTOM BAR
// ═══════════════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  final bool isReadOnly;
  final VoidCallback onPressed;

  const _BottomBar({required this.isReadOnly, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bg.withOpacity(0.9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A004D40),
                offset: Offset(0, -4),
                blurRadius: 20,
              ),
            ],
          ),
          child: isReadOnly
              ? Text(
            'This itinerary is in the past and is read-only.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.inkFaint,
            ),
            textAlign: TextAlign.center,
          )
              : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              elevation: 4,
              shadowColor: AppColors.accent.withOpacity(0.3),
            ),
            child: Text(
              'Review Changes',
              style: AppTextStyles.button.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PLACE OPTIONS BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════

class _PlaceOptionsSheet extends StatelessWidget {
  final String placeName;
  final bool isReadOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlaceOptionsSheet({
    required this.placeName,
    required this.isReadOnly,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.moduleBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              placeName,
              style: AppTextStyles.bodyLg.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),

            // ── Edit option ──
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.ink),
              title: Text(
                'Edit place',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: onEdit,
            ),

            // ── Delete option ──
            if (!isReadOnly)
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: AppColors.accent,
                ),
                title: Text(
                  'Remove from itinerary',
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: onDelete,
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
