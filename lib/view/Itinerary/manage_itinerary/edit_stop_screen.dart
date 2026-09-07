// lib/view/Itinerary/manage_itinerary/edit_stop_screen.dart
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/ai_assistant/global_ai_assistant.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/services/database_manager.dart';
import '../../../model/business_logic/itinerary_service/change_location_service.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../viewmodel/Itinerary/change_location_vm.dart';
import '../../../viewmodel/Itinerary/edit_stop_vm.dart';
import '../widgets/view_place_detail_screen.dart';

/// Edits the traveler's progress for a single stop.
///
/// The traveler may edit the scheduled START time (end time auto-derived
/// from the existing duration) and the progress status (Planned /
/// Completed / Skipped). Place, order, route and duration are never
/// modified.
class EditStopScreen extends StatefulWidget {
  final ItineraryStop stop;
  final DateTime itineraryStartDate;
  final bool isReadOnly;
  final String userId;

  const EditStopScreen({
    Key? key,
    required this.stop,
    required this.itineraryStartDate,
    this.isReadOnly = false,
    this.userId = '252f0924-192c-42fe-8643-881da7bbf285',
  }) : super(key: key);

  @override
  State<EditStopScreen> createState() => _EditStopScreenState();
}

class _EditStopScreenState extends State<EditStopScreen> {
  late EditStopViewModel _viewModel;
  late TextEditingController _skipReasonController;

  final Color _bg = AppColors.bg;
  final Color _surfaceCard = AppColors.surface;
  final Color _onSurface = AppColors.ink;
  final Color _textMuted = AppColors.inkFaint;
  final Color _terracotta = AppColors.accent;
  final Color _dangerText = AppColors.error;

  bool _hasChanges = false;
  bool _registeredInitialContext = false;

  Future<void> _handleBack() async {
    if (!_viewModel.hasUnsavedChanges) {
      Navigator.maybePop(context, _hasChanges);
      return;
    }
    final discard = await showConfirmationDialog(
      context: context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Discard them and leave?',
      confirmLabel: 'Discard',
      icon: Icons.warning_amber_rounded,
      iconBgColor: const Color(0xFFFDE8E8),
      iconColor: AppColors.error,
      confirmColor: AppColors.error,
    );
    if (discard == true && mounted) {
      Navigator.maybePop(context, false);
    }
  }

