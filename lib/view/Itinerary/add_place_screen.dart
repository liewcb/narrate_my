import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../viewmodel/Itinerary/add_place_vm.dart';

class AddPlaceScreen extends StatefulWidget {
  final String itineraryId;
  final int dayIndex; // 0-based

  const AddPlaceScreen({
    Key? key,
    required this.itineraryId,
    required this.dayIndex,
  }) : super(key: key);

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddPlaceVM>(
      create: (_) => AddPlaceVM(
        itineraryId: widget.itineraryId,
        dayIndex: widget.dayIndex,
        explorationTime: 'Standard',
      )..load(),
      child: const _AddPlaceBody(),
    );
  }
}

class _AddPlaceBody extends StatelessWidget {
  const _AddPlaceBody();

  // Brand Colors
  static const _bg = AppColors.creamBg;
  static const _charcoal = AppColors.charcoal;
  static const _mutedText = AppColors.mutedText;
  static const _pineGreen = AppColors.pineGreen;
  static const _terracotta = AppColors.terracotta;
  static const _surfaceCard = AppColors.white;
  static const _surfaceInactive = AppColors.surfaceInactive;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: vm.isLoadingStops
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContextCards(vm),
                  const SizedBox(height: 32),
                  _buildFilterAndSearch(),
                  const SizedBox(height: 32),
                  _buildRecommendedList(context),
                  const SizedBox(height: 16),
                  _buildAddButton(context),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _bg.withOpacity(0.9),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: _charcoal),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Column(
        children: [
          Text(
            "Add a Place",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _charcoal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Day ${context.read<AddPlaceVM>().dayIndex + 1}",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _mutedText,
            ),
          ),
        ],
      ),
      actions: const [SizedBox(width: 48)],
    );
  }

  Widget _buildContextCards(AddPlaceVM vm) {
    final freeMinutes = vm.availableMinutes;
    final hours = freeMinutes ~/ 60;
    final mins = freeMinutes % 60;
    final freeText = hours > 0
        ? '$hours hr${mins > 0 ? ' $mins min' : ''}'
        : '$mins min';

    return Column(
      children: [
        // Time Available Card (computed from the exploration window)
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surfaceInactive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule, color: AppColors.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TIME AVAILABLE",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: _mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$freeText free',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: freeMinutes > 0 ? _charcoal : _terracotta,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${vm.existingStops.length} stop(s) already on Day ${vm.dayIndex + 1}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: _mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterAndSearch() {
    return Column(
      children: [
        // Search Bar
        Container(
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
            decoration: InputDecoration(
              hintText: "Search places",
              hintStyle: TextStyle(color: _mutedText),
              prefixIcon: Icon(Icons.search, color: _mutedText),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedList(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "RECOMMENDED NEARBY",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: _mutedText,
          ),
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: vm.candidates.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final option = vm.candidates[index];
            return _buildPlaceCard(context, option);
          },
        ),
      ],
    );
  }

  Widget _buildPlaceCard(BuildContext context, AddPlaceOption option) {
    final vm = context.watch<AddPlaceVM>();
    final added = vm.isSelected(option.placeId);
    final hours = option.durationMinutes ~/ 60;
    final mins = option.durationMinutes % 60;
    final durText = hours > 0 ? '$hours hr${mins > 0 ? ' $mins min' : ''}' : '$mins min';

    return Container(
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
      child: Row(
        children: [
          // Image
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _surfaceInactive,
              image: option.imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(option.imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: option.imageUrl == null
                ? const Icon(Icons.place, color: _mutedText)
                : null,
          ),
          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.name,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _charcoal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  option.category,
                  style: TextStyle(fontSize: 12, color: _mutedText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // Bottom Row (Duration + Add Button)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hourglass_empty, size: 16, color: _terracotta),
                        const SizedBox(width: 4),
                        Text(
                          durText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _terracotta,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: added ? _pineGreen : _terracotta,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () => vm.toggleSelection(option.placeId),
                      child: Text(
                        added ? "Selected" : "Add",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildAddButton(BuildContext context) {
    final vm = context.watch<AddPlaceVM>();
    final canAdd = vm.selectedPlaceIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: canAdd && !vm.isSaving
              ? () async {
                  final result = await vm.addPlaces();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          result.success
                              ? 'Added ${result.addedStops.length} place(s) to Day ${vm.dayIndex + 1}.'
                              : (result.message ?? 'Could not add place.'),
                        ),
                      ),
                    );
                  if (result.success) Navigator.maybePop(context);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: canAdd ? _pineGreen : _surfaceInactive,
            foregroundColor: canAdd ? Colors.white : _mutedText,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          icon: vm.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 20),
          label: Text(
            vm.isSaving
                ? 'Adding...'
                : 'Add ${vm.selectedPlaceIds.length} place(s) to Itinerary',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
