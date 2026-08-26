import 'package:flutter/material.dart';

import '../../view/Itinerary/manage_itinerary/add_custom_screen.dart';
import '../../view/Itinerary/my_itineraries_screen.dart';
import '../../view/Itinerary/step1_where_to_screen.dart';


final Map<String, WidgetBuilder> itineraryRoutes = {
  // Main list (bottom-nav tab)
  '/itinerary': (_) => const MyItinerariesScreen(),

  // Step 1: Where to travel? (wizard starts here; steps 2-5 are
  // navigated with MaterialPageRoute so the TripDraft flows along).
  '/itinerary/where-to': (_) => const Step1WhereToScreen(),

  // Adding a custom stop to a generated itinerary
  '/itinerary/add-custom-stop': (_) => const AddCustomStopScreen(),
};
