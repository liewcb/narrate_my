import 'package:flutter/material.dart';
import 'package:narrate_my/view/Itinerary/widgets/layout_widgets.dart';
import 'package:narrate_my/view/Itinerary/widgets/travel_form_widgets.dart';

class SereneTravelerScreen extends StatelessWidget {
  const SereneTravelerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFF9F9F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const HeroHeader(),
                _buildFormContent(),
              ],
            ),
          ),
          const CustomAppBar(),
          const Positioned(bottom: 0, left: 0, right: 0, child: StickyFooter()),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    // Removed the "const" here so the stateful form widgets can rebuild dynamically!
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [ // Note: Keep const on individual items, or remove it entirely
          SectionTitle(title: "Itinerary Title"),
          ItineraryTitleField(),
          SizedBox(height: 32),

          SectionTitle(title: "Travel Dates"),
          TravelDatesSection(), // Now a stateful widget, clicking opens a calendar!
          SizedBox(height: 32),

          SectionTitle(title: "Exploration Time"),
          ExplorationTimeSection(), // Now clickable and swaps options
          SizedBox(height: 32),

          SectionTitle(title: "Travel Pace"),
          TravelPaceSection(), // Now clickable
          SizedBox(height: 32),

          SectionTitle(title: "Interests", subtitle: "Select multiple"),
          InterestsSection(), // Multiple selections now work
          SizedBox(height: 32),

          SectionTitle(title: "Additional Notes"),
          AdditionalNotesField(),
        ],
      ),
    );
  }
}