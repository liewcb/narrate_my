import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../model/business_logic/itinerary_service/generation_pipeline_service.dart';
import '../../model/entities/place.dart';
import '../../viewmodel/Itinerary/edit_itinerary_vm.dart';
import 'add_custom_stop_screen.dart';

/// Edits a single day of the generated itinerary during preview/review.
/// Now supports switching between days via a day selector.
class EditItineraryScreen extends StatefulWidget {
  final ItineraryResult result;
  final String title;
  final int dayNumber;
  final DateTime tripStartDate;
  final String explorationTime;
  final List<String> mustVisitPlaceIds;

  const EditItineraryScreen({
    super.key,
    required this.result,
    required this.title,
    required this.dayNumber,
    required this.tripStartDate,
    required this.explorationTime,
    required this.mustVisitPlaceIds,
  });

  @override
  State<EditItineraryScreen> createState() => _EditItineraryScreenState();
}

class _EditItineraryScreenState extends State<EditItineraryScreen> {
  late EditItineraryViewModel _vm;
  bool _changesApplied = false;
  GoogleMapController? _mapController;

  // ─── Multi-day state ────────────────────────────────────────
  late int _selectedDayIndex;
  late final int _totalDays;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _totalDays = widget.result.scheduledDays?.length ?? 0;
    _selectedDayIndex = _totalDays > 0
        ? (widget.dayNumber - 1).clamp(0, _totalDays - 1)
        : 0;
    _initViewModel();
  }

  void _initViewModel() {
    _vm = EditItineraryViewModel(
      result: widget.result,
      dayIndex: _selectedDayIndex,
      tripStartDate: widget.tripStartDate,
      explorationTime: widget.explorationTime,
      mustVisitPlaceIds: widget.mustVisitPlaceIds,
      title: widget.title,
    );
    _changesApplied = false;
  }

  @override
  void dispose() {
    _vm.dispose();
    _scrollController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── Day switching ──────────────────────────────────────────
  void _selectDay(int index) {
    if (index == _selectedDayIndex) return;

    try {
      // 1. Keep a temporary reference to the old VM so we can dispose of it safely later
      final oldVm = _vm;

      setState(() {
        _selectedDayIndex = index;

        // 2. Initialize the new VM immediately so the widget tree binds to it on the next frame
        _vm = EditItineraryViewModel(
          result: widget.result,
          dayIndex: index,
          tripStartDate: widget.tripStartDate,
          explorationTime: widget.explorationTime,
          mustVisitPlaceIds: widget.mustVisitPlaceIds,
          title: widget.title,
        );
        _changesApplied = false;
      });

      // 3. Handle cleanup, maps, and scrolling AFTER the widget tree has rebuilt
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Safely dispose of the old VM now that nothing is listening to it
        oldVm.dispose();

        // Update map bounds for the new day
        _fitMapBounds();

        // Smoothly scroll back to the top of the content
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      debugPrint('[EditItineraryScreen] Day switch failed: $e');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to load Day ${index + 1}. Please try again.'),
          ),
        );
    }
  }

  // ─── Map helpers ──────────────────────────────────────────

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
        color: AppColors.tealGreen,
        width: 4,
      ),
    };
  }

  void _fitMapBounds() {
    if (_mapController == null || _vm.stops.isEmpty) return;
    if (_vm.stops.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_vm.stops.first.place.latitude, _vm.stops.first.place.longitude),
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

  // ─── Navigation & Save (unchanged) ─────────────────────────

  Future<void> _handleBack() async {
    if (!_vm.hasChanges || _changesApplied) {
      Navigator.pop(context, null);
      return;
    }
    final discard = await showConfirmationDialog(
      context: context,
      title: 'Discard changes?',
      message: 'Your itinerary edits have not been applied.',
      confirmLabel: 'Discard',
      icon: Icons.warning_amber_rounded,
      iconBgColor: const Color(0xFFFDE8E8),
      iconColor: AppColors.dangerText,
      confirmColor: AppColors.dangerText,
    );
    if (discard == true && mounted) {
      Navigator.pop(context, null);
    }
  }

  void _reviewChanges() {
    final errors = _vm.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _friendlyValidationError(errors.first),
            ),
          ),
        );
      return;
    }
    _vm.applyChanges();
    if (_vm.appliedResult != null) {
      _changesApplied = true;
      // Show the confirmation BEFORE popping: the root ScaffoldMessenger
      // keeps it visible on the previous screen.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Your itinerary changes were applied.'),
            duration: Duration(seconds: 2),
          ),
        );
      Navigator.pop(context, _vm.appliedResult);
    }
  }

  Future<void> _pickStartTime(int index) async {
    final stop = _vm.stops[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: stop.startTime.hour, minute: stop.startTime.minute),
    );
    if (picked == null) return;
    if (!mounted) return;
    final ok = _vm.setStartTime(index, picked);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Time updated for ${stop.name}. '
                'The rest of your schedule has been adjusted.'),
            duration: const Duration(seconds: 2),
          ),
        );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _vm.error ??
                  'This time does not fit the day\'s schedule. Please pick another time.',
            ),
          ),
        );
    }
  }
  Future<void> _showAddPicker() async {
    final candidates = _vm.availableCandidates;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No additional candidates available.')),
        );
      return;
    }

    final selected = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => AddPlaceScreen(
          candidates: candidates,
          title: 'Add a Place',
          subtitle: 'Choose from available candidates',
        ),
      ),
    );

    if (selected != null && mounted) {
      final ok = _vm.addCandidate(selected);
      _fitMapBounds();
      if (ok) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${selected.placeName} added to Day '
                  '${_vm.dayNumber}.'),
              duration: const Duration(seconds: 2),
            ),
          );
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _vm.error ??
                    'Cannot add ${selected.placeName} because there is not '
                    'enough time remaining in the day.',
              ),
            ),
          );
      }
    }
  }

  Future<void> _showReplacePicker(int index) async {
    final currentPlaceId = _vm.stops[index].placeId;
    final candidates = _vm.availableCandidates
        .where((p) => p.placeId != currentPlaceId)
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No replacement candidates available.')),
        );
      return;
    }

    final selected = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (ctx) => AddPlaceScreen(
          candidates: candidates,
          title: 'Replace Stop',
          subtitle: 'Select a replacement from candidates',
        ),
      ),
    );

    if (selected != null && mounted) {
      final ok = _vm.replaceStop(index, selected);
      _fitMapBounds();
      if (ok) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Stop replaced with ${selected.placeName}.'),
              duration: const Duration(seconds: 2),
            ),
          );
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _vm.error ?? 'Unable to replace this stop. The replacement '
                    'does not fit the day\'s schedule.',
              ),
            ),
          );
      }
    }
  }

  Future<void> _removeStop(int index) async {
    final stop = _vm.stops[index];
    if (stop.isMustVisit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This place is a must-visit and cannot be removed.'),
          ),
        );
      return;
    }

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Remove "${stop.name}"?',
      message: 'This stop will be removed from Day ${_vm.dayNumber}.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;

    final ok = _vm.removeStop(index);
    if (!mounted) return;
    if (ok) {
      _fitMapBounds();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${stop.name} removed from Day ${_vm.dayNumber}.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _vm.error ?? 'Cannot remove this stop. Please try again.',
            ),
          ),
        );
    }
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.warmBg,
          appBar: _buildAppBar(),
          body: _totalDays == 0
              ? _buildEmptyState()
              : Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(), // <-- Force scrolling mechanics to remain alive
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDaySelector(),
                    const SizedBox(height: 12),
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildMapPreview(),
                    const SizedBox(height: 24),
                    _buildStopsList(),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
              Positioned(
                bottom: 100,
                right: 20,
                child: _buildFloatingAddButton(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No itinerary days available.',
        style: TextStyle(fontSize: 16, color: AppColors.mutedText),
      ),
    );
  }

  // ─── App Bar (unchanged) ────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.warmBg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
        onPressed: _handleBack,
      ),
      title: Text(
        widget.title.isEmpty ? 'Edit Itinerary' : widget.title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.charcoal,
          letterSpacing: -0.02,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text(
            'Done',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.terracottaDark,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Day Selector (improved) ───────────────────────────────

  Widget _buildDaySelector() {
    if (_totalDays <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _totalDays,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isActive = index == _selectedDayIndex;
          return GestureDetector(
            onTap: () => _selectDay(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.terracottaDark : AppColors.surfaceInactive,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isActive ? AppColors.terracottaDark : AppColors.taupe.withOpacity(0.3),
                ),
              ),
              child: Center(
                child: Text(
                  'Day ${index + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive ? Colors.white : AppColors.charcoal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────

  Widget _buildHeader() {
    final dateFmt = DateFormat('d MMM');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day ${_vm.dayNumber} · ${dateFmt.format(_vm.dayDate)} · ${_vm.title}',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Reorder, edit or add places to your day.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }

  // ─── Map Preview (forces rebuild on day change) ────────────

  Widget _buildMapPreview() {
    final initialPos = _vm.stops.isNotEmpty
        ? LatLng(_vm.stops.first.place.latitude, _vm.stops.first.place.longitude)
        : const LatLng(3.1390, 101.6869);

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            GoogleMap(
              // 🔑 Force map to rebuild when day changes
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
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.pineDark.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '${_vm.stops.length} Stops Planned',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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

  // ─── Stops List (with empty state) ─────────────────────────

  Widget _buildStopsList() {
    final stops = _vm.stops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STOPS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppColors.mutedText,
          ),
        ),
        const SizedBox(height: 12),
        if (stops.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.map_outlined, size: 40, color: AppColors.mutedText),
                  const SizedBox(height: 8),
                  Text(
                    'No stops for this day',
                    style: TextStyle(fontSize: 14, color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showAddPicker,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a place'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.terracottaDark,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Stack(
            children: [
              Positioned(
                left: 17,
                top: 16,
                bottom: 16,
                child: SizedBox(
                  width: 2,
                  child: CustomPaint(
                    painter: _DashedLinePainter(),
                  ),
                ),
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stops.length,
                onReorder: (oldIndex, newIndex) {
                  final ok = _vm.reorder(oldIndex, newIndex);
                  _fitMapBounds();
                  if (ok) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Stop order updated.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                  } else {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            _vm.error ??
                                'That order does not allow enough travel time '
                                'between these stops.',
                          ),
                        ),
                      );
                  }
                },
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  return _StopItem(
                    key: ValueKey(stop.placeId),
                    stop: stop,
                    number: index + 1,
                    isFirst: index == 0,
                    isLast: index == stops.length - 1,
                    onEditTime: () => _pickStartTime(index),
                    onReplace: () => _showReplacePicker(index),
                    onDelete: () => _removeStop(index),
                  );
                },
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (stops.isNotEmpty)
          GestureDetector(
            onTap: _showAddPicker,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.terracottaDark, width: 2),
                      color: AppColors.warmBg,
                    ),
                    child: const Icon(Icons.add, size: 20, color: AppColors.terracottaDark),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Floating Add Button ────────────────────────────────────

  Widget _buildFloatingAddButton() {
    return FloatingActionButton(
      onPressed: _showAddPicker,
      backgroundColor: AppColors.tealGreen,
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }

  // ─── Bottom Button ──────────────────────────────────────────

  Widget _buildBottomButton() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warmBg.withOpacity(0.9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A004D40),
                offset: Offset(0, -4),
                blurRadius: 20,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _reviewChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.terracottaDark,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Review Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Converts a validation error message into a user-friendly string.
  /// Messages that are already friendly are passed through.
  String _friendlyValidationError(String msg) {
    // Add a short prefix for common patterns.
    if (msg.startsWith('Stop "') && msg.contains('has an invalid time')) {
      return 'One of the stops has an invalid time sequence.';
    }
    if (msg.contains('exploration time')) {
      return 'This change makes the schedule exceed the available time for the day.';
    }
    if (msg.contains('travel time')) {
      return 'That order does not allow enough travel time between these stops.';
    }
    if (msg.contains('Add at least one stop')) {
      return 'You need at least one stop to finish editing.';
    }
    return msg;
  }
}

// ─── Stop Item, DashedLinePainter (unchanged) ────────────────

class _StopItem extends StatelessWidget {
  final EditableStop stop;
  final int number;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEditTime;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  const _StopItem({
    super.key,
    required this.stop,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.onEditTime,
    required this.onReplace,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final h = stop.durationMinutes ~/ 60;
    final m = stop.durationMinutes % 60;
    final durationLabel = h > 0 && m > 0
        ? '${h}h ${m}m'
        : h > 0
        ? '${h}h'
        : '${m}m';
    final timeLabel = '${_fmt(stop.startTime)} – ${_fmt(stop.endTime)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stop.isMustVisit
                  ? AppColors.terracottaDark
                  : (isFirst ? AppColors.tealGreen : AppColors.surfaceInactive),
              border: isFirst || stop.isMustVisit
                  ? null
                  : Border.all(color: AppColors.taupe.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: (isFirst || stop.isMustVisit) ? Colors.white : AppColors.charcoal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stop.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.charcoal,
                              ),
                            ),
                            if (stop.isMustVisit) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Must-visit',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.dangerText),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              timeLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: onEditTime,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceInactive,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.schedule, size: 20, color: AppColors.warmBrown),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onReplace,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceInactive,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.swap_horiz, size: 20, color: AppColors.warmBrown),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onDelete,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.dangerBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete_outline, size: 20, color: AppColors.dangerText),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.drag_handle, color: AppColors.taupe),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, size: 20, color: AppColors.terracottaDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stop.address,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.warmBrown,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 20, color: AppColors.terracottaDark),
                      const SizedBox(width: 8),
                      Text(
                        'Visit: $durationLabel',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.warmBrown,
                        ),
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
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.taupe
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashHeight = 6.0;
    const dashSpace = 6.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}