// lib/screens/my_itineraries_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../viewmodel/ItineraryModel/my_itineraries_vm.dart';
import 'manage_itinerary/manage_display_plan_screen.dart';
import 'destination_choice_screen.dart';  // for the FAB
import 'widgets/itinerary_card.dart';

class MyItinerariesScreen extends StatefulWidget {
  const MyItinerariesScreen({Key? key}) : super(key: key);

  @override
  State<MyItinerariesScreen> createState() => _MyItinerariesScreenState();
}

class _MyItinerariesScreenState extends State<MyItinerariesScreen> {
  final TextEditingController _searchController = TextEditingController();

  // Hardcoded user ID – replace with real auth later
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
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DestinationChoiceScreen(),
            ),
          );
        },
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text(
          "New Itinerary",
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.bg,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Title
              Text(
                "My Itineraries",
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 24),

              // Search Field
              TextField(
                controller: searchController,
                onChanged: vm.setSearchQuery,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: "Search your trips...",
                  hintStyle: GoogleFonts.nunito(
                    color: AppColors.inkFaint,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: AppColors.inkFaint, size: 20),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.moduleBorder, width: 1.5),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 24),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ["All", "Upcoming", "Ongoing", "Past"].map((filter) {
                    final isActive = vm.activeFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => vm.setFilter(filter),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.accent : AppColors.surface2,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            filter,
                            style: GoogleFonts.nunito(
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                              fontSize: 14,
                              color: isActive ? AppColors.bg : AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 32),

              // Content
              if (vm.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                    ),
                  ),
                )
              else if (vm.error != null)
                Card(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        "Failed to load trips: ${vm.error}",
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                )
              else if (filteredTrips.isEmpty)
                  Card(
                    color: AppColors.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "No trips found",
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Try searching for another destination or adjust your active filter.",
                              style: GoogleFonts.nunito(
                                fontSize: 14,
                                color: AppColors.inkFaint,
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
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
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