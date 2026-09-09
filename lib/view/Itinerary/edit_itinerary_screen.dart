import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/config/api_keys.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../model/entities/place.dart';
import '../../viewmodel/Itinerary/edit_itinerary_vm.dart';
import './recommended_places_screen.dart';
import './widgets/change_location_picker_sheet.dart';
import './widgets/view_place_detail_screen.dart';

/// Edits a single day of the generated itinerary during preview/review.
class EditItineraryScreen extends StatefulWidget {
  final ItineraryResult result;
  final String title;
  final int dayNumber;
  final DateTime tripStartDate;
  final String explorationTime;
  final List<String> mustVisitPlaceIds;
  final String transportMode;
  final List<String> interests;

  const EditItineraryScreen({
    super.key,
    required this.result,
    required this.title,
    required this.dayNumber,
    required this.tripStartDate,
    required this.explorationTime,
    required this.mustVisitPlaceIds,
    this.transportMode = 'walking',
    this.interests = const [],
  });

  @override
  State<EditItineraryScreen> createState() => _EditItineraryScreenState();
}

class _EditItineraryScreenState extends State<EditItineraryScreen> {
  late EditItineraryViewModel _vm;
  bool _changesApplied = false;
  bool _allowPop = false;
  bool _dialogOpen = false;
  bool _removing = false;
  GoogleMapController? _mapController;

  late int _selectedDayIndex;
  late final int _totalDays;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _tabScrollController = ScrollController();
  late final List<GlobalKey> _tabKeys;

  @override
  void initState() {
    super.initState();
    _totalDays = widget.result.scheduledDays?.length ?? 0;
    _selectedDayIndex = _totalDays > 0
        ? (widget.dayNumber - 1).clamp(0, _totalDays - 1)
        : -1;
    _tabKeys = List.generate(_totalDays + 1, (_) => GlobalKey());
    _initViewModel();
  }

  void _initViewModel() {
    if (_selectedDayIndex >= 0) {
      _vm = EditItineraryViewModel(
        result: widget.result,
        dayIndex: _selectedDayIndex,
        tripStartDate: widget.tripStartDate,
        explorationTime: widget.explorationTime,
        mustVisitPlaceIds: widget.mustVisitPlaceIds,
        title: widget.title,
        transportMode: widget.transportMode,
      );
    }
    _changesApplied = false;
  }

