import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../model/business_logic/itinerary_service/custom_place_service.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/business_logic/itinerary_service/schedule_construction_service.dart';
import '../../model/entities/coordinates.dart';
import '../../model/entities/itinerary_stop.dart';
import '../../viewmodel/Itinerary/edit_itinerary_vm.dart';
import './recommended_places_screen.dart';
import './widgets/change_location_picker_sheet.dart';

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

  void _selectDay(int index) {
    if (index == _selectedDayIndex) return;

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
            snippet: '${_fmt(stop.startTime)} – ${_fmt(stop.endTime)}',
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

  Future<void> _handleBack() async {
    if (_selectedDayIndex < 0 || !_vm.hasChanges || _changesApplied) {
      Navigator.pop(context, null);
      return;
    }
    final discard = await showConfirmationDialog(
      context: context,
      title: 'Discard changes?',
      message: 'Your itinerary edits have not been applied.',
      confirmLabel: 'Discard',
      icon: Icons.warning_amber_rounded,
      iconBgColor: AppColors.error.withOpacity(0.12),
      iconColor: AppColors.error,
      confirmColor: AppColors.error,
    );
    if (discard == true && mounted) {
      Navigator.pop(context, null);
    }
  }

  void _reviewChanges() {
    if (_selectedDayIndex < 0) return;

    final errors = _vm.validate();
    if (errors.isNotEmpty) {
      _showProblem(_friendlyValidationError(errors.first));
      return;
    }
    _vm.applyChanges();
    if (_vm.appliedResult != null) {
      _changesApplied = true;
      Navigator.pop(context, _vm.appliedResult);
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
      backgroundColor: AppColors.bg,
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

    final ok = await _vm.removeStopByPlaceId(stop.placeId);
    if (mounted && ok) {
      _fitMapBounds();
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
      } else {
        _showProblem(_vm.error ?? 'Schedule conflict detected. Try shortening duration or adjusting adjacent stops.');
      }
    }
  }

  // ─── Main Screen Build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selectedDayIndex >= 0 ? _vm : Listenable.merge([]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.bg,
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
                    _buildDaySelector(),
                    const SizedBox(height: 12),
                    if (_selectedDayIndex == -1) ...[
                      _buildAllHeader(),
                      const SizedBox(height: AppSpacing.cardPadding),
                      _buildAllDaysList(),
                    ] else ...[
                      _buildHeader(),
                      const SizedBox(height: AppSpacing.cardPadding),
                      _buildMapPreview(),
                      const SizedBox(height: AppSpacing.cardPadding),
                      _buildStopsList(),
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
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.ink),
        onPressed: _handleBack,
      ),
      title: Text(
        widget.title.isEmpty ? 'Edit Itinerary' : widget.title,
        style: AppTextStyles.pageTitle,
      ),
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
          final isAll = index == 0;
          final dayIndex = isAll ? -1 : index - 1;
          final isActive = dayIndex == _selectedDayIndex;

          return GestureDetector(
            key: _tabKeys[index],
            onTap: () => _selectDay(dayIndex),
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
                  isAll ? 'All' : 'Day ${dayIndex + 1}',
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
    final dateFmt = DateFormat('d MMM');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day ${_vm.dayNumber} · ${dateFmt.format(_vm.dayDate)} · ${_vm.title}',
          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Reorder, edit or add places to your day.',
          style: AppTextStyles.labelSm,
        ),
      ],
    );
  }

  Widget _buildAllHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All days · ${widget.title}',
          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Overview of your full itinerary. Tap a day to edit it.',
          style: AppTextStyles.labelSm,
        ),
      ],
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

  Widget _buildAllDaysList() {
    final days = widget.result.scheduledDays ?? [];
    return Column(
      children: List.generate(days.length, (i) {
        return ListTile(
          title: Text(
            'Day ${i + 1}',
            style: AppTextStyles.bodyLg,
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.inkSoft),
          onTap: () => _selectDay(i),
        );
      }),
    );
  }

  Widget _buildStopsList() {
    final stops = _vm.stops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STOPS',
          style: AppTextStyles.sectionLabel,
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
            return _StopItem(
              key: ValueKey(stop.placeId),
              stop: stop,
              number: index + 1,
              onEditTimeRange: () => _pickTimeRange(index),
              onReplace: () => _showReplacePicker(index),
              onDelete: () => _removeStop(index),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFloatingAddButton() {
    return FloatingActionButton(
      onPressed: _showAddPicker,
      backgroundColor: AppColors.green,
      child: const Icon(Icons.add, color: AppColors.bg, size: 26),
    );
  }

  Widget _buildBottomButton() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          color: AppColors.bg.withOpacity(0.9),
          child: ElevatedButton(
            onPressed: _reviewChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bg,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              'Review Changes',
              style: AppTextStyles.button,
            ),
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

// ─── Refined De-Cluttered Place Card Item ─────────────────────

class _StopItem extends StatelessWidget {
  final EditableStop stop;
  final int number;
  final VoidCallback onEditTimeRange;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  const _StopItem({
    super.key,
    required this.stop,
    required this.number,
    required this.onEditTimeRange,
    required this.onReplace,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final startTimeStr = _fmt(stop.startTime);
    final endTimeStr = _fmt(stop.endTime);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Number Badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stop.isMustVisit ? AppColors.accent : AppColors.surface2,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: stop.isMustVisit ? AppColors.bg : AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.moduleBorder),
                boxShadow: const [
                  BoxShadow(
                    color: AppShadows.card,
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          stop.place.placeImageUrl ?? '',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 56,
                            height: 56,
                            color: AppColors.surface2,
                            child: const Icon(Icons.place_outlined, color: AppColors.inkFaint),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stop.name,
                              style: GoogleFonts.nunito(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
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
                          ],
                        ),
                      ),
                      const Icon(Icons.drag_handle_rounded, color: AppColors.inkFaint, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 1, color: AppColors.moduleBorder),
                  const SizedBox(height: 8),

                  // Bottom Bar: Tap Time Badge + Clean Actions
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: onEditTimeRange,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.teal.withOpacity(0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$startTimeStr - $endTimeStr',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.teal,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_outlined, size: 12, color: AppColors.teal),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Action Buttons (Swap & Delete)
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
                        bgColor: AppColors.error.withOpacity(0.12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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