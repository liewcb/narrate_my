import 'dart:async'; // Added for Timer debouncing
import 'dart:math';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/ai_assistant/global_ai_assistant.dart';
import '../../../core/config/api_keys.dart';
import '../../../core/config/itinerary_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/services/database_manager.dart';
import '../../../model/entities/itinerary.dart';
import '../../../model/entities/itinerary_stop.dart';
import '../../../model/entities/place.dart';
import '../../../model/repositories/adapters/itinerary/place_repository_adapter.dart';
import '../../../model/repositories/adapters/itinerary/itinerary_repository_adapter.dart';
import '../../../model/repositories/adapters/itinerary/itinerary_stop_repository_adapter.dart';
import '../../../model/business_logic/itinerary_service/itinerary_validator.dart';
import '../../../viewmodel/Itinerary/edit_stop_vm.dart';
import '../widgets/view_place_detail_screen.dart';

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
    // Day-aware context: loads THIS day's stops and builds the
    // full-day customization options for the dropdowns.
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
                onPressed: () => Navigator.pop(context),
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
        onConfirmReplacement: _applyLocationReplacement,
      ),
    );
    if (confirmed == true && mounted) {
      _hasChanges = true;
      setState(() {});
    }
  }

  /// Change-location flow: select → confirm → the EXISTING repository
  /// updates ONLY this itinerary_stops row's place_id. NO route or
  /// distance calculation happens before the save — location editing is
  /// direct record customization, not route optimization.
  Future<String?> _applyLocationReplacement(Place selected) async {
    if (!mounted) return 'Edit screen is no longer open.';

    final proceed = await showConfirmationDialog(
      context: context,
      title: 'Use ${selected.placeName}?',
      message: 'This place will replace the current stop\'s location.\n\n'
          'The stop keeps its time, duration and place in the day. '
          'No other stop will change.',
      confirmLabel: 'Use Location',
      icon: Icons.place_outlined,
      iconBgColor: AppColors.surface2,
      iconColor: AppColors.accent,
      confirmColor: AppColors.accent,
    );
    if (proceed != true) {
      debugPrint('[EDIT_STOP_LOCATION] Traveler cancelled — original place '
          'kept (no database change)');
      return 'Location change cancelled.';
    }

    final ok = await _viewModel.changePlace(selected);
    return ok ? null : (_viewModel.error ??
        'Unable to use this place. Your original stop was kept.');
  }

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
                color: isSelected ? Colors.white : AppColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                isCompletedSelected ? "Completed" : title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.inkSoft,
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
    if (_viewModel.isCompleted && target == 'COMPLETED') {
      _showMessage(context, 'This stop is already completed.');
      return;
    }

    if ((_viewModel.isCompleted && target == 'SKIPPED') ||
        (_viewModel.isSkipped && target == 'COMPLETED')) {
      _showMessage(
        context,
        'You must go back to Planned first before changing to '
            '${target[0]}${target.substring(1).toLowerCase()}.',
      );
      return;
    }

    if (target == 'COMPLETED' && !_viewModel.canCompleteNow) {
      _showMessage(
        context,
        'This stop cannot be completed yet.\n'
            'Please wait until its scheduled time.',
      );
      return;
    }

    if (_viewModel.status == target) {
      return;
    }

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
          'Your chosen time is saved exactly as you set it. No other '
          'stop will be moved.',
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

// ─── ChangeLocationSheet ──────────────────────────────────────────

class _ChangeLocationSheet extends StatefulWidget {
  final ItineraryStop stop;
  final String userId;

  final Future<String?> Function(Place selected) onConfirmReplacement;

  const _ChangeLocationSheet({
    required this.stop,
    required this.userId,
    required this.onConfirmReplacement,
  });

  @override
  State<_ChangeLocationSheet> createState() => _ChangeLocationSheetState();
}

class _ChangeLocationSheetState extends State<_ChangeLocationSheet> {
  final PlaceRepositoryAdapter _placeRepo = DatabaseManager().placeRepository;
  final ItineraryRepositoryImpl _itineraryRepo = DatabaseManager().itineraryRepository;
  final ItineraryStopRepositoryImpl _stopRepo = DatabaseManager().itineraryStopRepository;
  final ItineraryValidator _validator = ItineraryValidator();
  final TextEditingController _queryController = TextEditingController();

