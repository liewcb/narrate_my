// lib/view/Itinerary/manage_itinerary/view_place_detail_screen.dart
import 'package:flutter/material.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/view_place_detail_vm.dart';

/// Read-only View Place Detail screen.
enum StopStatus {
  planned('Planned', Icons.calendar_today, AppColors.teal),
  inProgress('In Progress', Icons.play_circle_outline, AppColors.gold),
  completed('Completed', Icons.check_circle_outline, AppColors.green),
  skipped('Skipped', Icons.cancel_outlined, AppColors.inkFaint);

  final String label;
  final IconData icon;
  final Color color;

  const StopStatus(this.label, this.icon, this.color);

  static StopStatus fromBool(bool isStopped) =>
      isStopped ? StopStatus.completed : StopStatus.planned;
}

class ViewPlaceDetailScreen extends StatefulWidget {
  final String placeId;
  final Place? initialPlace;
  final bool showStatusToggle;
  final ValueChanged<bool>? onStatusChanged;
  final StopStatus initialStatus;
  final bool isReplacement;
  final Future<String?> Function(Place place)? onUsePlace;

  /// The itinerary stop being replaced (context only — the replacement
  /// itself is performed by [onUsePlace]). Null outside replacement mode.
  final String? replacingStopId;

  const ViewPlaceDetailScreen({
    Key? key,
    required this.placeId,
    this.initialPlace,
    this.showStatusToggle = false,
    this.onStatusChanged,
    this.initialStatus = StopStatus.planned,
    this.isReplacement = false,
    this.replacingStopId,
    this.onUsePlace,
  }) : super(key: key);

  @override
  State<ViewPlaceDetailScreen> createState() => _ViewPlaceDetailScreenState();
}