  @override
  void initState() {
    super.initState();
    _viewModel = EditStopViewModel(
      stop: widget.stop,
      itineraryStartDate: widget.itineraryStartDate,
      isReadOnly: widget.isReadOnly,
    );
    _skipReasonController =
        TextEditingController(text: widget.stop.skipReason ?? '');
    _viewModel.refreshTimeOptions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registeredInitialContext) return;
    _registeredInitialContext = true;
    final place = widget.stop.place;
    if (place != null) {
      context
          .read<GlobalAiAssistantController>()
          .selectPlace(place, source: 'itinerary');
    }
  }

  @override
  void dispose() {
    _skipReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bg,
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(context),
          body: RefreshIndicator(
            onRefresh: () => _viewModel.refreshTimeOptions(),
            color: AppColors.accent,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: MediaQuery.of(context).padding.top + 80,
                bottom: 48,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompactHero(),
                  const SizedBox(height: 24),
                  if (!_viewModel.isEditable) _buildLockedBanner(),
                  if (_viewModel.isEditable) ...[
                    _buildLocationSection(),
                    const SizedBox(height: 24),
                  ],
                  _buildTimeAndDuration(),
                  const SizedBox(height: 24),
                  _buildStopStatus(),
                  const SizedBox(height: 24),
                  _buildScheduleInfo(),
                  if (_viewModel.isSkipped) ...[
                    const SizedBox(height: 24),
                    _buildSkipReason(),
                  ],
                  if (_viewModel.error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(),
                  ],
                  const SizedBox(height: 32),
                  if (_viewModel.isEditable) _buildRemoveButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            backgroundColor: _bg.withOpacity(0.9),
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: IconButton(
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back, color: _onSurface),
                ),
                onPressed: _handleBack,
              ),
            ),
            title: Text(
              "Edit Stop",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: _onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Locked banner ───────────────────────────────────────────

  Widget _buildLockedBanner() {
    String message;
    if (_viewModel.isCompleted) {
      message = 'This stop has been marked as completed and cannot be modified.';
    } else if (_viewModel.isSkipped) {
      message = 'This stop has been marked as skipped and cannot be modified.';
    } else {
      message = 'This stop is locked and cannot be modified.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Compact Hero ─────────────────────────────────────────────

  Widget _buildCompactHero() {
    final place = _viewModel.stop.place;
    final photoUrl = place?.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
        '?maxwidth=400&photoreference=${place!.photoReference}'
        '&key=${ApiKeys.googleMapsApiKey}'
        : null;

    return GestureDetector(
      onTap: () => _openPlaceDetail(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: photoUrl != null
                  ? Image.network(
                photoUrl,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _photoPlaceholder(),
              )
                  : _photoPlaceholder(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.attractions,
                          size: 14,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (place?.category ?? 'STOP').toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place?.name ?? _viewModel.stop.placeId,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place?.address ?? 'Address unmapped',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPlaceDetail() async {
    final place = _viewModel.stop.place;
    if (place == null) {
      _showMessage(context, 'Place details are unavailable.');
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: place.placeId,
          initialPlace: place,
          showStatusToggle: false,
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.surface2,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.inkFaint,
      ),
    );
  }

  // ─── Location ─────────────────────────────────────────────

  Widget _buildLocationSection() {
    final place = _viewModel.stop.place;
    final address = place?.address;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "LOCATION",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place?.name ?? _viewModel.stop.placeId,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        if (address != null && address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _viewModel.isSaving ? null : _openLocationSearch,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Change Location'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openLocationSearch() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChangeLocationSheet(
        stop: _viewModel.stop,
        userId: widget.userId,
      ),
    );
    if (confirmed == true && mounted) {
      _hasChanges = true;
      setState(() {});
    }
  }

  // ─── Time & Duration ────────────────────────────────────────

  Widget _buildTimeAndDuration() {
    final timeFormat = DateFormat('hh:mm a');
    final editable = _viewModel.isEditable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "TIME",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStartTimeDropdown(timeFormat, !editable),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade100,
              ),
              const SizedBox(height: 12),
              _buildEndTimeDropdown(timeFormat, !editable),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStartTimeDropdown(DateFormat timeFormat, bool readOnly) {
    final options = _viewModel.availableStartTimes;
    final current = _viewModel.editedStartTime;
    final selected = options.contains(current)
        ? current
        : (options.isNotEmpty ? options.first : null);

    return Row(
      children: [
        const Icon(
          Icons.schedule,
          color: AppColors.inkFaint,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'START TIME',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _textMuted,
                ),
              ),
              const SizedBox(height: 4),
              if (readOnly)
                Text(
                  timeFormat.format(current),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: selected,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.inkFaint,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    items: [
                      for (final t in options)
                        DropdownMenuItem<DateTime>(
                          value: t,
                          child: Text(timeFormat.format(t)),
                        ),
                    ],
                    onChanged: _viewModel.isSaving
                        ? null
                        : (value) {
                      if (value != null) {
                        _onStartTimeSelected(value);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEndTimeDropdown(DateFormat timeFormat, bool readOnly) {
    final options = _viewModel.availableEndTimes;
    final current = _viewModel.editedEndTime;
    final selected = options.contains(current)
        ? current
        : (options.isNotEmpty ? options.first : null);

    return Row(
      children: [
        const Icon(
          Icons.arrow_forward,
          color: AppColors.inkFaint,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'END TIME',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: _textMuted,
                ),
              ),
              const SizedBox(height: 4),
              if (readOnly)
                Text(
                  timeFormat.format(current),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (options.isEmpty)
                const Text(
                  'No available end times',
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: selected,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.inkFaint,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    items: [
                      for (final t in options)
                        DropdownMenuItem<DateTime>(
                          value: t,
                          child: Text(timeFormat.format(t)),
                        ),
                    ],
                    onChanged: _viewModel.isSaving
                        ? null
                        : (value) {
                      if (value != null) {
                        _onEndTimeSelected(value);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onEndTimeSelected(DateTime picked) async {
    if (_viewModel.isSaving) return;
    final applied = await _viewModel.setEndTime(picked);
    if (!mounted) return;
    if (!applied) {
      _showMessage(
        context,
        'Unable to update end time: ${_viewModel.error ?? 'invalid end time.'}',
      );
      return;
    }

    final confirmed = await _confirmTimeChange(context);
    if (!mounted) return;
    if (confirmed != true) {
      _viewModel.resetTimeEdits();
      _showMessage(context, 'Time change cancelled.');
      return;
    }

    final saved = await _viewModel.saveTimeChanges();
    if (!mounted) return;
    if (saved) {
      _hasChanges = true;
      setState(() {});
      _showMessage(context, 'Stop time updated successfully.');
    } else {
      _showMessage(
        context,
        'Unable to update time: ${_viewModel.error ?? 'please try again.'}',
      );
    }
  }

  Future<void> _onStartTimeSelected(DateTime picked) async {
    if (_viewModel.isSaving) return;
    final applied = await _viewModel.setStartTime(picked);
    if (!mounted) return;
    if (!applied) {
      _showMessage(
        context,
        'Unable to update time: ${_viewModel.error ?? 'invalid start time.'}',
      );
      return;
    }

    final confirmed = await _confirmTimeChange(context);
    if (!mounted) return;
    if (confirmed != true) {
      _viewModel.resetTimeEdits();
      _showMessage(context, 'Time change cancelled.');
      return;
    }

    final saved = await _viewModel.saveTimeChanges();
    if (!mounted) return;
    if (saved) {
      _hasChanges = true;
      setState(() {});
      _showMessage(context, 'Stop time updated successfully.');
    } else {
      _showMessage(
        context,
        'Unable to update time: ${_viewModel.error ?? 'please try again.'}',
      );
    }
  }

  // ─── Stop Status ─────────────────────────────────────────────

  Widget _buildStopStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "STOP STATUS",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            children: [
              _buildStatusButton("Planned", Icons.schedule),
              const SizedBox(width: 4),
              _buildStatusButton("Completed", Icons.check),
              const SizedBox(width: 4),
              _buildStatusButton("Skipped", Icons.fast_forward),
            ],
          ),
        ),
        // ── Reset button (only when status is not PLANNED and today) ──
        if (_viewModel.canReset) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _viewModel.isSaving ? null : _resetStatus,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Reset to Planned'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusButton(String title, IconData icon) {
    final target = title.toUpperCase();
    final isSelected = _viewModel.status == target;
    final isCompletedSelected =
        target == 'COMPLETED' && _viewModel.isCompleted;

    return Expanded(
      child: GestureDetector(
        onTap: _viewModel.isSaving
            ? null
            : () => _onStatusTapped(context, target),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _terracotta : _bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCompletedSelected ? Icons.check_circle : icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : AppColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                isCompletedSelected ? "? Completed" : title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetStatus() async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Reset to Planned?',
      message: 'This will reset the stop status back to Planned and re-enable editing.',
      confirmLabel: 'Reset',
      icon: Icons.undo,
      iconBgColor: AppColors.surface2,
      iconColor: AppColors.accent,
      confirmColor: AppColors.accent,
    );
    if (confirmed != true) return;

    final success = await _viewModel.resetStatus();
    if (!mounted) return;
    if (success) {
      _hasChanges = true;
      setState(() {});
      _showMessage(context, 'Stop status reset to Planned.');
    } else {
      _showMessage(
        context,
        'Unable to reset status: ${_viewModel.error ?? 'please try again.'}',
      );
    }
  }

  Future<void> _onStatusTapped(BuildContext context, String target) async {
    // 1. Already Completed -> cannot re-complete.
    if (_viewModel.isCompleted && target == 'COMPLETED') {
      _showMessage(context, 'This stop is already completed.');
      return;
    }

    // 2. Direct Completed <-> Skipped is not supported.
    if ((_viewModel.isCompleted && target == 'SKIPPED') ||
        (_viewModel.isSkipped && target == 'COMPLETED')) {
      _showMessage(
        context,
        'You must go back to Planned first before changing to '
            '${target[0]}${target.substring(1).toLowerCase()}.',
      );
      return;
    }

    // 3. Future stop cannot be Completed yet.
    if (target == 'COMPLETED' && !_viewModel.canCompleteNow) {
      _showMessage(
        context,
        'This stop cannot be completed yet.\n'
            'Please wait until its scheduled time.',
      );
      return;
    }

    // 4. No-op if already the current status.
    if (_viewModel.status == target) {
      return;
    }

    // 5. Confirm the status change BEFORE persisting.
    final confirmed = await _confirmStatusChange(context, target);
    if (confirmed != true) return;

    final success = await _viewModel.updateStatus(
      target,
      skipReason: target == 'SKIPPED'
          ? _skipReasonController.text.trim()
          : null,
    );

    if (success) {
      _hasChanges = true;
      setState(() {});
      _showMessage(context, _statusSuccessMessage(target));
    } else {
      _showMessage(
        context,
        'Unable to update status: '
            '${_viewModel.error ?? 'please try again.'}',
      );
    }
  }

  String _statusSuccessMessage(String target) {
    switch (target) {
      case 'COMPLETED':
        return 'Stop marked as completed.';
      case 'SKIPPED':
        return 'Stop marked as skipped.';
      case 'PLANNED':
        return 'Stop changed back to planned.';
      default:
        return 'Stop status updated successfully.';
    }
  }

  Future<bool?> _confirmStatusChange(BuildContext context, String target) {
    String title;
    String message;
    String confirmLabel;
    IconData icon;
    switch (target) {
      case 'COMPLETED':
        title = 'Mark this stop as completed?';
        message = 'This will mark the stop as completed.';
        confirmLabel = 'Complete';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'SKIPPED':
        title = 'Skip this stop?';
        message = 'This will mark the stop as skipped.';
        confirmLabel = 'Skip';
        icon = Icons.fast_forward_rounded;
        break;
      case 'PLANNED':
        title = 'Change this stop back to Planned?';
        message = 'This will reset the current progress status.';
        confirmLabel = 'Reset';
        icon = Icons.schedule_rounded;
        break;
      default:
        title = 'Change stop status?';
        message = 'This will update the stop status.';
        confirmLabel = 'Confirm';
        icon = Icons.flag_rounded;
    }
    return showConfirmationDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      iconBgColor: AppColors.surface2,
      iconColor: AppColors.accent,
      confirmColor: AppColors.accent,
    );
  }

  // ─── Schedule Info ──────────────────────────────────────────

  Widget _buildScheduleInfo() {
    final stop = _viewModel.stop;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "SCHEDULE",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                'Day ${stop.dayIndex} • Stop ${stop.stopOrder}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                '${DateFormat('HH:mm').format(stop.startTime)} – '
                    '${DateFormat('HH:mm').format(stop.endTime)}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkipReason() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "SKIP REASON (OPTIONAL)",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: _textMuted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: TextField(
            controller: _skipReasonController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
              "e.g., Rainy weather, closed for maintenance, or ran out of time...",
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _viewModel.error!,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.error,
        ),
      ),
    );
  }

  Widget _buildRemoveButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _viewModel.isSaving
            ? null
            : () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove this stop?'),
              content: const Text(
                'This will remove the stop from the itinerary. '
                    'The affected schedule and route will be recalculated.',
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
            final ok = await _viewModel.deleteStop();
            if (!mounted) return;
            if (ok) {
              _showMessage(context, 'Stop removed from itinerary.');
              Navigator.pop(context, true);
            } else {
              _showMessage(
                context,
                'Unable to remove the stop: '
                    '${_viewModel.error ?? 'please try again.'}',
              );
            }
          }
        },
        icon: Icon(Icons.delete, size: 18, color: _dangerText),
        label: Text(
          "Remove from itinerary",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _dangerText,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (_viewModel.isSkipped) {
      final reasonSaved = await _viewModel.saveSkipReason(
        _skipReasonController.text.trim(),
      );
      if (!reasonSaved) {
        _showMessage(context, _viewModel.error ?? 'Unable to save.');
        return;
      }
      _hasChanges = true;
    }

    if (_viewModel.hasTimeChanges) {
      final confirmed = await _confirmTimeChange(context);
      if (confirmed != true) {
        return;
      }
      final timeSaved = await _viewModel.saveTimeChanges();
      if (!timeSaved) {
        _showMessage(context, _viewModel.error ?? 'Unable to update time.');
        return;
      }
      _hasChanges = true;
      _showMessage(context, 'Stop time updated successfully.');
    }

    Navigator.maybePop(context, _hasChanges);
  }

  Future<bool?> _confirmTimeChange(BuildContext context) {
    final timeFormat = DateFormat('hh:mm a');
    final from = '${timeFormat.format(_viewModel.stop.startTime)} – '
        '${timeFormat.format(_viewModel.stop.endTime)}';
    final to = '${timeFormat.format(_viewModel.editedStartTime)} – '
        '${timeFormat.format(_viewModel.editedEndTime)}';

    return showConfirmationDialog(
      context: context,
      title: 'Confirm Time Change?',
      message: 'Change this stop from\n$from\n\nto\n$to?\n\n'
          'This will update the scheduled time for this stop.',
      confirmLabel: 'Confirm',
      icon: Icons.schedule_rounded,
      iconBgColor: AppColors.surface2,
      iconColor: AppColors.accent,
      confirmColor: AppColors.accent,
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

// ─── ChangeLocationSheet (unchanged from original) ─────────────

class _ChangeLocationSheet extends StatefulWidget {
  final ItineraryStop stop;
  final String userId;

  const _ChangeLocationSheet({required this.stop, required this.userId});

  @override
  State<_ChangeLocationSheet> createState() => _ChangeLocationSheetState();
}

class _ChangeLocationSheetState extends State<_ChangeLocationSheet> {
  late final ChangeLocationViewModel _vm;
  final GoogleMapsService _mapsService = GoogleMapsService();
  final TextEditingController _queryController = TextEditingController();

  List<Place> _results = [];
  bool _isSearching = false;
  String? _searchError;

  List<Place> _bookmarks = [];
  bool _isLoadingBookmarks = true;
  String? _bookmarksError;

  @override
  void initState() {
    super.initState();
    _vm = ChangeLocationViewModel(stop: widget.stop);
    _vm.loadRecommendations();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    try {
      final repo = DatabaseManager().bookmarkRepository;
      final dtos = await repo.getBookmarksWithPlaces(widget.userId);
      if (mounted) {
        setState(() {
          _bookmarks = dtos.map((d) => d.place).toList();
          _isLoadingBookmarks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bookmarksError = 'Could not load bookmarks.';
          _isLoadingBookmarks = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _vm.dispose();
    _queryController.dispose();
    super.dispose();
  }


  // ✅ UPDATED: Accepts the suggestedDuration
  Future<void> _openPlaceDetail(Place place, {int? suggestedDuration}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: place.placeId,
          initialPlace: place,
          isReplacement: true,
          onUsePlace: (selected) async {
            // ✅ PASSES DURATION TO VIEWMODEL
            final result = await _vm.confirmReplacement(selected, suggestedDuration: suggestedDuration);
            return result.isSuccessful ? null : result.message;
          },
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
    } catch (e) {
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
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
                  prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint),
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
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.moduleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.moduleBorder),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      else if (_results.isNotEmpty)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _results.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final place = _results[index];
                              return _LocationResultTile(
                                place: place,
                                onTap: () => _openPlaceDetail(place),
                              );
                            },
                          )
                        else ...[
                            _buildRecommendationsSection(),
                            _buildBookmarksSection(),
                          ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationsSection() {
    return ListenableBuilder(
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
                  style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                ),
              ],
            ),
          );
        }

        if (_vm.problemMessage != null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _vm.problemMessage!,
                    style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          );
        }

        if (_vm.recommendations.isEmpty) return const SizedBox.shrink();

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
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _vm.recommendations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final rec = _vm.recommendations[index];
                return _RecommendationCard(
                  recommendation: rec,
                  // ✅ PASS AI DURATION DOWN TO ONTAP
                  onTap: () => _openPlaceDetail(rec.place, suggestedDuration: rec.suggestedDuration),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildBookmarksSection() {
    if (_isLoadingBookmarks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SAVED BOOKMARKS',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 10),
        if (_bookmarksError != null)
          Text(
            _bookmarksError!,
            style: const TextStyle(fontSize: 14, color: AppColors.inkFaint, fontStyle: FontStyle.italic),
          )
        else if (_bookmarks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text(
              'No bookmarks saved yet. Search above to find places!',
              style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _bookmarks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final place = _bookmarks[index];
                return _LocationResultTile(
                  place: place,
                  onTap: () => _openPlaceDetail(place),
                );
              },
            ),
          ),
      ],
    );
  }
}

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
                        const Icon(Icons.star,
                            size: 14, color: AppColors.gold),
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
                      // ✅ ADDED: Display the AI suggested duration in the UI!
                      Text(
                        '${recommendation.distanceText} • ${recommendation.suggestedDuration} min',
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

class _LocationResultTile extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;

  const _LocationResultTile({required this.place, required this.onTap});

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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.moduleBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
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