  Timer? _debounceTimer; // Debounce timer for live search

  // ── Current stop data ──
  late final double _currentLat;
  late final double _currentLng;
  late final String _currentPlaceId;
  late final DateTime _stopStartTime;

  // ── Itinerary & neighbor stops ──
  Itinerary? _itinerary;
  List<ItineraryStop>? _dayStops;
  int? _currentStopIndex;

  // ── Local state ──────────────────────────────────────────────
  List<Place> _searchResults = [];
  List<Place> _recommendations = [];
  bool _isSearching = false;
  bool _isRefreshing = false;
  bool _isLoadingRecommendations = true;
  String? _searchError;
  String? _recommendationsError;

  // ── Bookmarks ────────────────────────────────────────────────
  List<Place> _bookmarks = [];
  bool _isLoadingBookmarks = true;
  String? _bookmarksError;

  // ── Distance radius (km) for nearby recommendations ─────────
  static const double _nearbyRadiusKm = 10.0;

  static double _calculateDistance(
      double lat1, double lon1,
      double lat2, double lon2,
      ) {
    const double R = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  String _getTimeSlot(DateTime time) {
    final hour = time.hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  bool _isPlaceSuitableForTime(Place place) {
    final suggestion = place.bestTimeSuggestion;
    if (suggestion == null || suggestion.isEmpty) return true;
    final slot = _getTimeSlot(_stopStartTime);
    return suggestion.toLowerCase().contains(slot);
  }

  bool _isUsableDatabasePlace(Place place) {
    if (place.placeId.trim().isEmpty) return false;
    if (place.placeName.trim().isEmpty) return false;
    if (place.placeLatitude == 0 && place.placeLongitude == 0) return false;
    return true;
  }

  /// Candidate filtering:
  /// Passes `isSearch: true` during active manual search to ignore the
  /// 10km proximity boundary so all valid destination results are shown.
  List<Place> _applyCandidateFilters(
      List<Place> source,
      Set<String> seenIds, {
        bool isSearch = false,
      }) {
    final destinationId = widget.stop.destinationId;
    final kept = <Place>[];
    for (final place in source) {
      if (place.placeId.trim().isEmpty ||
          place.placeName.trim().isEmpty ||
          place.id.trim().isEmpty) {
        continue;
      }
      if (seenIds.contains(place.placeId)) continue;
      if (place.placeId == _currentPlaceId) continue;
      if (!_isUsableDatabasePlace(place)) continue;

      if (destinationId != null &&
          destinationId.isNotEmpty &&
          place.destinationId != null &&
          place.destinationId!.isNotEmpty &&
          place.destinationId != destinationId) {
        continue;
      }

      final distanceKm = _calculateDistance(
          _currentLat, _currentLng, place.latitude, place.longitude);

      // Do NOT filter out search results based on nearby radius when searching by text
      if (!isSearch && distanceKm > _nearbyRadiusKm) {
        continue;
      }

      seenIds.add(place.placeId);
      kept.add(place);
    }
    return kept;
  }

  Future<bool> _isPlaceValidForDay(Place candidate) async {
    if (_itinerary == null || _dayStops == null) return false;
    if (_currentStopIndex == null) return false;
    if (!_isUsableDatabasePlace(candidate)) return false;

    final itinerary = _itinerary!;
    final stops = _dayStops!;
    final index = _currentStopIndex!;

    final newStops = <ItineraryStop>[];
    for (int i = 0; i < stops.length; i++) {
      if (i == index) {
        final replacement = stops[i].copyWith(
          placeId: candidate.placeId,
          place: candidate,
        );
        newStops.add(replacement);
      } else {
        newStops.add(stops[i]);
      }
    }

    final dayDate = itinerary.startDate.add(Duration(days: stops[index].dayIndex - 1));
    final window = ItineraryConstants.explorationWindowFor(itinerary.explorationTime);
    final result = await _validator.validateResultingDay(
      dayStops: newStops,
      dayDate: dayDate,
      window: window,
      transportMode: itinerary.transportationMode,
      focusStop: stops[index],
      candidatePlace: candidate,
      travelPace: itinerary.travelPace,
      customizationMode: true,
    );
    return result.isValid;
  }

  Future<void> _loadItineraryData() async {
    try {
      final itinerary = await _itineraryRepo.getItinerary(widget.stop.itineraryId);
      final allStops = await _stopRepo.getStopsForItinerary(widget.stop.itineraryId);
      final dayStops = allStops
          .where((s) => s.dayIndex == widget.stop.dayIndex)
          .toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));

      final index = dayStops.indexWhere((s) => s.stopId == widget.stop.stopId);
      if (index == -1) {
        _recommendationsError = 'Stop not found in itinerary.';
        return;
      }

      final joined = <ItineraryStop>[];
      for (final stop in dayStops) {
        var place = stop.place;
        if (place == null) {
          try {
            place = await _placeRepo.getPlace(stop.placeId);
          } catch (e) {
            debugPrint('[ChangeLocationSheet] Place join failed: $e');
          }
        }
        joined.add(stop.copyWith(place: place));
      }

      setState(() {
        _itinerary = itinerary;
        _dayStops = joined;
        _currentStopIndex = index;
      });
    } catch (e) {
      setState(() {
        _recommendationsError = 'Could not load itinerary data.';
      });
    }
  }