  @override
  void dispose() {
    if (_selectedDayIndex >= 0) {
      _vm.dispose();
    }
    _scrollController.dispose();
    _tabScrollController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _selectDay(int index) async {
    if (index == _selectedDayIndex || _removing) return;
    if (!await _confirmDiscard() || !mounted) return;

    try {
      final oldVm = _selectedDayIndex >= 0 ? _vm : null;

      setState(() {
        _selectedDayIndex = index;
        if (index >= 0) {
          _vm = EditItineraryViewModel(
            result: widget.result,
            dayIndex: index,
            tripStartDate: widget.tripStartDate,
            explorationTime: widget.explorationTime,
            mustVisitPlaceIds: widget.mustVisitPlaceIds,
            title: widget.title,
            transportMode: widget.transportMode,
          );
        }
        _changesApplied = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldVm?.dispose();
        if (index >= 0) {
          _fitMapBounds();
        }
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        final tabKeyIndex = index == -1 ? 0 : index + 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerSelectedTab(tabKeyIndex);
        });
      });
    } catch (e) {
      debugPrint('[EditItineraryScreen] Day switch failed: $e');
    }
  }

  void _centerSelectedTab(int tabKeyIndex) {
    if (tabKeyIndex < 0 || tabKeyIndex >= _tabKeys.length) return;
    final tabContext = _tabKeys[tabKeyIndex].currentContext;
    if (tabContext == null) return;

    Scrollable.ensureVisible(
      tabContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (int i = 0; i < _vm.stops.length; i++) {
      final stop = _vm.stops[i];
      markers.add(
        Marker(
          markerId: MarkerId(stop.placeId),
          position: LatLng(stop.place.latitude, stop.place.longitude),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}: ${stop.name}',
            snippet: (stop.startTime.hour == 0 && stop.startTime.minute == 0 && stop.endTime.hour == 0 && stop.endTime.minute == 0)
                ? 'Unscheduled'
                : '${_fmt(stop.startTime)} – ${_fmt(stop.endTime)}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_vm.stops.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('itinerary_route'),
        points: _vm.stops
            .map((s) => LatLng(s.place.latitude, s.place.longitude))
            .toList(),
        color: AppColors.teal,
        width: 4,
      ),
    };
  }

  void _fitMapBounds() {
    if (_mapController == null || _vm.stops.isEmpty) return;
    if (_vm.stops.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(
            _vm.stops.first.place.latitude,
            _vm.stops.first.place.longitude,
          ),
          14,
        ),
      );
      return;
    }

    double minLat = _vm.stops.first.place.latitude;
    double maxLat = _vm.stops.first.place.latitude;
    double minLng = _vm.stops.first.place.longitude;
    double maxLng = _vm.stops.first.place.longitude;

    for (final stop in _vm.stops) {
      if (stop.place.latitude < minLat) minLat = stop.place.latitude;
      if (stop.place.latitude > maxLat) maxLat = stop.place.latitude;
      if (stop.place.longitude < minLng) minLng = stop.place.longitude;
      if (stop.place.longitude > maxLng) maxLng = stop.place.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48.0,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (_dialogOpen) return false;
    if (_selectedDayIndex < 0 || !_vm.hasChanges || _changesApplied) return true;
    _dialogOpen = true;
    try {
      return await showConfirmationDialog(
        context: context,
        title: 'Discard unsaved changes?',
        message: 'Your edits have not been saved. Tap Review & Save to keep them, or discard them to leave.',
        confirmLabel: 'Discard changes',
        cancelLabel: 'Keep editing',
        confirmColor: AppColors.error,
      ) == true;
    } finally {
      _dialogOpen = false;
    }
  }

  void _leaveEditor([ItineraryResult? result]) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  Future<void> _handleBack() async {
    if (_removing) return;
    if (await _confirmDiscard() && mounted) _leaveEditor();
  }

  void _reviewChanges() {
    if (_selectedDayIndex < 0 || _removing) return;

    final errors = _vm.validateStructural();
    if (errors.isNotEmpty) {
      _showProblem(_friendlyValidationError(errors.first));
      return;
    }
    _vm.applyChanges();
    if (_vm.appliedResult != null) {
      _changesApplied = true;
      _leaveEditor(_vm.appliedResult);
    }
  }

  void _showProblem(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          message,
          style: GoogleFonts.nunito(color: AppColors.surface),
        ),
        backgroundColor: AppColors.ink,
      ));
  }

  Future<void> _showAddPicker() async {
    final existingStops = _vm.stops
        .map(
          (s) => ExistingStopContext(
        place: s.place,
        startTime: s.startTime,
        endTime: s.endTime,
        durationMinutes: s.durationMinutes,
        travelFromPrevMinutes: s.travelFromPrevMinutes,
        isMustVisit: s.isMustVisit,
      ),
    )
        .toList();

    final usedIds = <String>{};
    for (final d in (widget.result.scheduledDays ?? const <ScheduledDay>[])) {
      for (final stop in d.stops) {
        usedIds.add(stop.attraction.place.placeId);
      }
    }

    Coordinates? dayCenter;
    if (_vm.stops.isNotEmpty) {
      double lat = 0, lng = 0;
      var n = 0;
      for (final s in _vm.stops) {
        final p = s.place;
        if (p.latitude == 0 && p.longitude == 0) continue;
        lat += p.latitude;
        lng += p.longitude;
        n++;
      }
      if (n > 0) dayCenter = Coordinates(latitude: lat / n, longitude: lng / n);
    }

    final result = await Navigator.push<RecommendedPlaceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendedPlacesScreen(
          dayNumber: _vm.dayNumber,
          dayDate: _vm.dayDate,
          existingStops: existingStops,
          usedPlaceIds: usedIds,
          interests: widget.interests,
          transportMode: widget.transportMode,
          explorationTime: widget.explorationTime,
          travelPace: 'Standard',
          destinationCenter: dayCenter,
        ),
      ),
    );
    if (!mounted || result == null) return;

    final ok = _vm.applyProposedDay(result.day);
    _fitMapBounds();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${result.addedPlaceName} added to Day ${_vm.dayNumber}.',
              style: GoogleFonts.nunito(color: AppColors.surface),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } else {
      _showProblem(_vm.error ?? 'This place cannot fit into Day ${_vm.dayNumber}.');
    }
  }

  Future<void> _showReplacePicker(int index) async {
    final lockedReason = _vm.stopLockedReason(index);
    if (lockedReason != null) {
      _showProblem(lockedReason);
      return;
    }

    final stop = _vm.stops[index];
    final scheduledIds = _vm.stops.map((s) => s.placeId).toSet();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8F5EF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => ChangeLocationPickerSheet(
        stop: ItineraryStop(
          stopId: index + 1,
          itineraryId: 'preview',
          placeId: stop.placeId,
          dayIndex: _vm.dayNumber,
          stopOrder: index + 1,
          startTime: stop.startTime,
          endTime: stop.endTime,
          durationMinutes: stop.durationMinutes,
          stopStatus: 'PLANNED',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          place: stop.place,
        ),
        scheduledPlaceIds: scheduledIds,
        tripDate: _vm.dayDate,
        interests: const [],
        explorationTime: widget.explorationTime,
        onUsePlace: (selected) async {
          final ok = _vm.replaceStop(index, selected);
          if (ok) {
            _fitMapBounds();
            return null;
          }
          return _vm.error ?? 'This place cannot fit into your remaining schedule.';
        },
      ),
    );

    if (confirmed == true && mounted) {
      _fitMapBounds();
    }
  }

  Future<void> _openPlaceDetails(EditableStop stop) async {
    await Navigator.push<void>(
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

  Future<void> _removeStop(int index) async {
    if (index < 0 || index >= _vm.stops.length) return;
    final stop = _vm.stops[index];

    if (stop.isMustVisit) {
      _showProblem('Cannot remove a must-visit place');
      return;
    }
    if (_vm.stops.length <= 1) {
      _showProblem('Cannot remove the last stop from a day');
      return;
    }

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Remove Place?',
      message: 'Are you sure you want to remove this place from Day ${_vm.dayNumber}?',
      confirmLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      final ok = await _vm.removeStopByPlaceId(stop.placeId);
      if (!mounted) return;
      if (ok) {
        _fitMapBounds();
      } else {
        _showProblem(_vm.error ?? 'Unable to remove this place. Please try again.');
      }
    } catch (_) {
      if (mounted) _showProblem('Unable to remove this place. Please try again.');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  // ─── User-Friendly Interactive Time Picker Sheet ───────────────

  Future<void> _pickTimeRange(int index) async {
    final stop = _vm.stops[index];
    TimeOfDay currentStart = TimeOfDay(hour: stop.startTime.hour, minute: stop.startTime.minute);
    TimeOfDay currentEnd = TimeOfDay(hour: stop.endTime.hour, minute: stop.endTime.minute);

    final selectedRange = await showModalBottomSheet<List<TimeOfDay>>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final startMins = currentStart.hour * 60 + currentStart.minute;
            final endMins = currentEnd.hour * 60 + currentEnd.minute;
            final diffMins = endMins - startMins;
            final isValid = diffMins > 0;

            final hours = diffMins ~/ 60;
            final mins = diffMins % 60;
            final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.inkFaint.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.cardPadding),
                    Text(
                      'Adjust Visit Schedule',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stop.name,
                      style: AppTextStyles.labelSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),

                    // Tap Cards for Native Time Picker
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: currentStart,
                              );
                              if (picked != null) {
                                setSheetState(() => currentStart = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.moduleBorder),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'START TIME',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    currentStart.format(context),
                                    style: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.componentGap),
                          child: Icon(Icons.arrow_forward_rounded, color: AppColors.inkFaint, size: 20),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: currentEnd,
                              );
                              if (picked != null) {
                                setSheetState(() => currentEnd = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.moduleBorder),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'END TIME',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    currentEnd.format(context),
                                    style: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.cardPadding),

                    // Realtime Calculated Duration Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.pillPaddingX,
                        vertical: AppSpacing.pillPaddingY,
                      ),
                      decoration: BoxDecoration(
                        color: isValid ? AppColors.teal.withOpacity(0.1) : AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isValid ? Icons.timer_outlined : Icons.error_outline_rounded,
                            size: 16,
                            color: isValid ? AppColors.teal : AppColors.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isValid ? 'Total duration: $durationStr' : 'End time must be after start time',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isValid ? AppColors.teal : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.componentGap),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isValid ? () => Navigator.pop(sheetContext, [currentStart, currentEnd]) : null,
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedRange != null && selectedRange.length == 2 && mounted) {
      final ok = _vm.setTimeRange(index, selectedRange[0], selectedRange[1]);
      if (ok) {
        _fitMapBounds();
        final conflict = _vm.getStopConflict(index);
        if (conflict != null) {
          _showProblem('Time updated. Conflict detected: $conflict');
        }
      } else {
        _showProblem(_vm.error ?? 'Unable to update time.');
      }
    }
  }

  // ─── Main Screen Build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selectedDayIndex >= 0 ? _vm : Listenable.merge([]),
      builder: (context, _) {
        return PopScope<ItineraryResult>(
          canPop: _allowPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _handleBack();
          },
          child: AbsorbPointer(
            absorbing: _removing,
            child: Scaffold(
          backgroundColor: const Color(0xFFF8F5EF),
          appBar: _buildAppBar(),
          body: _totalDays == 0
              ? Center(
            child: Text(
              'No itinerary days available.',
              style: AppTextStyles.bodyLg,
            ),
          )
              : Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenMargin,
                  vertical: AppSpacing.componentGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_removing) const LinearProgressIndicator(),
                    _buildCompactHero(), // ✅ Added compact hero section
                    const SizedBox(height: 16),
                    _buildDaySelector(),
                    const SizedBox(height: 12),
                    if (_selectedDayIndex >= 0) ...[
                      _buildHeader(),
                      const SizedBox(height: AppSpacing.cardPadding),
                      _buildMapPreview(),
                      const SizedBox(height: AppSpacing.cardPadding),
                      _buildStopsList(),
                    ] else ...[
                      _buildAllDaysOverview(),
                    ],
                    const SizedBox(height: 120),
                  ],
                ),
              ),
              if (_selectedDayIndex >= 0) ...[
                Positioned(bottom: 96, right: AppSpacing.screenMargin, child: _buildFloatingAddButton()),
                Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomButton()),
              ],
            ],
          ),
        ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF8F5EF),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.ink),
        onPressed: _handleBack,
      ),
      title: Text(
        'Edit Itinerary',
        style: AppTextStyles.pageTitle,
      ),
    );
  }

  // ─── Compact Hero Section ─────────────────────────────────────

  Widget _buildCompactHero() {
    final endDate = widget.tripStartDate.add(Duration(days: _totalDays > 0 ? _totalDays - 1 : 0));
    final now = DateTime.now();
    final nowDay = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(widget.tripStartDate.year, widget.tripStartDate.month, widget.tripStartDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);

    String statusLabel;
    Color bgColor;
    Color fgColor;
    IconData icon;

    if (endDay.isBefore(nowDay)) {
      bgColor = Colors.orange.shade100;
      fgColor = Colors.deepOrange.shade900;
      icon = Icons.history;
      statusLabel = 'Past';
    } else if (startDay.isAfter(nowDay)) {
      bgColor = Colors.yellow.shade400;
      fgColor = Colors.red.shade800;
      icon = Icons.event_available;
      statusLabel = 'Upcoming';
    } else {
      bgColor = Colors.green.shade600;
      fgColor = Colors.white;
      icon = Icons.play_circle_outline;
      statusLabel = 'Ongoing';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.title.isEmpty ? 'My Trip' : widget.title,
                style: GoogleFonts.nunito(
                  fontSize: 20, // Smaller than typical 24/28 pageTitle
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: fgColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: AppTextStyles.labelSm.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4.0),
        Text(
          '$_totalDays Days • ${DateFormat('d MMM').format(widget.tripStartDate)} – ${DateFormat('d MMM').format(endDate)}',
          style: GoogleFonts.nunito(
            fontSize: 13,
            color: AppColors.inkFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDaySelector() {
    if (_totalDays == 0) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: _totalDays + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.componentGap),
        itemBuilder: (context, index) {
          final isAllDays = index == 0;
          final dayIndex = index - 1;
          final isActive = isAllDays ? _selectedDayIndex == -1 : dayIndex == _selectedDayIndex;

          return GestureDetector(
            key: _tabKeys[index],
            onTap: () => _selectDay(isAllDays ? -1 : dayIndex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pillPaddingX,
                vertical: AppSpacing.pillPaddingY,
              ),
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent : AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Center(
                child: Text(
                  isAllDays ? 'All Days' : 'Day $index',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: isActive ? AppColors.bg : AppColors.ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final dateFmt = DateFormat('EEEE, d MMM yyyy');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day ${_vm.dayNumber} Schedule',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${_vm.stops.length} stops',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateFmt.format(_vm.dayDate),
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reorder, edit or add places to your day.',
            style: AppTextStyles.labelSm,
          ),
        ],
      ),
    );
  }

  Widget _buildAllDaysOverview() {
    final days = widget.result.scheduledDays ?? const <ScheduledDay>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.moduleBorder.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All Days Overview',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${days.length} Days Trip • Select any day to edit stops and reorder.',
                style: AppTextStyles.labelSm,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardPadding),
        _buildAllDaysMapPreview(),
        const SizedBox(height: AppSpacing.cardPadding),
        for (int i = 0; i < days.length; i++) ...[
          _buildAllDaysDayCard(i, days[i]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildAllDaysDayCard(int dayIndex, ScheduledDay day) {
    final dateFmt = DateFormat('d MMM');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.moduleBorder.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day ${dayIndex + 1} · ${dateFmt.format(day.date)}',
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => _selectDay(dayIndex),
                child: Text(
                  'Edit Day ${dayIndex + 1}',
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${day.stops.length} stops planned',
            style: GoogleFonts.nunito(fontSize: 13, color: AppColors.inkFaint),
          ),
          if (day.stops.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in day.stops.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.attraction.place.placeName,
                      style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (day.stops.length > 4)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${day.stops.length - 4} more',
                      style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllDaysMapPreview() {
    final allStops = <Place>[];
    final days = widget.result.scheduledDays ?? const <ScheduledDay>[];
    for (final d in days) {
      for (final s in d.stops) {
        if (s.attraction.place.latitude != 0 && s.attraction.place.longitude != 0) {
          allStops.add(s.attraction.place);
        }
      }
    }
    final initialPos = allStops.isNotEmpty
        ? LatLng(allStops.first.latitude, allStops.first.longitude)
        : const LatLng(3.1390, 101.6869);

    final markers = <Marker>{};
    for (int d = 0; d < days.length; d++) {
      final day = days[d];
      final hue = (d * 55.0) % 360.0;
      for (int i = 0; i < day.stops.length; i++) {
        final stop = day.stops[i];
        final p = stop.attraction.place;
        if (p.latitude == 0 && p.longitude == 0) continue;
        markers.add(
          Marker(
            markerId: MarkerId('all_${d}_${p.placeId}_$i'),
            position: LatLng(p.latitude, p.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(hue),
            infoWindow: InfoWindow(
              title: 'Day ${d + 1} • Stop ${i + 1}: ${p.placeName}',
            ),
          ),
        );
      }
    }

    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: GoogleMap(
          key: const ValueKey('map_all_days_overview'),
          initialCameraPosition: CameraPosition(target: initialPos, zoom: 11),
          markers: markers,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    final initialPos = _vm.stops.isNotEmpty
        ? LatLng(_vm.stops.first.place.latitude, _vm.stops.first.place.longitude)
        : const LatLng(3.1390, 101.6869);

    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: GoogleMap(
          key: ValueKey('map_$_selectedDayIndex'),
          initialCameraPosition: CameraPosition(target: initialPos, zoom: 11),
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          onMapCreated: (controller) {
            _mapController = controller;
            _fitMapBounds();
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  Widget _buildStopsList() {
    final stops = _vm.stops;
    final hasAnyConflict = stops.asMap().entries.any((e) => _vm.getStopConflict(e.key) != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STOPS',
              style: AppTextStyles.sectionLabel,
            ),
            if (hasAnyConflict)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5E5),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: const Color(0xFFE6C58B)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFE65100)),
                    const SizedBox(width: 4),
                    Text(
                      'Conflicts Detected',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8A5A18),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stops.length,
          onReorder: (oldIndex, newIndex) {
            _vm.reorder(oldIndex, newIndex);
            _fitMapBounds();
          },
          itemBuilder: (context, index) {
            final stop = stops[index];
            final conflict = _vm.getStopConflict(index);
            final isLast = index == stops.length - 1;
            return _StopItem(
              key: ValueKey('stop_${stop.placeId}_$index'),
              stop: stop,
              number: index + 1,
              isLast: isLast,
              conflict: conflict,
              onEditTimeRange: () => _pickTimeRange(index),
              onReplace: () => _showReplacePicker(index),
              onDelete: () => _removeStop(index),
              onOpenDetails: () => _openPlaceDetails(stop),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFloatingAddButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showAddPicker,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Add Place',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.screenMargin,
        right: AppSpacing.screenMargin,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: AppColors.moduleBorder.withOpacity(0.8),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          onPressed: _reviewChanges,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Review & Save Day ${_vm.dayNumber}',
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _friendlyValidationError(String msg) {
    return msg.contains('exploration time')
        ? 'Schedule exceeds available day time.'
        : msg;
  }
}

// ─── Modern Timeline Place Card Item ──────────────────────────

class _StopItem extends StatelessWidget {
  final EditableStop stop;
  final int number;
  final bool isLast;
  final String? conflict;
  final VoidCallback onEditTimeRange;
  final VoidCallback onReplace;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetails;

  const _StopItem({
    super.key,
    required this.stop,
    required this.number,
    this.isLast = false,
    this.conflict,
    required this.onEditTimeRange,
    required this.onReplace,
    required this.onDelete,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isUnscheduled = (stop.startTime.hour == 0 && stop.startTime.minute == 0 && stop.endTime.hour == 0 && stop.endTime.minute == 0);
    final startTimeStr = _fmt(stop.startTime);
    final endTimeStr = _fmt(stop.endTime);
    final rating = stop.place.rating;
    final category = _resolveCategoryLabel(stop.place);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          if (!isLast)
            Positioned(
              top: 32,
              bottom: 0,
              left: 15,
              child: Container(
                width: 2,
                color: AppColors.moduleBorder,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Timeline Node
              SizedBox(
                width: 32,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: stop.isMustVisit
                        ? const LinearGradient(
                            colors: [Color(0xFFE65100), Color(0xFFC0392B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: (stop.isMustVisit ? AppColors.accent : Colors.black)
                            .withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Right Card Content
              Expanded(
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: stop.isMustVisit
                        ? AppColors.accent.withOpacity(0.35)
                        : AppColors.moduleBorder.withOpacity(0.8),
                    width: stop.isMustVisit ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Tags & Drag Handle
                    Row(
                      children: [
                        _buildCategoryBadge(category),
                        if (rating > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA000)),
                                const SizedBox(width: 2),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF8D6E63),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        const Icon(Icons.drag_handle_rounded, color: AppColors.inkFaint, size: 20),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Place Image + Info (Clickable for details and full preview)
                    InkWell(
                      onTap: onOpenDetails,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 68,
                                height: 68,
                                child: Builder(
                                  builder: (context) {
                                    final imgUrl = (stop.place.placeImageUrl != null && stop.place.placeImageUrl!.isNotEmpty)
                                        ? stop.place.placeImageUrl!
                                        : (stop.place.placePhotoRef != null && stop.place.placePhotoRef!.isNotEmpty
                                            ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=${stop.place.placePhotoRef}&key=${ApiKeys.googleMapsApiKey}'
                                            : null);
                                    if (imgUrl != null && imgUrl.isNotEmpty) {
                                      return Image.network(
                                        imgUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.surface2,
                                          child: const Icon(Icons.photo_outlined, color: AppColors.inkFaint),
                                        ),
                                      );
                                    }
                                    return Container(
                                      color: AppColors.surface2,
                                      child: const Icon(Icons.place_outlined, color: AppColors.inkFaint),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stop.name,
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    stop.address,
                                    style: GoogleFonts.nunito(
                                      fontSize: 12,
                                      color: AppColors.inkSoft,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(
                                        'View details',
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.teal,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.teal),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (conflict != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE6C58B), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE65100)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                conflict!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF8A5A18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Divider(height: 1, thickness: 0.8, color: AppColors.moduleBorder.withOpacity(0.6)),
                    const SizedBox(height: 10),

                    // Bottom Bar: Clickable Time Pill + Modern Actions
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: onEditTimeRange,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isUnscheduled
                                    ? const Color(0xFFFFF8E1)
                                    : conflict != null
                                        ? const Color(0xFFFFF5E5)
                                        : const Color(0xFFEAF3EF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isUnscheduled
                                      ? const Color(0xFFFFE082)
                                      : conflict != null
                                          ? const Color(0xFFE6C58B)
                                          : AppColors.teal.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isUnscheduled
                                        ? Icons.access_time_rounded
                                        : conflict != null
                                            ? Icons.warning_amber_rounded
                                            : Icons.schedule_rounded,
                                    size: 14,
                                    color: isUnscheduled
                                        ? const Color(0xFFE65100)
                                        : conflict != null
                                            ? const Color(0xFF8A5A18)
                                            : AppColors.teal,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isUnscheduled
                                          ? 'Unscheduled • Tap to schedule'
                                          : (conflict != null
                                              ? '$startTimeStr – $endTimeStr (Conflict)'
                                              : '$startTimeStr – $endTimeStr'),
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isUnscheduled
                                            ? const Color(0xFFE65100)
                                            : conflict != null
                                                ? const Color(0xFF8A5A18)
                                                : AppColors.teal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                    color: isUnscheduled
                                        ? const Color(0xFFE65100)
                                        : conflict != null
                                            ? const Color(0xFFE65100)
                                            : AppColors.teal,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        _ActionButton(
                          icon: Icons.swap_horiz_rounded,
                          tooltip: 'Replace Place',
                          onTap: onReplace,
                          color: AppColors.inkSoft,
                          bgColor: AppColors.surface2,
                        ),
                        const SizedBox(width: 6),
                        _ActionButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Delete Place',
                          onTap: onDelete,
                          color: AppColors.error,
                          bgColor: AppColors.error.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildCategoryBadge(String category) {
    Color bg;
    Color fg;
    IconData icon;

    final lower = category.toLowerCase();
    if (lower.contains('food') || lower.contains('restaurant') || lower.contains('cafe')) {
      bg = const Color(0xFFFFF5E5);
      fg = const Color(0xFFE65100);
      icon = Icons.restaurant_rounded;
    } else if (lower.contains('night') || lower.contains('bar') || lower.contains('club')) {
      bg = const Color(0xFFEDE7F6);
      fg = const Color(0xFF512DA8);
      icon = Icons.nightlife_rounded;
    } else if (lower.contains('nature') || lower.contains('park')) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      icon = Icons.nature_rounded;
    } else {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
      icon = Icons.account_balance_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            category,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  String _resolveCategoryLabel(Place place) {
    final cat = place.category ?? '';
    if (cat.isNotEmpty) return cat;
    final types = place.types.map((t) => t.toLowerCase()).toSet();
    if (types.contains('night_club') || types.contains('bar')) return 'Nightlife';
    if (types.contains('restaurant') || types.contains('food')) return 'Restaurant';
    if (types.contains('cafe') || types.contains('bakery')) return 'Cafe';
    if (types.contains('park') || types.contains('natural_feature')) return 'Nature';
    if (types.contains('museum')) return 'Museum';
    return 'Landmark';
  }

  String _fmt(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  final Color bgColor;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}