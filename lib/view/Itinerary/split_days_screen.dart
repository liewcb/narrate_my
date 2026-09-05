import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// ──────────────────────────────────────────────────────────────
// Simple wrapper: Destination + mutable days
// ──────────────────────────────────────────────────────────────
class DestinationWithDays {
  final String id;
  final String name;
  final String imageUrl;
  int days; // mutable – user adjusts this

  DestinationWithDays({
    required this.id,
    required this.name,
    required this.imageUrl,
    required int initialDays,
  }) : days = initialDays;
}

// ──────────────────────────────────────────────────────────────
// The SplitDaysScreen UI
// ──────────────────────────────────────────────────────────────
class SplitDaysScreen extends StatefulWidget {
  final List<DestinationWithDays> destinations;
  final int totalPlannedDays;

  const SplitDaysScreen({
    Key? key,
    required this.destinations,
    required this.totalPlannedDays,
  }) : super(key: key);

  @override
  State<SplitDaysScreen> createState() => _SplitDaysScreenState();
}

class _SplitDaysScreenState extends State<SplitDaysScreen> {
  // ─── Color Palette (using tokens from app_theme.dart) ──────
  final List<Color> _colorPalette = [
    AppColors.green,      // teal-green
    AppColors.accent,     // terracotta
    AppColors.teal,       // deep teal
    AppColors.gold,       // gold
    AppColors.primary,    // brand green
    AppColors.accentDark, // dark terracotta
    AppColors.inkSoft,    // muted brown
  ];

  // ─── Map each destination ID to a color ──────────────────────
  late final Map<String, Color> _destinationColors;

  // ─── Design colours (using app_theme tokens) ────────────────
  final Color _bgColor = AppColors.bg;
  final Color _subtitleColor = AppColors.inkFaint;
  final Color _textColor = AppColors.ink;

  @override
  void initState() {
    super.initState();
    _destinationColors = _buildColorMap();
  }

  Map<String, Color> _buildColorMap() {
    final map = <String, Color>{};
    for (int i = 0; i < widget.destinations.length; i++) {
      final dest = widget.destinations[i];
      map[dest.id] = _colorPalette[i % _colorPalette.length];
    }
    return map;
  }

  Color _getColorForDestination(String id) {
    return _destinationColors[id] ?? _colorPalette.first;
  }

  // ─── Computed total allocated days ──────────────────────────
  int get _totalAllocated =>
      widget.destinations.fold(0, (sum, d) => sum + d.days);

  // ─── Update days for a specific destination ──────────────────
  void _updateDays(int index, int change) {
    setState(() {
      int newDays = widget.destinations[index].days + change;
      int totalOthers = 0;
      for (int i = 0; i < widget.destinations.length; i++) {
        if (i != index) totalOthers += widget.destinations[i].days;
      }
      if (newDays >= 0 && (totalOthers + newDays) <= widget.totalPlannedDays) {
        widget.destinations[index].days = newDays;
      }
    });
  }

  // ─── Build date range string ──────────────────────────────────
  String _buildDateRange(int index) {
    int startDay = 1;
    for (int i = 0; i < index; i++) {
      startDay += widget.destinations[i].days;
    }
    int endDay = startDay + widget.destinations[index].days - 1;
    if (widget.destinations[index].days == 0) return "No days allocated";
    return "Day $startDay – Day $endDay";
  }

