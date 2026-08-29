// lib/view/Itinerary/manage_itinerary/edit_stop_screen.dart
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../viewmodel/Itinerary/edit_stop_vm.dart';

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

  const EditStopScreen({
    Key? key,
    required this.stop,
    required this.itineraryStartDate,
    this.isReadOnly = false,
  }) : super(key: key);

  @override
  State<EditStopScreen> createState() => _EditStopScreenState();
}

class _EditStopScreenState extends State<EditStopScreen> {
  late EditStopViewModel _viewModel;
  late TextEditingController _skipReasonController;

  // Brand Colors mapped from your Tailwind config
  final Color _bg = AppColors.bg;
  final Color _surfaceCard = AppColors.surface;
  final Color _onSurface = AppColors.ink;
  final Color _textMuted = AppColors.inkFaint;
  final Color _terracotta = AppColors.accent;
  final Color _dangerText = AppColors.error;

  // Track whether any progress change was persisted, so the parent
  // screen can reload on return.
  bool _hasChanges = false;

  /// Back-button handler: if there are unsaved edits, ask whether to
  /// discard them before leaving; otherwise pop normally.
  Future<void> _handleBack() async {
    if (!_hasChanges && !_viewModel.hasUnsavedChanges) {
      Navigator.maybePop(context, false);
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
          body: SingleChildScrollView(
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
                if (!_viewModel.isReadOnly) _buildRemoveButton(),
              ],
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
            actions: [
              TextButton(
                onPressed: _viewModel.isSaving ? null : () => _save(context),
                child: Text(
                  "Save",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _terracotta,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHero() {
    final place = _viewModel.stop.place;
    final photoUrl = place?.photoReference != null
        ? 'https://maps.googleapis.com/maps/api/place/photo'
            '?maxwidth=400&photoreference=${place!.photoReference}'
            '&key=${ApiKeys.googleMapsApiKey}'
        : null;

    return Container(
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
          // Thumbnail Image
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

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Tag
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

                // Title
                Text(
                  place?.name ?? _viewModel.stop.placeId,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                  ),
                ),

                // Location
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
                  ],
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildTimeAndDuration() {
    final stop = _viewModel.stop;
    final timeFormat = DateFormat('HH:mm');
    final hours = stop.durationMinutes ~/ 60;
    final minutes = stop.durationMinutes % 60;
    final durationLabel = hours > 0 && minutes > 0
        ? '${hours}h ${minutes}m'
        : hours > 0
            ? '${hours}h'
            : '${minutes}m';

    final editedStart = _viewModel.editedStartTime;
    final editedEnd = _viewModel.editedEndTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            "TIME & DURATION",
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Start & End Time
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Editable Start Time
                      GestureDetector(
                        onTap: _viewModel.isReadOnly
                            ? null
                            : () => _pickStartTime(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              color: Colors.grey.shade400,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeFormat.format(editedStart),
                              style: TextStyle(
                                color: _terracotta,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!_viewModel.isReadOnly) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.edit,
                                color: Colors.grey.shade400,
                                size: 14,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        color: Colors.grey.shade300,
                        size: 16,
                      ),
                      // Read-only End Time (derived from start + duration)
                      Text(
                        timeFormat.format(editedEnd),
                        style: TextStyle(
                          color: _terracotta,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: VerticalDivider(
                    color: Colors.grey.shade100,
                    thickness: 1,
                  ),
                ),

                // Duration (unchanged)
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timelapse,
                            color: Colors.grey.shade400,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            durationLabel,
                            style: TextStyle(
                              color: _terracotta,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
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
    );
  }

  /// Opens the standard time picker and applies the selection to the
  /// ViewModel's temporary state (end time auto-derived from duration).
  Future<void> _pickStartTime(BuildContext context) async {
    final current = _viewModel.editedStartTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    final applied = _viewModel.setStartTime(DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
    ));
    if (!applied) {
      _showMessage(context, _viewModel.error ?? 'Invalid start time.');
    }
  }

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
    debugPrint('[EDIT STOP] Status change requested');
    debugPrint('[EDIT STOP] From: ${_viewModel.status}');
    debugPrint('[EDIT STOP] To: $target');

    final confirmed = await _confirmStatusChange(context, target);
    if (confirmed != true) return; // Status remains unchanged.

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
      _showMessage(context, _viewModel.error ?? 'Unable to update status.');
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
                'Day ${stop.dayIndex} � Stop ${stop.stopOrder}',
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
                '${DateFormat('HH:mm').format(stop.startTime)} � '
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
                      'The schedule and route will not be recalculated.',
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
                  if (ok && mounted) {
                    Navigator.pop(context, true);
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
    // 1. Persist the skip reason when the stop is skipped.
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

    // 2. Persist pending time change (with confirmation).
    if (_viewModel.hasTimeChanges) {
      debugPrint('[EDIT STOP] Time change requires confirmation');
      final confirmed = await _confirmTimeChange(context);
      if (confirmed != true) {
        // Time change cancelled — do not persist it.
        return;
      }
      debugPrint('[EDIT STOP] Time change confirmed');
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
    final timeFormat = DateFormat('HH:mm');
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
