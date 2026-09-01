import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/colors.dart';
import '../../model/entities/destination.dart';
import '../../viewmodel/Itinerary/destination_choice_vm.dart';
import 'trip_customization_screen.dart';
import 'package:narrate_my/view/Itinerary/widgets/wizard_app_bar.dart';

class DestinationChoiceScreen extends StatefulWidget {
  const DestinationChoiceScreen({super.key});

  @override
  State<DestinationChoiceScreen> createState() => _DestinationChoiceScreenState();
}

class _DestinationChoiceScreenState extends State<DestinationChoiceScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Step1WhereToViewModel>(
      create: (_) => Step1WhereToViewModel()..loadDestinations(),
      child: const _Step1WhereToBody(),
    );
  }
}

class _Step1WhereToBody extends StatelessWidget {
  const _Step1WhereToBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<Step1WhereToViewModel>();
    final selected = vm.selectedDestinations;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      // Replaced internal _AppBar with shared WizardAppBar
      appBar: const WizardAppBar(step: 1),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 140),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Replaced internal _ProgressBar with shared WizardProgressBar
                  const WizardProgressBar(activeSteps: 1),
                  const SizedBox(height: 32),
                  const _Header(),
                  const SizedBox(height: 24),
                  _SearchBar(
                    onChanged: vm.searchDestinations,
                  ),
                  const SizedBox(height: 32),
                  _SelectedChips(
                    selected: selected,
                    onRemove: (dest) => vm.toggleSelection(dest),
                  ),
                  const SizedBox(height: 40),
                  if (vm.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    _PopularGrid(
                      destinations: vm.filteredDestinations,
                      isSelected: (dest) => vm.isSelected(dest),
                      onToggle: (dest) => vm.toggleSelection(dest),
                    ),
                ],
              ),
            ),
          ),
          _StickyFooter(
            count: selected.length,
            label: 'Continue to Trip Dates',
            onContinue: () {
              try {
                // Build validated draft from ViewModel
                final draft = vm.buildTripDraft();

                // Navigate to Step 2 with draft
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripCustomizationScreen(
                      draft: draft,
                    ),
                  ),
                );
              } catch (e) {
                // Show validation error from ViewModel
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceFirst('Bad state: ', '')),
                      backgroundColor: Colors.red,
                    ),
                  );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── Private sub‑widgets ──────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Where do you want to travel?",
          style: TextStyle(
            fontFamily: 'Playfair Display',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.brandCharcoal,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Select one or more destinations to build your itinerary.",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: AppColors.outline,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0A004D40), offset: Offset(0, 4), blurRadius: 20),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.brandGreen),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search cities, islands, regions...',
                hintStyle: TextStyle(color: AppColors.outlineLight, fontSize: 16),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 16, color: AppColors.brandCharcoal),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedChips extends StatelessWidget {
  final List<Destination> selected;
  final ValueChanged<Destination> onRemove;
  const _SelectedChips({required this.selected, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR ROUTE (${selected.length} Selected)',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: 12),
        if (selected.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: selected.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final dest = selected[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        dest.destinationName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => onRemove(dest),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        else
          const Text(
            'No destinations selected yet.',
            style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.outlineLight),
          ),
      ],
    );
  }
}

class _PopularGrid extends StatelessWidget {
  final List<Destination> destinations;
  final bool Function(Destination) isSelected;
  final ValueChanged<Destination> onToggle;

  const _PopularGrid({
    required this.destinations,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POPULAR IN MALAYSIA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: 16),
        if (destinations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No destinations found.',
                style: TextStyle(color: AppColors.outlineLight),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: destinations.length,
            itemBuilder: (_, i) {
              final dest = destinations[i];
              final selected = isSelected(dest);
              return GestureDetector(
                onTap: () => onToggle(dest),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? AppColors.brandGreen : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: selected
                        ? null
                        : const [
                      BoxShadow(
                        color: Color(0x0A004D40),
                        offset: Offset(0, 4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          dest.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.outlineLight,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.8),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.6],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: selected
                              ? Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.brandGreen,
                            ),
                          )
                              : Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.6),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Text(
                            dest.destinationName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _StickyFooter extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onContinue;

  const _StickyFooter({
    required this.count,
    required this.label,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = count > 0; // Button enabled only when at least 1 destination selected

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 32,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.creamBg.withOpacity(0.0),
              AppColors.creamBg.withOpacity(1.0),
            ],
            stops: const [0.0, 0.7],
          ),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandTerracotta,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 4,
            shadowColor: AppColors.brandTerracotta.withOpacity(0.3),
          ),
          onPressed: isEnabled ? onContinue : null, // ✅ Disabled when no destinations
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$label ($count Places)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}