  Future<void> _loadNearbyRecommendations() async {
    setState(() {
      _isLoadingRecommendations = true;
      _recommendationsError = null;
    });

    await _loadItineraryData();

    if (_itinerary == null || _dayStops == null || _currentStopIndex == null) {
      setState(() {
        _isLoadingRecommendations = false;
        _recommendationsError = 'Unable to load itinerary data.';
      });
      return;
    }

    try {
      final allPlaces = await _placeRepo.getAllPlaces();
      final candidates = _applyCandidateFilters(allPlaces, <String>{}, isSearch: false);

      final usable = <Place>[];
      for (final place in candidates) {
        if (await _isPlaceValidForDay(place)) {
          usable.add(place);
        }
      }

      usable.sort((a, b) {
        final suitA = _isPlaceSuitableForTime(a) ? 0 : 1;
        final suitB = _isPlaceSuitableForTime(b) ? 0 : 1;
        if (suitA != suitB) return suitA.compareTo(suitB);
        final distA = _calculateDistance(_currentLat, _currentLng, a.latitude, a.longitude);
        final distB = _calculateDistance(_currentLat, _currentLng, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      setState(() {
        _recommendations = usable.take(10).toList();
        _isLoadingRecommendations = false;
        if (_recommendations.isEmpty) {
          _recommendationsError = 'No available places found within $_nearbyRadiusKm km.';
        }
      });
    } catch (e) {
      setState(() {
        _recommendationsError = 'Could not load nearby places.';
        _isLoadingRecommendations = false;
      });
    }
  }

  Future<void> _loadNearbyBookmarks() async {
    try {
      final repo = DatabaseManager().bookmarkRepository;
      final dtos = await repo.getBookmarksWithPlaces(widget.userId);
      final allBookmarks = dtos.map((d) => d.place).toList();

      final candidates = _applyCandidateFilters(allBookmarks, <String>{}, isSearch: false);

      final usable = <Place>[];
      for (final place in candidates) {
        if (await _isPlaceValidForDay(place)) {
          usable.add(place);
        }
      }

      usable.sort((a, b) {
        final suitA = _isPlaceSuitableForTime(a) ? 0 : 1;
        final suitB = _isPlaceSuitableForTime(b) ? 0 : 1;
        if (suitA != suitB) return suitA.compareTo(suitB);
        final distA = _calculateDistance(_currentLat, _currentLng, a.latitude, a.longitude);
        final distB = _calculateDistance(_currentLat, _currentLng, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      if (mounted) {
        setState(() {
          _bookmarks = usable;
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

  /// Debounced Live Search Listener
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchLocalPlaces(trimmed);
    });
    setState(() {});
  }

  Future<void> _searchLocalPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      // Ensure itinerary context is loaded before validating candidate places
      if (_itinerary == null) {
        await _loadItineraryData();
      }

      final results = await _placeRepo.searchPlaces(trimmed);
      final candidates = _applyCandidateFilters(results, <String>{}, isSearch: true);

      final usable = <Place>[];
      for (final place in candidates) {
        if (await _isPlaceValidForDay(place)) {
          usable.add(place);
        }
      }

      usable.sort((a, b) {
        final suitA = _isPlaceSuitableForTime(a) ? 0 : 1;
        final suitB = _isPlaceSuitableForTime(b) ? 0 : 1;
        if (suitA != suitB) return suitA.compareTo(suitB);
        final distA = _calculateDistance(_currentLat, _currentLng, a.latitude, a.longitude);
        final distB = _calculateDistance(_currentLat, _currentLng, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      if (!mounted) return;
      setState(() {
        _searchResults = usable;
        if (usable.isEmpty) {
          _searchError = 'No available places found for "$trimmed".';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searchError = 'Could not search places. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _openPlaceDetail(Place place) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlaceDetailScreen(
          placeId: place.placeId,
          initialPlace: place,
          isReplacement: true,
          onUsePlace: widget.onConfirmReplacement,
        ),
      ),
    );
    if (changed == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _refreshCandidates() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _loadItineraryData();
      await _loadNearbyRecommendations();
      await _loadNearbyBookmarks();
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searchError = null;
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final place = widget.stop.place;
    _currentLat = place?.latitude ?? 0.0;
    _currentLng = place?.longitude ?? 0.0;
    _currentPlaceId = place?.placeId ?? '';
    _stopStartTime = widget.stop.startTime;

    _loadNearbyRecommendations();
    _loadNearbyBookmarks();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _queryController.dispose();
    super.dispose();
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Change Location',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh candidates',
                    icon: const Icon(Icons.refresh, color: AppColors.accent),
                    onPressed: _isRefreshing ? null : _refreshCandidates,
                  ),
                ],
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
                onSubmitted: _searchLocalPlaces,
                onChanged: _onSearchChanged, // Live search on keystroke
                decoration: InputDecoration(
                  hintText: 'Search restaurants, attractions...',
                  hintStyle: const TextStyle(color: AppColors.inkFaint),
                  prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint),
                  suffixIcon: _queryController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _queryController.clear();
                      _onSearchChanged('');
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
              ),
              const SizedBox(height: 16),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshCandidates,
                  color: AppColors.accent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                        else if (_searchResults.isNotEmpty)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _searchResults.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final place = _searchResults[index];
                                return _LocationResultTile(
                                  place: place,
                                  onTap: () => _openPlaceDetail(place),
                                );
                              },
                            )
                          else
                            _buildNearbySection(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNearbySection() {
    if (_isLoadingRecommendations) {
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
              'Finding nearby places...',
              style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
            ),
          ],
        ),
      );
    }

    if (_recommendationsError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _recommendationsError!,
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );
    }

    if (_recommendations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No available places nearby within $_nearbyRadiusKm km.',
          style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.access_time, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'BEST FOR ${_getTimeSlot(_stopStartTime).toUpperCase()} (available)',
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
          itemCount: _recommendations.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final place = _recommendations[index];
            final distance = _calculateDistance(
              _currentLat, _currentLng,
              place.latitude!, place.longitude!,
            );
            return _NearbyPlaceTile(
              place: place,
              distanceKm: distance,
              onTap: () => _openPlaceDetail(place),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildBookmarksSection(),
      ],
    );
  }

  Widget _buildBookmarksSection() {
    if (_isLoadingBookmarks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_bookmarksError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _bookmarksError!,
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );
    }

    if (_bookmarks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Text(
          'No available bookmarks within $_nearbyRadiusKm km.',
          style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NEARBY BOOKMARKS',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _bookmarks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final place = _bookmarks[index];
            final distance = _calculateDistance(
              _currentLat, _currentLng,
              place.latitude!, place.longitude!,
            );
            return _NearbyPlaceTile(
              place: place,
              distanceKm: distance,
              onTap: () => _openPlaceDetail(place),
            );
          },
        ),
      ],
    );
  }
}

class _NearbyPlaceTile extends StatelessWidget {
  final Place place;
  final double distanceKm;
  final VoidCallback onTap;

  const _NearbyPlaceTile({
    required this.place,
    required this.distanceKm,
    required this.onTap,
  });

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
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.place, color: AppColors.inkFaint),
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
                      if (place.placeRating != null && place.placeRating! > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 14, color: AppColors.gold),
                        const SizedBox(width: 2),
                        Text(
                          place.placeRating!.toStringAsFixed(1),
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
                            fontSize: 12,
                            color: AppColors.inkFaint,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.near_me, size: 12, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        distanceKm < 1
                            ? '${(distanceKm * 1000).round()} m away'
                            : '${distanceKm.toStringAsFixed(1)} km away',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.place, color: AppColors.inkFaint),
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
