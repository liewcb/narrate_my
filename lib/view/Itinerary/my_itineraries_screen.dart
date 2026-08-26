// lib/screens/my_itineraries_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodel/ItineraryModel/my_itineraries_vm.dart';
import 'manage_itinerary/manage_display_plan_screen.dart';
import 'widgets/itinerary_card.dart';

class MyItinerariesScreen extends StatefulWidget {
  const MyItinerariesScreen({Key? key}) : super(key: key);

  @override
  State<MyItinerariesScreen> createState() => _MyItinerariesScreenState();
}

class _MyItinerariesScreenState extends State<MyItinerariesScreen> {
  final TextEditingController _searchController = TextEditingController();

  static const String _userId = '252f0924-192c-42fe-8643-881da7bbf285';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MyItinerariesVM>(
      create: (_) => MyItinerariesVM(userId: _userId)..load(),
      // Removed the hardcoded colors from the widget tree; relying entirely on AppTheme
      child: _ItinerariesView(searchController: _searchController),
    );
  }
}

class _ItinerariesView extends StatelessWidget {
  final TextEditingController searchController;

  const _ItinerariesView({required this.searchController});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyItinerariesVM>();
    final filteredTrips = vm.filteredTrips;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/itinerary/where-to');
        },
        backgroundColor: AppColors.primaryTerracotta,
        elevation: 2,
        // Ensures the FAB matches the full-width pill button shape design language
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        icon: const Icon(Icons.add, color: AppColors.onPrimary),
        label: const Text(
          "New Itinerary",
          style: AppTextStyles.button,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // Uses the fluid grid screen margin (20px) from the theme
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.sectionGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Typography Hierarchy: Uses predefined pageTitle without hardcoded overrides
              const Text(
                "My Itineraries",
                style: AppTextStyles.pageTitle,
              ),

              const SizedBox(height: AppSpacing.sectionGap),

              // Simplification: The global InputDecorationTheme now handles the
              // white background, 16px radius, and borderless design automatically.
              TextField(
                controller: searchController,
                onChanged: vm.setSearchQuery,
                style: AppTextStyles.bodyLg,
                decoration: InputDecoration(
                  hintText: "Search your trips...",
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                ),
              ),

              const SizedBox(height: AppSpacing.sectionGap),

              // Filter Controls (Choice Pills mapping to the new Dark Pine / Muted Gray styling)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ["All", "Upcoming", "Ongoing", "Past"].map((filter) {
                    final isActive = vm.activeFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.componentGap),
                      child: GestureDetector(
                        onTap: () => vm.setFilter(filter),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.pillPaddingX,
                            vertical: AppSpacing.pillPaddingY,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.secondaryActive
                                : AppColors.surfaceInactive,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            filter,
                            style: AppTextStyles.bodySm.copyWith(
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                              color: isActive
                                  ? AppColors.onSecondary
                                  : AppColors.textInactive,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 32),

              // Content Section
              if (vm.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primaryTerracotta),
                  ),
                )
              else if (vm.error != null)
              // Replaced hardcoded containers with the Theme's Card widget
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        "Failed to load trips: ${vm.error}",
                        style: AppTextStyles.bodyLg.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else if (filteredTrips.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding * 1.5),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "No trips found",
                              style: AppTextStyles.bodyLg.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.componentGap),
                            Text(
                              "Try searching for another destination or adjust your active filter.",
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredTrips.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardPadding),
                    itemBuilder: (context, index) {
                      final trip = filteredTrips[index];
                      return ItineraryCard(
                        itinerary: trip,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageDisplayPlanScreen(
                                itineraryId: trip.itineraryId,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

              const SizedBox(height: 88),
            ],
          ),
        ),
      ),
    );
  }
}