class _ViewPlaceDetailScreenState extends State<ViewPlaceDetailScreen> {
  late ViewPlaceDetailViewModel _viewModel;
  late StopStatus _currentStatus;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.initialStatus;
    _viewModel = ViewPlaceDetailViewModel(
      placeId: widget.placeId,
      initialPlace: widget.initialPlace,
      onStatusChanged: widget.onStatusChanged,
    );
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _updateStatus(StopStatus newStatus) {
    setState(() {
      _currentStatus = newStatus;
    });
    final isCompleted = newStatus == StopStatus.completed;
    if (_viewModel.isStopped != isCompleted) {
      _viewModel.toggleStopped();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Place Details',
          style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final place = _viewModel.place;
          if (place == null) {
            return _buildUnavailable();
          }

          return _buildContent(place);
        },
      ),
    );
  }

  Widget _buildUnavailable() {
    final message = _viewModel.error ?? 'Place information is unavailable.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Place place) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        _buildHero(place),
        const SizedBox(height: 20),

        if (widget.showStatusToggle) ...[
          _buildStatusToggle(),
          const SizedBox(height: 20),
        ],

        _buildTitleRow(place),
        const SizedBox(height: 14),
        if (place.placeAddress.isNotEmpty) ...[
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            text: place.placeAddress,
          ),
          const SizedBox(height: 10),
        ],
        // ❌ Removed type chips section
        _buildDetailsCard(place),
        const SizedBox(height: 16),
        // ❌ Removed opening hours card

        const SizedBox(height: 24),
        if (widget.isReplacement && widget.onUsePlace != null) ...[
          _buildUseThisPlaceButton(place),
          const SizedBox(height: 12),
        ],
        _buildBottomBackButton(),
      ],
    );
  }

  Widget _buildUseThisPlaceButton(Place place) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isConfirming ? null : () => _confirmReplacement(place),
        icon: _isConfirming
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        )
            : const Icon(Icons.check_circle_outline, size: 20),
        label: Text(
          _isConfirming ? 'Updating…' : 'Use This Place',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _confirmReplacement(Place place) async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      final problem = await widget.onUsePlace!(place);
      if (!mounted) return;
      if (problem == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Location updated successfully.')),
          );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(problem)));
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Widget _buildHero(Place place) {
    final imageUrl = _buildPhotoUrl(place.placePhotoRef);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: 180,
        width: double.infinity,
        color: AppColors.surface2,
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _HeroPlaceholder(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        )
            : const _HeroPlaceholder(),
      ),
    );
  }

  String? _buildPhotoUrl(String? photoRef, {int maxWidth = 400}) {
    if (photoRef == null || photoRef.isEmpty) return null;
    return 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=$maxWidth'
        '&photoreference=$photoRef'
        '&key=${ApiKeys.googleMapsApiKey}';
  }

  Widget _buildBottomBackButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink),
        label: const Text(
          'Back',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.moduleBorder),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusToggle() {
    final activeStatus = _viewModel.isStopped
        ? StopStatus.completed
        : _currentStatus;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(activeStatus.icon, color: activeStatus.color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mark as completed',
                      style: AppTextStyles.bodyLg.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      'Status: ${activeStatus.label}',
                      style: AppTextStyles.labelSm.copyWith(
                        color: activeStatus.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _viewModel.isStopped,
                onChanged: (_) {
                  _viewModel.toggleStopped();
                  setState(() {
                    _currentStatus = _viewModel.isStopped
                        ? StopStatus.completed
                        : StopStatus.planned;
                  });
                },
                activeColor: AppColors.green,
              ),
            ],
          ),
          const Divider(height: 16, color: AppColors.moduleBorder),
          InkWell(
            onTap: _showStatusPickerBottomSheet,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'More status options (In Progress, Skipped)',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStatusPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.moduleBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Update Stop Status',
                style: AppTextStyles.pageTitle.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...StopStatus.values.map((status) {
                final isSelected = status == _currentStatus;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.surface2 : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? status.color : AppColors.moduleBorder,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(status.icon, color: status.color),
                    title: Text(
                      status.label,
                      style: AppTextStyles.bodySm.copyWith(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: status.color)
                        : null,
                    onTap: () {
                      _updateStatus(status);
                      Navigator.pop(ctx);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitleRow(Place place) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            place.placeName,
            style: AppTextStyles.pageTitle,
          ),
        ),
        if (place.placeRating > 0) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.moduleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 16, color: AppColors.gold),
                const SizedBox(width: 4),
                Text(
                  place.placeRating.toStringAsFixed(1),
                  style: AppTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }

  // ─── Removed _buildTypeChips ───

  Widget _buildDetailsCard(Place place) {
    final items = <(IconData, String)>[
      if (place.placeCategory != null && place.placeCategory!.isNotEmpty)
        (Icons.category_outlined, place.placeCategory!),
      if (place.bestTimeSuggestion != null && place.bestTimeSuggestion!.isNotEmpty)
        (Icons.wb_sunny_outlined, 'Best time: ${place.bestTimeSuggestion}'),
      if (place.visitDurationMinutes != null)
        (Icons.timelapse_outlined,
        'Suggested visit: ${place.visitDurationMinutes} min'),
      if (place.placeTotalReviews != null && place.placeTotalReviews! > 0)
        (Icons.rate_review_outlined, '${place.placeTotalReviews} reviews'),
      if (place.placePriceLevel != null)
        (Icons.attach_money_outlined,
        'Price level: ${_priceLevelLabel(place.placePriceLevel!)}'),
      if (place.businessStatus != null && place.businessStatus!.isNotEmpty)
        (Icons.store_outlined, place.businessStatus!),
      if (place.placePhone != null && place.placePhone!.isNotEmpty)
        (Icons.phone_outlined, place.placePhone!),
      if (place.placeWebsite != null && place.placeWebsite!.isNotEmpty)
        (Icons.language_outlined, place.placeWebsite!),
      (Icons.map_outlined,
      '${place.placeLatitude.toStringAsFixed(5)}, '
          '${place.placeLongitude.toStringAsFixed(5)}'),
      // ❌ Removed Google ID line
      if (place.destinationId != null && place.destinationId!.isNotEmpty)
        (Icons.tour_outlined, 'Destination: ${place.destinationId}'),
      if (place.hotspotId != null && place.hotspotId!.isNotEmpty)
        (Icons.location_city_outlined, 'Hotspot: ${place.hotspotId}'),
    ];

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.moduleBorder),
        ),
        child: Text(
          'No additional details are available for this place.',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.inkFaint),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildInfoRow(icon: item.$1, text: item.$2),
          ),
        )
            .toList(),
      ),
    );
  }

  String _priceLevelLabel(int level) {
    switch (level) {
      case 0:
        return 'Free';
      case 1:
        return 'Inexpensive';
      case 2:
        return 'Moderate';
      case 3:
        return 'Expensive';
      case 4:
        return 'Very Expensive';
      default:
        return '$level';
    }
  }

// ❌ Removed _buildOpeningHoursCard
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.place_outlined, size: 56, color: AppColors.inkFaint),
    );
  }
}