  // ──────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                _buildSummaryCard(),
                const SizedBox(height: 32),
                Text(
                  "DESTINATIONS & SCHEDULE",
                  style: AppTextStyles.sectionLabel,
                ),
                const SizedBox(height: 16),
                // ─── Build cards dynamically ──────────────────
                for (int i = 0; i < widget.destinations.length; i++)
                  _buildDestinationCard(
                    index: i,
                    title: "${i + 1}. ${widget.destinations[i].name}",
                    dateRange: _buildDateRange(i),
                    days: widget.destinations[i].days,
                    imageUrl: widget.destinations[i].imageUrl,
                    color: _getColorForDestination(widget.destinations[i].id),
                    onAdd: () => _updateDays(i, 1),
                    onRemove: () => _updateDays(i, -1),
                  ),
              ],
            ),
          ),
          // ─── Sticky footer ──────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildStickyFooter(),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final primaryColor = widget.destinations.isNotEmpty
        ? _getColorForDestination(widget.destinations.first.id)
        : AppColors.primary;

    return AppBar(
      backgroundColor: _bgColor.withOpacity(0.9),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: primaryColor),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Text(
        "STEP 4 OF 5",
        style: AppTextStyles.labelSm.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: _subtitleColor,
        ),
      ),
      actions: const [SizedBox(width: 48)],
    );
  }

  // ─── Header ───────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "How would you like to split your days?",
          style: AppTextStyles.pageTitle.copyWith(
            fontFamily: 'Playfair Display',
            fontSize: 28,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "You have ${widget.totalPlannedDays} total days planned. "
              "Allocate how many days to spend in each destination.",
          style: AppTextStyles.bodySm.copyWith(
            color: _subtitleColor,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ─── Summary Card (progress bar + legend) ────────────────────
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card,
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Duration",
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$_totalAllocated / ${widget.totalPlannedDays} Days Allocated",
                  style: AppTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ─── Progress Bar ──────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (int i = 0; i < widget.destinations.length; i++)
                    if (widget.destinations[i].days > 0) ...[
                      Expanded(
                        flex: widget.destinations[i].days,
                        child: Container(
                          color: _getColorForDestination(widget.destinations[i].id),
                        ),
                      ),
                      if (i < widget.destinations.length - 1 &&
                          widget.destinations[i + 1].days > 0)
                        const SizedBox(width: 4),
                    ],
                  if (_totalAllocated < widget.totalPlannedDays) ...[
                    if (_totalAllocated > 0) const SizedBox(width: 4),
                    Expanded(
                      flex: widget.totalPlannedDays - _totalAllocated,
                      child: Container(color: AppColors.moduleBorder),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ─── Legend ────────────────────────────────────────
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (int i = 0; i < widget.destinations.length; i++)
                _buildLegendItem(
                  color: _getColorForDestination(widget.destinations[i].id),
                  label: "${widget.destinations[i].name} "
                      "(${widget.destinations[i].days}d)",
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.25),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: AppTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.w600,
            color: _textColor,
          ),
        ),
      ],
    );
  }

  // ─── Individual Destination Card ──────────────────────────────
  Widget _buildDestinationCard({
    required int index,
    required String title,
    required String dateRange,
    required int days,
    required String imageUrl,
    required Color color,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(
            color: AppShadows.card,
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          children: [
            // ─── Left colour strip ────────────────────────
            Container(
              width: 6,
              height: 112,
              color: color,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // ─── Image ──────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Container(
                              color: AppColors.bg,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: color.withOpacity(0.6),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // ─── Info + Stepper ──────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── Destination number + name ──
                          Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title.replaceFirst(RegExp(r'^[0-9]+\.\s*'), ''),
                                  style: AppTextStyles.bodyLg.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: _textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // ─── Date range ───────────────────
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  days > 0 ? dateRange : "No days allocated",
                                  style: AppTextStyles.labelSm.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ─── Day Stepper ──────────────────
                          Row(
                            children: [
                              _buildStepperBtn(
                                icon: Icons.remove,
                                color: color,
                                onTap: onRemove,
                              ),
                              const SizedBox(width: 10),
                              Container(
                                constraints: const BoxConstraints(minWidth: 64),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "$days ${days == 1 ? 'Day' : 'Days'}",
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.labelSm.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _buildStepperBtn(
                                icon: Icons.add,
                                color: color,
                                onTap: onAdd,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.35),
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color: color,
          ),
        ),
      ),
    );
  }

  // ─── Sticky Footer ────────────────────────────────────────────
  Widget _buildStickyFooter() {
    bool isComplete = _totalAllocated == widget.totalPlannedDays;
    Color accentColor = widget.destinations.isNotEmpty
        ? _getColorForDestination(widget.destinations.first.id)
        : AppColors.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _bgColor,
            _bgColor.withOpacity(0.9),
            _bgColor.withOpacity(0.0),
          ],
        ),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isComplete ? accentColor : AppColors.moduleBorder,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: isComplete ? 8 : 0,
          shadowColor: accentColor.withOpacity(0.5),
          textStyle: AppTextStyles.button,
        ),
        onPressed: isComplete
            ? () {
          // ─── Navigate to the next screen ─────────────
          // Navigator.push(context, ...);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All days allocated! ✅')),
          );
        }
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isComplete
                  ? "Continue to Trip Details"
                  : "Allocate all ${widget.totalPlannedDays} days",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isComplete ? Colors.white : AppColors.inkFaint,
              ),
            ),
            if (isComplete) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}